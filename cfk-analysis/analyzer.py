"""
CFK Bundle Analyzer - Core analysis engine
Analyzes Confluent for Kubernetes support bundles for common issues
"""

import gzip
import os
import re
import json
import sys
try:
    import yaml
except ImportError:
    sys.stderr.write(
        "error: PyYAML is required by cfk-analysis but is not installed.\n"
        "       Install it with: pip3 install -r "
        + os.path.join(os.path.dirname(__file__), "requirements.txt") + "\n"
        "       (or: pip3 install pyyaml)\n"
    )
    sys.exit(64)
from datetime import datetime
from typing import Dict, List, Any, Optional

import environment
import kraft_migration
import runbooks

# known causes shared with tools/log-analyzer/log_report.py: tools/report-common of the repository, mounted in
# /tmp/report-common by playground analyze logs (CFK support bundle)
for _path in (os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "tools", "report-common"), "/tmp/report-common"):
    if os.path.isfile(os.path.join(_path, "known_causes.py")):
        sys.path.insert(0, _path)
        break
import known_causes  # noqa: E402
# patterns that sort a record into a category but explain nothing (any ConnectException, any Kafka exception)
_CATCH_ALL = {c['name'] for c in known_causes.KNOWN_CAUSES if c.get('hint', True) is False}


# Log files: foo.log, foo.txt, rotated foo.log.1 / foo.log.2026-10-12, and their .gz
_TEXT_FILE_RE = re.compile(r'\.(?:log|txt|out)(?:\.[\w-]+)?(?:\.gz)?$|\.log\.gz$', re.IGNORECASE)
_YAML_FILE_RE = re.compile(r'\.(?:ya?ml|json)$', re.IGNORECASE)

# Only lines with an explicit level count, like `playground analyze logs`:
# log4j ` ERROR ` / `[ERROR]`, logfmt `level=error`, JSON `"level":"error"`, klog `E1012 `.
# The bare form is upper case only, so `Warning` rows of `kubectl get events` are not log records.
_LEVEL_RE = re.compile(
    r'(?:^|[\s\[|])(FATAL|SEVERE|CRITICAL|ERROR|WARN|WARNING)(?:[\s\]|:]|$)'
    r'|(?i:level=(fatal|error|warn|warning|panic|dpanic)\b)'
    r'|(?i:"level"\s*:\s*"(fatal|error|warn|warning|panic|dpanic)")'
    r'|^([FEW])\d{4} \d{2}:\d{2}:\d{2}'
)
_KLOG_LEVEL = {'F': 'FATAL', 'E': 'ERROR', 'W': 'WARN'}

# Cache key of _classify: digits replaced one for one by 0 (same length, so `.{0,N}` match the same), which folds
# records that only differ by timestamps, offsets or ids. Texts with the only digits of the patterns are kept as is.
_CLASSIFY_DIGITS = str.maketrans('123456789', '000000000')
_PATTERN_DIGITS_RE = re.compile(r'40[13]|509')

# Uncaught exception head: "org.foo.BarException: msg", "Exception in thread ...", "Caused by: ..."
_EXCEPTION_HEAD_RE = re.compile(
    r'^(?:Exception in thread "[^"]*" )?(?:[a-z_$][\w$]*\.)+[A-Z][\w$]*(?:Exception|Error)(?::|$)'
)
_CAUSED_BY_RE = re.compile(r'^\s*Caused by:\s*(.*)')
_STACK_FRAME_RE = re.compile(r'^\s+at\s|^\s*\.\.\. \d+ (?:more|common frames omitted)|^\s*Suppressed:')
# A line that starts a new log record (timestamp or level first)
_RECORD_START_RE = re.compile(r'^\s*[\[{]?\s*(?:\d{4}-\d{2}-\d{2}|\d{2}:\d{2}:\d{2}|[FEWI]\d{4} |"?level"?)')
_NOISE_RE = re.compile(r'log4j:WARN|SLF4J:')

_SEVERITY_ORDER = {'critical': 0, 'high': 1, 'medium': 2, 'low': 3}

# Pod symptoms of events and kubectl output that a pod recovers from (readiness probe failing while Kafka starts,
# back-off of a container restarted before its dependencies were up): low when the pod is Running and Ready in the
# bundle with fewer restarts than the "restarted N times" finding
_TRANSIENT_CATEGORIES = {'Health Check Issues', 'Pod Failures'}
_TRANSIENT_MAX_RESTARTS = 3
_EVENT_POD_RE = re.compile(r'\bpod/([a-z0-9][a-z0-9.-]*)', re.IGNORECASE)

# Phases / states that are healthy (or normal transients) on CFK CRs
_GOOD_CR_STATES = {'RUNNING', 'CREATED', 'SUCCEEDED', 'SUCCESS', 'READY', 'ACTIVE', 'COMPLETED', 'UP', 'HEALTHY'}

# Waiting reasons that are normal transients, not problems
_TRANSIENT_WAITING = {'ContainerCreating', 'PodInitializing'}

# Components an issue is attributed to (--component, HTML filter). `other` = not a CFK component
# (nodes, PVs, unknown pods). Folder names of `kubectl confluent support-bundle`: cluster-resources/<type>/<name>/
COMPONENTS = ('kafka', 'kraftcontroller', 'zookeeper', 'connect', 'schemaregistry', 'ksqldb',
              'controlcenter', 'kafkarestproxy', 'operator', 'other')
_KIND_COMPONENT = {
    'kafka': 'kafka', 'kafkatopic': 'kafka', 'kafkarestclass': 'kafka', 'clusterlink': 'kafka',
    'confluentrolebinding': 'kafka', 'kraftcontroller': 'kraftcontroller', 'zookeeper': 'zookeeper',
    'connect': 'connect', 'connector': 'connect', 'schemaregistry': 'schemaregistry',
    'schema': 'schemaregistry', 'schemaexporter': 'schemaregistry', 'ksqldb': 'ksqldb',
    'controlcenter': 'controlcenter', 'kafkarestproxy': 'kafkarestproxy', 'kraftmigrationjob': 'kraftcontroller',
}
# CRs of the applications of a cluster (a subject, a topic, a role binding…): their instance is the cluster they
# belong to (spec.*ClusterRef), not their own name
_APPLICATION_KINDS = {'kafkatopic', 'kafkarestclass', 'clusterlink', 'confluentrolebinding', 'connector', 'schema',
                      'schemaexporter'}
_CLUSTER_REFS = ('connectClusterRef', 'schemaRegistryClusterRef', 'kafkaClusterRef', 'kafkaRestClassRef')
# Sub-folders of a component folder that are not the CR name
_GENERIC_DIRS = {'logs', 'pods', 'cm', 'sts', 'svc', 'pv', 'pvc', 'pdb', 'deployment', 'secrets'}
# Configuration (⚙️ section of the report): files of the <cr>-shared-config ConfigMap that CFK renders for a Kafka,
# ZooKeeper, Schema Registry, Connect or Control Center CR, and the "<Class>Config values:" dumps of their logs (the connectors of a Connect log
# with the [connector|task-0] MDC context of their header). Component -> CR kind, main properties file, config classes
# of the effective config logged at startup
_CONFIG_COMPONENTS = {
    'kafka': ('Kafka', 'kafka.properties', ('KafkaConfig',)),
    # ZooKeeper logs no "Config values:" dump
    'zookeeper': ('Zookeeper', 'zookeeper.properties', ()),
    'schemaregistry': ('SchemaRegistry', 'schemaregistry.properties', ('SchemaRegistryConfig',)),
    'connect': ('Connect', 'connect.properties', ('DistributedConfig', 'StandaloneConfig')),
    'controlcenter': ('ControlCenter', 'controlcenter.properties', ('ControlCenterConfig',)),
}
_CONFIGMAP_FILES = ('jvm.config', 'log4j.properties', 'plugins.json')
_CONFIG_DUMP_RE = re.compile(r'(?:\[([^\s|\]]+)\|((?:task-\d+|worker))[^\]]*\]\s*)?([A-Za-z]+Config) values:\s*$')
_CONFIG_VALUE_RE = re.compile(r'^\t(\S+) = (.*)$')
_CONFIG_LOGGER_RE = re.compile(r' \([\w.$]*Config(?::\d+)?\)$')
_LOG_TS_RE = re.compile(r'\d{4}-\d\d-\d\d[ T]\d\d:\d\d:\d\d')
# Last resort for names that are not in the bundle: keywords, most specific first
_NAME_KEYWORDS = (
    ('kraft', 'kraftcontroller'), ('zookeeper', 'zookeeper'), ('schemaregistry', 'schemaregistry'),
    ('schema-registry', 'schemaregistry'), ('ksql', 'ksqldb'), ('controlcenter', 'controlcenter'),
    ('control-center', 'controlcenter'), ('restproxy', 'kafkarestproxy'), ('kafka-rest', 'kafkarestproxy'),
    ('operator', 'operator'), ('connect', 'connect'), ('replicator', 'connect'), ('kafka', 'kafka'),
)
# Conditions of the CFK CRs where False is the healthy value (False = not garbage collecting, config up to date…).
# A False condition is reported only when True is the healthy value: *ready / *available / *healthy, or its
# reason / message says something failed.
_GOOD_WHEN_TRUE_RE = re.compile(r'ready|available|healthy|synced|reconciled|succeeded|running', re.IGNORECASE)
_FAILURE_WORDS_RE = re.compile(r'fail|error|invalid|denied|unable|cannot|timeout', re.IGNORECASE)

# Connect task / client of a log record, to list the connectors one root cause affects
_TASK_RE = re.compile(r'(?:Task|Worker\w*Task|task)\{id=([^}]+)\}|connector-(?:producer|consumer|dlq-producer|adminclient)-([\w.-]+?)(?:-\d+)?[\],\s]')
# Connector of a log record, for the connector filter of the report (same as tools/log-analyzer/log_report.py): the
# [connector|task-0] / [connector|worker] MDC context of Connect, with an optional scope ([connector|task-0|offsets]),
# or the id of the task
_CONNECTOR_RE = re.compile(r'\[([^\s|\]]+)\|(?:task-\d+|worker)(?:\|[^\s|\]]+)?\]|Worker(?:Source|Sink)Task\{id=(\S+)-\d+\}')

# "Kafka version: 7.4.1-ce" of the AppInfoParser at startup: the CP version a pod runs (the last one of its log). Only
# the -ce / -ccs builds of CP: a plugin with its own kafka-clients logs an Apache Kafka version
_KAFKA_VERSION_RE = re.compile(r'Kafka version: (\d+\.\d+\.\d+)-(?:ce|ccs)\b')
# components whose pods log the CP version of their image (Control Center next gen, ksqlDB have their own numbering)
_VERSION_LOGGING_KINDS = {'Kafka', 'KRaftController', 'Connect', 'SchemaRegistry'}

# FailedCreate of a ReplicaSet / StatefulSet / Job refused by a ResourceQuota (Kubernetes event)
_QUOTA_RE = re.compile(r'exceeded quota: ([\w.-]+), requested: (\S+), used: (\S+), limited: (\S+)')
_QUOTA_OWNER_RE = re.compile(r'\b(ReplicaSet|StatefulSet|Job|Deployment|DaemonSet)/([\w.-]+)')
# a Warning row of kubectl get events: "83s Warning Unhealthy Pod/kafka-1 Readiness probe failed: …"
_EVENT_ROW_RE = re.compile(r'\bWarning\s+(\S+)\s+([A-Za-z]+/[\w.-]+)\s+(.*)$')
# the message of a Warning event of a YAML file: "Unhealthy: Readiness probe failed: … (Pod/kafka-1)"
_EVENT_ISSUE_RE = re.compile(r'^(\S+): (.*) \(([A-Za-z]+/[\w.-]+)\)$', re.DOTALL)


def _log_stem(rel: str) -> str:
    """pod of a log file: cluster-resources/kafka/logs/kafka-0.log -> kafka-0"""
    return re.sub(r'\.(?:log|txt|out)(?:\..*)?$', '', os.path.basename(rel), flags=re.IGNORECASE)


def _event_key(reason: str, obj: str, message: str) -> tuple:
    message = re.sub(r'^\(combined from similar events\):\s*', '', message.strip())
    return reason, obj.lower(), re.sub(r'\s+', ' ', message)[:80]


def _quantity(value: str) -> Optional[float]:
    """Kubernetes quantity: 4, 500m, 16Gi, 2G -> number (bytes for memory)"""
    m = re.match(r'^(\d+(?:\.\d+)?)(m|k|Ki|M|Mi|G|Gi|T|Ti)?$', value or '')
    if not m:
        return None
    factor = {None: 1, 'm': 0.001, 'k': 1e3, 'Ki': 1024, 'M': 1e6, 'Mi': 1024 ** 2, 'G': 1e9, 'Gi': 1024 ** 3,
              'T': 1e12, 'Ti': 1024 ** 4}[m.group(2)]
    return float(m.group(1)) * factor


# pod name suffixes: statefulset ordinal (kafka-0), deployment hash (confluent-operator-7d9c8b6f5-x2x7k)
_POD_SUFFIX_RES = (re.compile(r'-\d+$'), re.compile(r'-[a-z0-9]{6,10}-[a-z0-9]{5}$'))


class CFKBundleAnalyzer:
    """Main analyzer class for CFK support bundles"""

    def __init__(self, bundle_path: str, include_warnings: bool = False):
        self.bundle_path = bundle_path
        self.include_warnings = include_warnings
        self.issues = []
        self.issue_index = {}  # signature -> issue, for deduplication with occurrence counts
        self.component_index = {}  # pod / CR name -> (component, instance), filled while walking the bundle
        self.clusters = {}  # component -> names of its clusters (CRs, cluster-resources/<type>/<name>)
        self.environment = {'components': {}}  # versions and images, see environment.py
        self.timeline = []  # changes (managedFields, pod restarts), newest first after the walk
        self.jvm_truststores = {}  # CR name -> JVM default truststore flags of its configOverrides / envVars
        self.pod_health = {}  # pod name -> (Running and every container ready, highest restart count)
        self.statefulset_ready = {}  # StatefulSet name -> every replica ready and updated, for bundles without pod manifests
        # what the CRs ask for and what runs (_check_rollouts): CR name -> {kind, image, file}, StatefulSet name ->
        # {images, replicas, ready, updated, revisions, file}, pod -> image of its main container, log file stem ->
        # (CP version logged at startup, file, line), CRs with platform.confluent.io/block-reconcile
        self.cr_images = {}
        self.statefulsets = {}
        self.pod_images = {}
        self.log_versions = {}
        self.blocked_crs = set()
        # ZooKeeper to KRaft migration (kraft_migration.py): KRaftMigrationJob CRs (name -> status, file), their Warning
        # events, the "Migration current status <phase>/<sub-phase>" lines of the operator log
        self.kraft_migrations = {}
        self.kraft_migration_events = {}
        self.kraft_migration_log = {}  # (phase, sub-phase) -> {count, first, last, reason, file}
        self.runbooks = runbooks.Catalog()  # known CFK issues (runbooks.py + the private file of Confluent support)
        # Kafka / ZooKeeper / Schema Registry / Connect / Control Center CRs (component -> CR name -> ConfigMap files,
        # configOverrides, config dumps of the logs) and connectors (name -> Connector CR and config dumps of the logs),
        # as key=value text so that the sanitizer redacts secrets
        self.configuration = {'components': {c: {} for c in _CONFIG_COMPONENTS}, 'connectors': {}}
        self.summary = {
            'total_issues': 0,
            'critical': 0,
            'high': 0,
            'medium': 0,
            'low': 0,
            'files_analyzed': 0,
            'analysis_time': None,
        }
        self.coverage = {
            'log_files': 0,
            'log_lines': 0,
            'yaml_files': 0,
            'event_files': 0,
            'pods': 0,
            'custom_resources': 0,
            'events': 0,
            'skipped_files': 0,
            'unparsable_files': [],
            'layout': [],
        }

        # Patterns applied to log records that have an explicit ERROR/FATAL (or WARN) level,
        # or are an uncaught exception. The record text is the head line plus its
        # `Caused by:` chain, so the root cause is classified, not only the symptom.
        # Shared with the known causes of playground analyze logs (tools/report-common/known_causes.py).
        self.error_patterns = known_causes.error_patterns()

        # Kubernetes symptoms. Applied to Warning events, pod describes and kubectl
        # text output, where there is no log level.
        self.k8s_patterns = {
            'crashloopbackoff': {
                'pattern': r'CrashLoopBackOff|Back-off restarting failed container',
                'severity': 'critical',
                'category': 'Pod Failures'
            },
            'oom_killed': {
                'pattern': r'OOMKilled|OOMKilling|Memory cgroup out of memory',
                'severity': 'critical',
                'category': 'Resource Issues'
            },
            'evicted': {
                'pattern': r'\bEvicted\b|The node was low on resource',
                'severity': 'high',
                'category': 'Resource Issues'
            },
            'image_pull_error': {
                'pattern': r'ImagePullBackOff|ErrImagePull|Failed to pull image',
                'severity': 'high',
                'category': 'Image Issues'
            },
            'pending_pod': {
                'pattern': r'FailedScheduling|Insufficient cpu|Insufficient memory|didn\'t match Pod\'s node affinity|had untolerated taint',
                'severity': 'medium',
                'category': 'Scheduling Issues'
            },
            'volume_mount': {
                'pattern': r'FailedMount|FailedAttachVolume|MountVolume\.SetUp failed|Unable to attach or mount volumes|ProvisioningFailed',
                'severity': 'high',
                'category': 'Volume Issues'
            },
            'liveness_probe_failed': {
                'pattern': r'Liveness probe failed|Readiness probe failed|Startup probe failed|\bUnhealthy\b',
                'severity': 'high',
                'category': 'Health Check Issues'
            },
            'init_container_error': {
                'pattern': r'Init:Error|Init:CrashLoopBackOff|init container.{0,40}failed',
                'severity': 'high',
                'category': 'Init Container Issues'
            },
            'config_error': {
                'pattern': r'CreateContainerConfigError|secret "[^"]+" not found|configmap "[^"]+" not found',
                'severity': 'high',
                'category': 'Configuration'
            },
            'storage_pending': {
                'pattern': r'PersistentVolumeClaim.{0,80}(?:pending|not found)|waiting for first consumer|no persistent volumes available',
                'severity': 'high',
                'category': 'Storage Issues'
            },
            'reconcile_blocked': {
                'pattern': r'block-reconcile',
                'severity': 'low',
                'category': 'Reconciliation Blocked'
            },
        }

        self._error_re = self._compile(self.error_patterns)
        self._k8s_re = self._compile(self.k8s_patterns)

        # Cheap literal screen for kubectl text output: a line with none of these
        # tokens cannot match a k8s pattern nor be a Warning event row.
        self._classify_cache = {}  # see _classify
        self._k8s_screen = (
            'warning', 'backoff', 'oomkill', 'out of memory', 'evicted', 'low on resource',
            'imagepull', 'errimagepull', 'pull image', 'failedscheduling', 'insufficient',
            'affinity', 'taint', 'mount', 'attach', 'provisioningfailed', 'probe failed',
            'unhealthy', 'init:', 'init container', 'createcontainerconfigerror', 'not found',
            'persistentvolumeclaim', 'first consumer', 'persistent volumes', 'block-reconcile',
        )

    @staticmethod
    def _compile(patterns: Dict[str, Dict[str, str]]):
        """Combine patterns into one lower-cased regex with one named group per pattern.

        Real CFK bundles routinely contain millions of log lines: one combined search per
        record (without IGNORECASE, both sides lowered) is much cheaper than a loop over
        every pattern. Unbounded `.*` are already replaced by `.{0,N}` in the patterns.
        Declaration order is the priority when several patterns match the same text
        (`java.io.IOException: No space left on device` is a Storage issue).
        """
        meta = {}
        priority = {}
        parts = []
        for index, (name, info) in enumerate(patterns.items()):
            group = f"p_{name}"
            # lower case outside the escapes: \S (not a space) must not become \s (a space)
            pattern = re.sub(r'\\.|[^\\]+', lambda m: m.group() if m.group().startswith('\\') else m.group().lower(), info['pattern'])
            parts.append(f"(?P<{group}>{pattern})")
            meta[group] = (info['severity'], info['category'], name)
            priority[group] = (index, re.compile(pattern))
        return re.compile('|'.join(parts)), meta, priority

    def analyze(self) -> Dict[str, Any]:
        """Main analysis method"""
        start_time = datetime.now()

        for name in ('cluster-resources', 'operator', 'misc'):
            if os.path.isdir(os.path.join(self.bundle_path, name)):
                self.coverage['layout'].append(name)

        copies = self._bundle_copies()
        for root, dirs, files in os.walk(self.bundle_path):
            dirs.sort()
            if root == self.bundle_path and copies:
                dirs[:] = [d for d in dirs if d not in copies]
            for file in sorted(files):
                file_path = os.path.join(root, file)
                if os.path.islink(file_path):
                    self.coverage['skipped_files'] += 1
                    continue
                self._index_path(self._rel(file_path))
                if file == 'cluster-details.txt':
                    self._read_cluster_details(file_path)
                if _YAML_FILE_RE.search(file):
                    if 'event' in file.lower():
                        self._analyze_event_file(file_path)
                    else:
                        self._analyze_yaml_file(file_path)
                elif _TEXT_FILE_RE.search(file):
                    self._analyze_text_file(file_path)
                else:
                    self.coverage['skipped_files'] += 1

        # after the walk: events and shared pods.yaml may come before the CRs they refer to
        self._check_environment()
        self._check_jvm_truststores()
        self._drop_duplicate_text_events()
        self._merge_quota_events()
        self._check_rollouts()
        for issue in self.issues:
            self._assign_component(issue)
        self._mark_transient()
        self._check_kraft_migrations()
        for issue in self.issues:
            names = self.runbooks.match(issue['message'] + ' ' + ' '.join(issue.get('caused_by') or []))
            if names:
                issue['runbooks'] = list(dict.fromkeys((issue.get('runbooks') or []) + names))
        for change in self.timeline:
            found = self._lookup_name(change['name'])
            if found:
                change['component'], change['instance'] = found
        self.timeline.sort(key=lambda c: c['time'], reverse=True)

        self.summary['analysis_time'] = (datetime.now() - start_time).total_seconds()
        self.summary['total_issues'] = len(self.issues)
        for issue in self.issues:
            severity = issue.get('severity', 'low')
            if severity in self.summary:
                self.summary[severity] += 1

        return {
            'summary': self.summary,
            'coverage': self.coverage,
            'environment': self.environment,
            'timeline': self.timeline,
            'configuration': self.configuration,
            'issues': sorted(
                self.issues,
                key=lambda x: (_SEVERITY_ORDER.get(x['severity'], 4), -x.get('count', 1)),
            ),
        }

    def _bundle_copies(self) -> List[str]:
        """Folders of the bundle root that hold a copy of the bundle itself (an archive extracted next to its content,
        support-bundle-ns-x/support-bundle-ns-x/): same files with the same sizes for 90% of them. Analyzed once."""
        def files_of(folder, skip=()):
            out = {}
            for root, dirs, files in os.walk(folder):
                if root == folder:
                    dirs[:] = [d for d in dirs if d not in skip]
                for f in files:
                    path = os.path.join(root, f)
                    if not os.path.islink(path):
                        out[os.path.relpath(path, folder)] = os.path.getsize(path)
            return out
        markers = ('cluster-resources', 'operator')
        if not any(os.path.isdir(os.path.join(self.bundle_path, m)) for m in markers):
            return []
        candidates = [d for d in sorted(os.listdir(self.bundle_path))
                      if os.path.isdir(os.path.join(self.bundle_path, d))
                      and any(os.path.isdir(os.path.join(self.bundle_path, d, m)) for m in markers)]
        if not candidates:
            return []
        top = files_of(self.bundle_path, skip=candidates)
        copies = []
        for d in candidates:
            inner = files_of(os.path.join(self.bundle_path, d))
            same = sum(1 for path, size in inner.items() if top.get(path) == size)
            if inner and same >= 0.9 * len(inner):
                copies.append(d)
                self.coverage.setdefault('skipped_copies', []).append(d)
        return copies

    def _severity_order(self, severity: str) -> int:
        """Return numeric order for severity sorting"""
        return _SEVERITY_ORDER.get(severity, 4)

    def _rel(self, file_path: str) -> str:
        return os.path.relpath(file_path, self.bundle_path)

    # ── Dedupe normalization ──────────────────────────────────────────────
    # Variable parts of a log line — timestamps, hex/UUID/numeric IDs,
    # request/thread IDs, line numbers — that should NOT cause distinct
    # log lines to be treated as different issues.
    _NORMALIZE_PATTERNS = [
        # one issue per root cause, not per connector task / client
        (re.compile(r'\{id=[^}]*\}'), '{id=<TASK>}'),
        (re.compile(r'\b(clientId|groupId|client\.id|group\.id)=[^\],\s]+'), r'\1=<CLIENT>'),
        (re.compile(r'connector-(?:producer|consumer|dlq-producer|adminclient)-[\w.-]+'), 'connector-<CLIENT>'),
        (re.compile(r'\d{4}-\d{2}-\d{2}[ T]\d{2}:\d{2}:\d{2}[.,]?\d*Z?'), '<TS>'),
        (re.compile(r'\b\d{2}:\d{2}:\d{2}[.,]?\d*\b'), '<TS>'),
        (re.compile(r'\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b'), '<UUID>'),
        (re.compile(r'\b0x[0-9a-fA-F]+\b'), '<HEX>'),
        # Short hex IDs (request IDs, correlation IDs, short hashes). Without
        # this, `creqId=040cd1e6` and `creqId=8d3bbd11` are treated as
        # different "issues" even though they're the same recurring event.
        (re.compile(r'\b[0-9a-f]{8,32}\b'), '<ID>'),
        (re.compile(r'\b\d+\b'), '<N>'),
        (re.compile(r'\(\S+\.java:\d+\)'), '(<JAVA>)'),
        (re.compile(r'\s+'), ' '),
    ]

    def _normalize_signature(self, text: str) -> str:
        out = text
        for pat, repl in self._NORMALIZE_PATTERNS:
            out = pat.sub(repl, out)
        return out.strip()[:160]

    def _add_issue(self, severity: str, category: str, message: str,
                   file_path: str, line_number: int = None, context: str = None,
                   caused_by: List[str] = None, count: int = 1, timestamp: str = None,
                   dedupe_key: str = None, resource: str = None, resource_kind: str = None,
                   affected: str = None, connector: str = None):
        """Add an issue, or bump the occurrence count of an identical one.

        Identical means same category, same file (rotated logs of the same pod count
        as the same file) and the same normalized message (connector task / client ids
        removed, `affected` lists them).
        `resource` / `resource_kind` name the pod or CR the issue is about, to find its
        component when the file is shared (events, pods.yaml).
        `connector` is the Connect connector of the log record, `connectors` lists them.
        """
        file_key = re.sub(r'\.log(?:\.[\w-]+)?(?:\.gz)?$', '.log', file_path)
        signature = f"{category}:{file_key}:{dedupe_key or self._normalize_signature(message)}"

        existing = self.issue_index.get(signature)
        if existing is not None:
            existing['count'] = existing.get('count', 1) + count
            if _SEVERITY_ORDER[severity] < _SEVERITY_ORDER[existing['severity']]:
                existing['severity'] = severity
            if affected and affected not in existing.setdefault('affected', []):
                existing['affected'].append(affected)
            if connector and connector not in existing.setdefault('connectors', []):
                existing['connectors'].append(connector)
            return

        issue = {
            'severity': severity,
            'category': category,
            'message': message,
            'file': file_path,
            'count': count,
        }
        if timestamp:
            issue['timestamp'] = timestamp
        if line_number:
            issue['line_number'] = line_number
        if context:
            issue['context'] = context
        if caused_by:
            issue['caused_by'] = caused_by
        if resource or resource_kind:
            issue['_resource'] = (resource_kind or '', resource or '')
        if affected:
            issue['affected'] = [affected]
        if connector:
            issue['connectors'] = [connector]

        self.issue_index[signature] = issue
        self.issues.append(issue)

    # ── Component attribution ─────────────────────────────────────────────

    def _index_component(self, name: str, component: str, instance: str = None, cluster: bool = False):
        """cluster: name is a cluster of the component (Kafka, SchemaRegistry… CR, cluster-resources/<type>/<name>)"""
        if name and component in COMPONENTS:
            self.component_index.setdefault(name, (component, instance or name))
            if cluster:
                self.clusters.setdefault(component, set()).add(name)

    def _index_path(self, file_path: str):
        """cluster-resources/<type>/<name>/... names a CR of that type"""
        parts = file_path.replace('\\', '/').split('/')[:-1]
        for index, part in enumerate(parts[:-1]):
            if index > 0 and parts[index - 1] == 'cluster-resources' and part.lower() in COMPONENTS:
                self._index_component(parts[index + 1], part.lower(), cluster=True)

    def _lookup_name(self, name: str, keywords: bool = True):
        """(component, instance) of a pod / CR name: bundle index first, then pod suffixes, then keywords"""
        if not name:
            return None
        candidates = [name] + [r.sub('', name) for r in _POD_SUFFIX_RES if r.search(name)]
        for candidate in candidates:
            if candidate in self.component_index:
                return self.component_index[candidate]
        if keywords:
            lowered = name.lower()
            for keyword, component in _NAME_KEYWORDS:
                if keyword in lowered:
                    return component, candidates[-1]
        return None

    def _component_from_path(self, file_path: str):
        """cluster-resources/connect/connect-peh/logs/connect-peh-0.log -> (connect, connect-peh)"""
        parts = file_path.replace('\\', '/').split('/')
        dirs = [p.lower() for p in parts[:-1]]
        matches = [i for i, d in enumerate(dirs) if d in COMPONENTS and d != 'other']
        if not matches:
            return None
        # cluster-resources/<type>/ wins, else the deepest folder (a namespace may be called "kafka")
        typed = [i for i in matches if i > 0 and dirs[i - 1] == 'cluster-resources']
        index = (typed or matches)[-1]
        following = parts[index + 1:-1]
        if following and following[0].lower() not in _GENERIC_DIRS:
            return dirs[index], following[0]
        return dirs[index], None

    def _only_cluster(self, component: str):
        """the cluster of a component when the bundle has one, else None"""
        clusters = self.clusters.get(component) or set()
        return next(iter(clusters)) if len(clusters) == 1 else None

    def _lookup_resource(self, kind: str, name: str):
        if kind.lower() in _APPLICATION_KINDS:
            component = _KIND_COMPONENT[kind.lower()]
            found = self.component_index.get(name)
            # "-": no cluster ref and several clusters, the component is known but not its instance
            instance = found[1] if found and found[1] != '-' else self._only_cluster(component)
            return component, instance
        if kind.lower() in _KIND_COMPONENT:
            return self.component_index.get(name) or (_KIND_COMPONENT[kind.lower()], name or None)
        return self._lookup_name(name)

    def _assign_component(self, issue: Dict):
        kind, name = issue.pop('_resource', ('', ''))
        # flat layout (confluent/connect/logs/connect-0.log): the log file is named after its pod
        stem = re.sub(r'\.(?:log|txt|out)(?:\..*)?$', '', os.path.basename(issue.get('file', '')), flags=re.IGNORECASE)
        component, instance = self._component_from_path(issue.get('file', '')) or (None, None)
        if component is None:
            found = self._lookup_resource(kind, name) or self._lookup_name(stem)
            component, instance = found if found else ('other', None)
        elif instance is None:
            found = self._lookup_resource(kind, name) if name else self._lookup_name(stem, keywords=False)
            if found and found[0] == component:
                instance = found[1]
        if instance == '-':
            instance = self._only_cluster(component)
        issue['component'] = component
        if instance:
            issue['instance'] = instance

    # ── Log / text files ──────────────────────────────────────────────────

    def _read_lines(self, file_path: str) -> Optional[List[str]]:
        try:
            if file_path.lower().endswith('.gz'):
                with gzip.open(file_path, 'rb') as f:
                    raw = f.read()
            else:
                with open(file_path, 'rb') as f:
                    raw = f.read()
        except (OSError, EOFError) as e:
            print(f"warning: cannot read {self._rel(file_path)}: {e}")
            self.coverage['unparsable_files'].append(self._rel(file_path))
            return None
        if b'\x00' in raw[:8192]:
            self.coverage['skipped_files'] += 1  # binary
            return None
        return raw.decode('utf-8', errors='replace').splitlines()

    def _detect_level(self, line: str) -> Optional[str]:
        m = _LEVEL_RE.search(line[:400])
        if not m:
            return None
        if m.group(4):
            return _KLOG_LEVEL[m.group(4)]
        level = (m.group(1) or m.group(2) or m.group(3)).upper()
        if level in ('WARNING',):
            return 'WARN'
        if level in ('SEVERE', 'CRITICAL', 'PANIC', 'DPANIC'):
            return 'FATAL'
        return level

    def _classify(self, compiled, text: str):
        """Return (severity, category, name) of the first pattern, in declaration order, that matches.

        Cached: a WARN storm repeats the same record millions of times with other timestamps and ids,
        and the combined regex costs ~50µs per record.
        """
        regex, meta, priority = compiled
        key = (id(regex), text if _PATTERN_DIGITS_RE.search(text) else text.translate(_CLASSIFY_DIGITS))
        if key in self._classify_cache:
            return self._classify_cache[key]
        best = None
        lowered = text.lower()
        # the combined regex only tells whether a pattern matches: its matches do not overlap, so in
        # "org.apache.kafka.common.errors.TopicAuthorizationException" the generic Kafka exception hides the
        # authorization one. The patterns are then tried one by one, in declaration order
        if regex.search(lowered):
            for group, (_, single) in priority.items():
                if single.search(lowered):
                    best = group
                    break
        if len(self._classify_cache) >= 200000:
            self._classify_cache.clear()
        self._classify_cache[key] = meta[best] if best else None
        return self._classify_cache[key]

    def _analyze_text_file(self, file_path: str):
        """Analyze a log or kubectl text file.

        Log records are grouped with their stack trace and `Caused by:` chain. A record
        counts only when its head line has an explicit ERROR/FATAL level (WARN when it
        matches a known category, or always with --include-warnings) or when it is an
        uncaught exception. Kubernetes symptoms (CrashLoopBackOff, FailedMount…) are
        detected on every line, since kubectl output has no log level.
        """
        lines = self._read_lines(file_path)
        if lines is None:
            return
        self.summary['files_analyzed'] += 1
        self.coverage['log_files'] += 1
        self.coverage['log_lines'] += len(lines)
        rel = self._rel(file_path)

        record = None  # (line_number, level, head, caused_by)

        def flush():
            if record is not None:
                self._handle_record(rel, lines, *record)

        k8s_screen = self._k8s_screen
        # states of known CFK issues that the operator logs at INFO (runbooks.py operator_info)
        operator_info_re = self.runbooks.operator_info_re if rel.split(os.sep)[0] == 'operator' or \
            '/operator/' in f'/{rel}' else None
        for line_num, line in enumerate(lines, 1):
            if record is not None:
                cb = _CAUSED_BY_RE.match(line)
                if cb:
                    if len(record[3]) < 5:
                        record[3].append(cb.group(1).strip()[:300])
                    continue
                if _STACK_FRAME_RE.match(line):
                    continue
                if (_EXCEPTION_HEAD_RE.match(line) and not record[3]
                        and not _RECORD_START_RE.match(line)):
                    # exception printed on the line after "ERROR something failed"
                    record[3].append(line.strip()[:300])
                    continue
            flush()
            record = None

            if not line.strip() or _NOISE_RE.search(line):
                continue
            # "\tkey = value" of a "…Config values:" dump: configuration, not a record nor kubectl output
            # (confluent.broker.health.manager.num.samples.before.broker.unhealthy = 180)
            if line[0] == '\t' and _CONFIG_VALUE_RE.match(line):
                continue

            if 'Kafka version: ' in line:
                found = _KAFKA_VERSION_RE.search(line)
                if found:
                    self.log_versions[_log_stem(rel)] = (found.group(1), rel, line_num)
            level = self._detect_level(line)
            if level is None and _EXCEPTION_HEAD_RE.match(line):
                level = 'ERROR'
            if level is not None:
                record = (line_num, level, line, [])
                continue
            if operator_info_re is not None and 'Migration current status' in line:
                self._record_kraft_migration_log(line, rel)
                continue
            if operator_info_re is not None and operator_info_re.search(line):
                self._add_issue(
                    severity='medium', category='Operator Issues', message=f"Operator: {line.strip()[:300]}",
                    file_path=rel, line_number=line_num,
                    context='\n'.join(lines[max(0, line_num - 3):min(len(lines), line_num + 2)]),
                )
                continue

            line_lower = line.lower()
            if any(t in line_lower for t in k8s_screen):
                self._handle_k8s_line(rel, lines, line_num, line)

        flush()
        component = self._component_from_path(rel)
        if component and component[0] in _CONFIG_COMPONENTS:
            self._collect_config_dumps(rel, lines, *component)

    def _collect_config_dumps(self, rel: str, lines: List[str], kind: str, instance: Optional[str]):
        """"<Class>Config values:" blocks of a component log (one tab-indented "key = value" per line): the effective
        config of the component (KafkaConfig, SchemaRegistryConfig, DistributedConfig, ControlCenterConfig), and in a
        Connect log the configs of the connectors (SourceConnectorConfig, the config of the plugin, ConsumerConfig of a
        task… attributed with the [connector|task-0] context, else the name key).
        The last dump of each config class wins."""
        own_classes = _CONFIG_COMPONENTS[kind][2]
        n = len(lines)
        i = 0
        while i < n:
            line = lines[i]
            i += 1
            if 'Config values:' not in line:
                continue
            m = _CONFIG_DUMP_RE.search(line)
            if not m:
                continue
            header = i
            values = []
            while i < n and lines[i].startswith('\t'):
                v = _CONFIG_VALUE_RE.match(lines[i])
                if v:
                    # the logger of the record ends the last line: " (org.apache.kafka.common.config.AbstractConfig:370)"
                    values.append((v.group(1), _CONFIG_LOGGER_RE.sub('', v.group(2))))
                i += 1
            if not values:
                continue
            connector, scope, cls = m.group(1), m.group(2), m.group(3)
            keys = dict(values)
            if kind != 'connect':
                connector = None
            elif not connector and cls.endswith('ConnectorConfig'):
                connector = keys.get('name')
            ts = _LOG_TS_RE.search(line[:80])
            entry = {'title': cls + (f' ({scope})' if scope else ''), 'source': 'log', 'file': rel, 'line': header,
                     'time': ts.group(0).replace(' ', 'T') if ts else None,
                     'text': '\n'.join(f'{k}={v}' for k, v in values)}
            if connector:
                conn = self._connector_config(connector)
                conn['dumps'][cls] = entry
                if keys.get('connector.class'):
                    conn['class'] = keys['connector.class']
                if instance and not conn.get('cluster'):
                    conn['cluster'] = instance
            elif cls in own_classes:
                config = self._component_config(kind, instance or kind)
                # one per pod log
                config['dumps'] = [d for d in config['dumps'] if d['file'] != rel] + [entry]

    def _component_config(self, kind: str, name: str) -> Dict:
        return self.configuration['components'][kind].setdefault(name, {'files': {}, 'overrides': {}, 'dumps': []})

    def _connector_config(self, name: str) -> Dict:
        return self.configuration['connectors'].setdefault(name, {'dumps': {}})

    def _record_configmap(self, obj: Dict, file_path: str):
        """kafka.properties / schemaregistry.properties / connect.properties, jvm.config… of the <cr>-shared-config
        ConfigMap that CFK renders for a Kafka, ZooKeeper, Schema Registry, Connect or Control Center CR"""
        data = obj.get('data')
        if not isinstance(data, dict):
            return
        kind = next((c for c, (_, main, _) in _CONFIG_COMPONENTS.items() if main in data), None)
        if kind is None:
            return
        cr_kind, main, _ = _CONFIG_COMPONENTS[kind]
        metadata = obj.get('metadata') or {}
        annotations = metadata.get('annotations') or {}
        owner = next((o.get('name') for o in metadata.get('ownerReferences') or []
                      if isinstance(o, dict) and o.get('kind') == cr_kind), None)
        name = annotations.get('platform.confluent.io/cr-name') or owner or \
            re.sub(r'-shared-config$', '', str(metadata.get('name') or '')) or file_path
        config = self._component_config(kind, name)
        config['source'] = file_path
        config['files'] = {f: str(data[f]) for f in (main,) + _CONFIGMAP_FILES if data.get(f)}

    def _record_config_cr(self, obj: Dict, kind: str, name: str, file_path: str):
        """configOverrides of a Kafka, ZooKeeper, Schema Registry, Connect or Control Center CR, configs of a Connector CR"""
        spec = obj.get('spec') or {}
        if kind in _CONFIG_COMPONENTS:
            overrides = spec.get('configOverrides') or {}
            if isinstance(overrides, dict):
                config = self._component_config(kind, name)
                config['cr'] = file_path
                config['overrides'] = {k: '\n'.join(str(v) for v in overrides[k]) for k in ('server', 'jvm', 'log4j')
                                       if isinstance(overrides.get(k), list) and overrides[k]}
        elif kind == 'connector':
            conn = self._connector_config(spec.get('name') or name)
            configs = spec.get('configs') if isinstance(spec.get('configs'), dict) else {}
            head = [('connector.class', spec.get('class')), ('tasks.max', spec.get('taskMax'))]
            conn['cr'] = {'title': 'Connector CR', 'source': 'cr', 'file': file_path, 'line': None, 'time': None,
                          'text': '\n'.join(f'{k}={v}' for k, v in head + sorted(configs.items()) if v is not None)}
            if spec.get('class'):
                conn['class'] = spec['class']
            cluster = (spec.get('connectClusterRef') or {}).get('name') if isinstance(spec.get('connectClusterRef'), dict) else None
            if cluster:
                conn['cluster'] = cluster
            status = obj.get('status') or {}
            state = status.get('connectorState') or status.get('state')
            if state:
                conn['state'] = str(state)

    def _handle_record(self, rel: str, lines: List[str], line_num: int, level: str,
                       head: str, caused_by: List[str]):
        text = head + ' ' + ' '.join(caused_by)
        # The root cause (last Caused by) wins over the symptom when both match. A WARN record counts only when it
        # matches a known cause, not a catch-all (any Kafka exception…): WARN storms of retriable errors are noise.
        match = None
        for candidate in list(reversed(caused_by)) + [head]:
            match = self._classify(self._error_re, candidate)
            if match and level == 'WARN' and match[2] in _CATCH_ALL:
                match = None
            if match:
                break
        if match is None:
            match = self._classify(self._k8s_re, text)

        if match is not None:
            severity, category, name = match
            if level == 'WARN':
                if _SEVERITY_ORDER[severity] < _SEVERITY_ORDER['medium']:
                    severity = 'medium'
            label = name.replace('_', ' ').title()
        else:
            if level == 'FATAL':
                severity, category = 'high', 'Other Critical (Unclassified)'
            elif level == 'WARN':
                if not self.include_warnings:
                    return
                severity, category = 'low', 'Other Warnings (Unclassified)'
            elif caused_by or _EXCEPTION_HEAD_RE.match(head):
                severity, category = 'medium', 'Other Exceptions (Unclassified)'
            else:
                severity, category = 'medium', 'Other Errors (Unclassified)'
            label = level.title()

        task = _TASK_RE.search(head + ' ')
        connector = _CONNECTOR_RE.search(head)
        context_lines = lines[max(0, line_num - 3):min(len(lines), line_num + 2)]
        self._add_issue(
            severity=severity,
            category=category,
            affected=(task.group(1) or task.group(2)) if task else None,
            connector=(connector.group(1) or connector.group(2)) if connector else None,
            message=f"{label}: {head.strip()[:300]}",
            file_path=rel,
            line_number=line_num,
            context='\n'.join(context_lines),
            caused_by=caused_by,
            dedupe_key=self._normalize_signature(head + ' '.join(caused_by[-1:])),
        )

    def _handle_k8s_line(self, rel: str, lines: List[str], line_num: int, line: str):
        match = self._classify(self._k8s_re, line)
        is_warning_event = re.search(r'(?:^|\s)Warning\s', line) is not None
        if match is None and not is_warning_event:
            return
        # row of a Normal event (kubectl get events / describe): "Normal WaitForFirstConsumer … waiting for first
        # consumer to be created before binding" is how a PVC of a WaitForFirstConsumer storage class starts
        if not is_warning_event and re.search(r'(?:^|\s)Normal\s', line):
            return
        if match is not None:
            severity, category, name = match
        else:
            severity, category = 'medium', 'Kubernetes Events'
        context_lines = lines[max(0, line_num - 3):min(len(lines), line_num + 2)]
        self._add_issue(
            severity=severity,
            category=category,
            message=line.strip()[:300],
            file_path=rel,
            line_number=line_num,
            context='\n'.join(context_lines),
        )

    # ── Kubernetes events ─────────────────────────────────────────────────

    def _load_yaml_documents(self, file_path: str) -> Optional[List[Any]]:
        try:
            with open(file_path, 'r', encoding='utf-8', errors='replace') as f:
                content = f.read()
            if file_path.lower().endswith('.json'):
                docs = [json.loads(content)]
            else:
                docs = [d for d in yaml.safe_load_all(content) if d is not None]
        except (OSError, ValueError, yaml.YAMLError) as e:
            print(f"warning: cannot parse {self._rel(file_path)}: {str(e).splitlines()[0]}")
            self.coverage['unparsable_files'].append(self._rel(file_path))
            return None
        # Flatten `kind: List` / `items:` and top-level lists
        objects = []
        for doc in docs:
            if isinstance(doc, dict) and isinstance(doc.get('items'), list):
                objects.extend(doc['items'])
            elif isinstance(doc, list):
                objects.extend(doc)
            else:
                objects.append(doc)
        return [o for o in objects if isinstance(o, dict)]

    def _analyze_event_file(self, file_path: str):
        """Analyze Kubernetes events file"""
        objects = self._load_yaml_documents(file_path)
        if objects is None:
            # Fallback to text analysis
            self._analyze_text_file(file_path)
            return
        self.summary['files_analyzed'] += 1
        self.coverage['event_files'] += 1
        for event in objects:
            self._process_event(event, file_path)

    def _process_event(self, event: Dict, file_path: str):
        """Process a single Kubernetes event"""
        self.coverage['events'] += 1
        event_type = event.get('type', '')
        if event_type not in ('Warning', 'Error'):
            return
        reason = event.get('reason', '') or ''
        message = event.get('message', '') or event.get('note', '') or ''
        obj = event.get('involvedObject') or event.get('regarding') or {}
        target = f"{obj.get('kind', '')}/{obj.get('name', '')}".strip('/')

        match = self._classify(self._k8s_re, f"{reason} {message}")
        if match is not None:
            severity, category, _ = match
        else:
            severity = 'high' if event_type == 'Error' else 'medium'
            category = 'Kubernetes Events'

        count = event.get('count') or (event.get('series') or {}).get('count') or 1
        try:
            count = int(count)
        except (TypeError, ValueError):
            count = 1
        if obj.get('kind') == 'KRaftMigrationJob':
            category = 'KRaft Migration'
            self.kraft_migration_events.setdefault(obj.get('name') or '?', []).append({
                'reason': reason, 'message': message, 'count': count,
                'first': kraft_migration._parse_ts(event.get('firstTimestamp') or event.get('eventTime')),
                'last': kraft_migration._parse_ts(event.get('lastTimestamp') or event.get('eventTime')),
            })

        self._add_issue(
            severity=severity,
            category=category,
            message=f"{reason}: {message}" + (f" ({target})" if target else ''),
            file_path=self._rel(file_path),
            context=yaml.safe_dump(event, default_flow_style=False, sort_keys=False),
            count=count,
            timestamp=event.get('lastTimestamp') or event.get('eventTime') or event.get('firstTimestamp'),
            resource=obj.get('name'),
            resource_kind=obj.get('kind'),
        )

    # ── YAML: pods and CFK custom resources ───────────────────────────────

    def _analyze_yaml_file(self, file_path: str):
        """Analyze a YAML / JSON manifest (multi-document and `kind: List` supported)"""
        objects = self._load_yaml_documents(file_path)
        if objects is None:
            return
        self.summary['files_analyzed'] += 1
        self.coverage['yaml_files'] += 1
        relative_path = self._rel(file_path)

        for obj in objects:
            kind = obj.get('kind') or self._infer_kind(obj)
            api_version = str(obj.get('apiVersion', ''))
            metadata = obj.get('metadata') or {}
            name = metadata.get('name') or ''
            if kind == 'Pod':
                self.coverage['pods'] += 1
                labels = metadata.get('labels') or {}
                self._index_component(name, str(labels.get('platform.confluent.io/type', '')).lower(),
                                      labels.get('app'))
                self._check_pod_config(obj, relative_path)
                self.timeline += environment.pod_changes(obj, name)
            elif kind == 'Event':
                self._process_event(obj, file_path)
            elif api_version.startswith('platform.confluent.io/'):
                self.coverage['custom_resources'] += 1
                # a Connector belongs to its Connect cluster, a Schema to its Schema Registry…
                spec = obj.get('spec') or {}
                cluster = next((spec[ref].get('name') for ref in _CLUSTER_REFS
                                if isinstance(spec.get(ref), dict) and spec[ref].get('name')), None)
                if kind.lower() in _APPLICATION_KINDS:
                    # "-": no cluster ref, resolved once every cluster of the bundle is known (_lookup_resource)
                    self._index_component(name, _KIND_COMPONENT.get(kind.lower(), ''), cluster or '-')
                else:
                    self._index_component(name, _KIND_COMPONENT.get(kind.lower(), ''), cluster, cluster=True)
                self._check_confluent_component_config(obj, relative_path)
                self.timeline += environment.managed_field_changes(obj, kind, name)
                self._record_component_images(obj, name)
                if name in self.cr_images and not self.cr_images[name].get('file'):
                    self.cr_images[name]['file'] = relative_path
                self._record_jvm_truststore(obj, kind, name, relative_path)
                if kind.lower() in _CONFIG_COMPONENTS or kind.lower() == 'connector':
                    self._record_config_cr(obj, kind.lower(), name, relative_path)
                if kind == 'KRaftMigrationJob':
                    self.kraft_migrations[name] = {'status': obj.get('status') or {}, 'file': relative_path}
            elif kind == 'ConfigMap' or (not kind and isinstance(obj.get('data'), dict)):
                self._record_configmap(obj, relative_path)
            elif kind == 'StatefulSet':
                self.timeline += environment.managed_field_changes(obj, kind, name)
                replicas = (obj.get('spec') or {}).get('replicas')
                status = obj.get('status') or {}
                containers = (((obj.get('spec') or {}).get('template') or {}).get('spec') or {}).get('containers') or []
                self.statefulsets[name] = {
                    'images': [str(c.get('image', '')) for c in containers if isinstance(c, dict)],
                    'replicas': replicas, 'ready': status.get('readyReplicas', 0), 'updated': status.get('updatedReplicas'),
                    'current': status.get('currentRevision'), 'update': status.get('updateRevision'), 'file': relative_path,
                }
                self.statefulset_ready[name] = bool(replicas) and status.get('readyReplicas') == replicas and \
                    status.get('updatedReplicas', replicas) == replicas and \
                    status.get('currentRevision') == status.get('updateRevision')
            elif kind == 'Deployment':
                for container in ((obj.get('spec') or {}).get('template') or {}).get('spec', {}).get('containers') or []:
                    if 'confluent-operator' in str(container.get('image', '')) or name == 'confluent-operator':
                        self.environment.setdefault('operator_image_tag', environment.image_tag(container.get('image', '')))

    @staticmethod
    def _infer_kind(obj: Dict) -> str:
        """`kubectl confluent support-bundle` writes pods/pod-<name>.yaml and sts/statefulset.yaml without kind"""
        spec = obj.get('spec') or {}
        if not isinstance(spec, dict):
            return ''
        if isinstance(spec.get('containers'), list):
            return 'Pod'
        if spec.get('serviceName') is not None and isinstance(spec.get('template'), dict):
            return 'StatefulSet'
        if isinstance(spec.get('template'), dict) and spec.get('selector') is not None:
            return 'Deployment'
        return ''

    # ── Environment: versions, compatibility, JVM truststore ─────────────

    def _read_cluster_details(self, file_path: str):
        try:
            with open(file_path, 'r', encoding='utf-8', errors='replace') as f:
                details = environment.parse_cluster_details(f.read())
        except OSError:
            return
        components = details.pop('components', {})
        self.environment.update(details)
        for name, images in components.items():
            self.environment['components'].setdefault(name, {}).update(images)

    def _record_component_images(self, obj: Dict, name: str):
        image = (obj.get('spec') or {}).get('image') or {}
        if not isinstance(image, dict) or not name or not (image.get('application') or image.get('init')):
            return
        entry = self.environment['components'].setdefault(name, {})
        entry.setdefault('kind', obj.get('kind'))
        if image.get('application'):
            entry.setdefault('image', image['application'])
            self.cr_images.setdefault(name, {'kind': obj.get('kind'), 'image': image['application']})
        if image.get('init'):
            entry.setdefault('init_image', image['init'])

    def _check_environment(self):
        env = self.environment
        release = environment.operator_release(env.get('operator_image_tag', '')) or \
            environment.operator_release(env.get('crd_version', ''))
        if release:
            env['cfk_version'] = release
        source = 'cluster-details.txt' if env.get('kubernetes_version') else 'cluster-resources'
        for finding in environment.compatibility_findings(env):
            instance = finding.get('instance')
            self._add_issue(
                severity=finding['severity'],
                category='Compatibility',
                message=finding['message'],
                file_path=source,
                resource=instance or 'confluent-operator',
            )

    def _record_jvm_truststore(self, obj: Dict, kind: str, name: str, file_path: str):
        """JVM flags of the CR (configOverrides.jvm, KAFKA_OPTS / JAVA_TOOL_OPTIONS env vars) for the default truststore"""
        spec = obj.get('spec') or {}
        flags = [str(f) for f in ((spec.get('configOverrides') or {}).get('jvm') or [])]
        for env_var in ((spec.get('podTemplate') or {}).get('envVars') or []):
            if isinstance(env_var, dict) and env_var.get('name') in ('KAFKA_OPTS', 'JAVA_TOOL_OPTIONS', 'KAFKA_JVM_PERFORMANCE_OPTS'):
                flags += str(env_var.get('value', '')).split()
        store = next((f.split('=', 1)[1] for f in flags if f.startswith('-Djavax.net.ssl.trustStore=')), None)
        if store is None:
            return
        self.jvm_truststores[name] = {
            'kind': kind, 'file': file_path, 'store': store,
            'password': any(f.startswith('-Djavax.net.ssl.trustStorePassword=') for f in flags),
            'type': next((f.split('=', 1)[1] for f in flags if f.startswith('-Djavax.net.ssl.trustStoreType=')), None),
        }

    def _check_jvm_truststores(self):
        """A JVM default truststore set without its password is empty when the store is PKCS12 (keytool default,
        whatever the file extension): every TLS client using the default SSLContext (AWS SDK, HTTP connectors,
        JDBC drivers…) then fails with `trustAnchors parameter must be non-empty`."""
        log_errors = {}
        for issue in self.issues:
            if issue['category'] == 'JVM Truststore Issues' and 'trustanchors' in issue['message'].lower() + \
                    ' '.join(issue.get('caused_by') or []).lower():
                found = self._component_from_path(issue['file'])
                if found and found[1]:
                    log_errors[found[1]] = log_errors.get(found[1], 0) + issue.get('count', 1)
        with_password = sorted(n for n, t in self.jvm_truststores.items() if t['password'])
        for name, truststore in sorted(self.jvm_truststores.items()):
            if truststore['password'] or (truststore['type'] or '').upper() == 'JKS':
                continue
            message = (f"{truststore['kind']}/{name} sets -Djavax.net.ssl.trustStore={truststore['store']} without "
                       f"-Djavax.net.ssl.trustStorePassword (nor trustStoreType=JKS). A PKCS12 store, the keytool default "
                       f"whatever the file extension, then loads with 0 trusted certificates in the JVM default SSLContext")
            if with_password:
                message += f". {', '.join(with_password)} set the password"
            if log_errors.get(name):
                message += f". Matches the {log_errors[name]} 'trustAnchors parameter must be non-empty' errors of its logs"
            self._add_issue(
                severity='high' if log_errors.get(name) else 'medium',
                category='JVM Truststore Issues',
                message=message,
                file_path=truststore['file'],
                resource=name, resource_kind=truststore['kind'],
            )

    def _drop_duplicate_text_events(self):
        """The Warning rows of kubectl get events (event.txt) that are also in the YAML events of the bundle (event.yaml):
        counted once, from the YAML (which has the count and the timestamps)"""
        yaml_keys = set()
        for issue in self.issues:
            if 'event' in issue['file'].lower() and not issue.get('line_number'):
                m = _EVENT_ISSUE_RE.match(issue['message'])
                if m:
                    yaml_keys.add(_event_key(m.group(1), m.group(3), m.group(2)))
        if not yaml_keys:
            return
        kept = []
        for issue in self.issues:
            m = _EVENT_ROW_RE.search(issue['message']) if issue.get('line_number') and 'event' in issue['file'].lower() else None
            if m and _event_key(m.group(1), m.group(2), m.group(3)) in yaml_keys:
                self.coverage['duplicate_events'] = self.coverage.get('duplicate_events', 0) + 1
                continue
            kept.append(issue)
        self.issues = kept

    def _merge_quota_events(self):
        """The FailedCreate events refused by a ResourceQuota (one per pod the controller tried to create): one finding per
        quota and controller, with what is requested, used and allowed for the resources that are exceeded"""
        groups, kept = {}, []
        for issue in self.issues:
            quota = _QUOTA_RE.search(issue['message'])
            owner = _QUOTA_OWNER_RE.search(issue['message']) if quota else None
            if not owner:
                kept.append(issue)
                continue
            group = groups.setdefault((quota.group(1), owner.group(1), owner.group(2)), {
                'count': 0, 'first': None, 'last': None, 'file': issue['file'], 'quota': quota})
            group['count'] += issue.get('count', 1)
            ts = issue.get('timestamp')
            if ts:
                group['first'] = min(filter(None, [group['first'], ts]))
                group['last'] = max(filter(None, [group['last'], ts]))
        self.issues = kept
        for (name, kind, owner), group in sorted(groups.items()):
            parse = lambda text: dict(kv.split('=', 1) for kv in text.strip(',').split(',') if '=' in kv)
            requested, used, limited = (parse(group['quota'].group(i)) for i in (2, 3, 4))
            exceeded = []
            for key, value in requested.items():
                r, u, l = _quantity(value), _quantity(used.get(key)), _quantity(limited.get(key))
                if None not in (r, u, l) and r + u > l:
                    exceeded.append(f"{key}: requested {value}, used {used[key]} of {limited[key]}")
            message = (f"{kind}/{owner} cannot create its pods: ResourceQuota {name} exceeded"
                       + (f" ({'; '.join(exceeded)})" if exceeded else '')
                       + f", {group['count']} refusal(s)"
                       + (f" from {group['first']} to {group['last']}" if group['first'] else ''))
            steps = [f"kubectl describe resourcequota {name} -n <namespace>: what each pod of the namespace requests",
                     "lower the requests / limits of a component (spec.podTemplate.resources), or raise the quota"]
            if owner.startswith('confluent-operator'):
                message += (". It is the CFK operator: while the quota is full, this ReplicaSet cannot (re)create its operator "
                            "pod, and nothing is reconciled when no operator pod runs")
                steps.insert(0, "kubectl get pods -l app=confluent-operator -n <namespace>: which operator pod runs, if any")
            self._add_issue(severity='high', category='Resource Issues', message=message, file_path=group['file'],
                            resource=owner, resource_kind=kind, count=group['count'], dedupe_key=f"quota:{name}:{owner}")
            self.issues[-1]['next_steps'] = steps

    def _check_rollouts(self):
        """A CR whose image is not what runs: its StatefulSet still has another image (the operator did not apply the
        CR: block-reconcile, operator down), or some of its pods run another CP version (roll not complete). What runs
        comes from the pod manifests, else from the CP version each pod logs at startup."""
        for name, cr in sorted(self.cr_images.items()):
            wanted = environment.image_version(cr['image'])
            if not wanted:
                continue
            kind = cr.get('kind') or ''
            repo = cr['image'].split('@')[0].rsplit(':', 1)[0]
            sts = self.statefulsets.get(name) or {}
            stale_sts = [i for i in sts.get('images', []) if i.split('@')[0].rsplit(':', 1)[0] == repo
                         and environment.image_version(i) not in (None, wanted)]
            pods = sorted({p for p in list(self.pod_images) + list(self.log_versions)
                           if _POD_SUFFIX_RES[0].sub('', p) == name and _POD_SUFFIX_RES[0].search(p)})
            behind = {}  # (version, source) -> pods
            for pod in pods:
                if pod in self.pod_images:
                    running, source = environment.image_version(self.pod_images[pod]), 'image of the pod'
                elif kind in _VERSION_LOGGING_KINDS:
                    running, source = self.log_versions[pod][0], 'logged at startup'
                else:
                    continue
                if running and running != wanted:
                    behind.setdefault((running, source), []).append(pod)
            if not stale_sts and not behind:
                continue
            blocked = name in self.blocked_crs
            parts = [f"{kind}/{name} asks for {wanted} (image tag {environment.image_tag(cr['image'])})"]
            if stale_sts:
                parts.append(f"its StatefulSet still has {environment.image_tag(stale_sts[0])}: the operator did not "
                             "apply the CR")
            if behind:
                parts.append(", ".join(f"{', '.join(names)} {'runs' if len(names) == 1 else 'run'} {version} ({source})"
                                       for (version, source), names in sorted(behind.items())))
            if sts.get('replicas'):
                roll = f"StatefulSet {name}: {sts.get('updated', '?')}/{sts['replicas']} replicas updated, " \
                       f"{sts.get('ready', 0)}/{sts['replicas']} ready"
                if sts.get('current') and sts.get('update') and sts['current'] != sts['update']:
                    roll += f", roll from revision {sts['current']} to {sts['update']} not complete"
                parts.append(roll)
            if blocked:
                parts.append(f"{kind}/{name} has platform.confluent.io/block-reconcile=true")
            steps = []
            if blocked:
                steps.append(f"remove platform.confluent.io/block-reconcile from {kind}/{name}: the operator then rolls "
                             "the pods itself. A pod deleted by hand while it is blocked comes back with the old spec")
            if stale_sts and not blocked:
                steps.append("the operator did not apply the CR: look at its log for this CR (apply failed, reconcile "
                             "errors) and check that an operator pod runs (quota, crash loop)")
            if behind and not stale_sts:
                steps.append("CFK rolls one pod at a time, once the cluster is healthy (pods Ready, no under-replicated "
                             "partition): look at the pod that is not Ready and at the roll lines of the operator log")
            steps.append(f"kubectl get statefulset {name} -n <namespace> -o jsonpath='{{.status.updatedReplicas}}/"
                         "{.status.replicas} {.status.currentRevision} {.status.updateRevision}'")
            self._add_issue(
                severity='high' if blocked or stale_sts or (sts.get('updated') or 0) < (sts.get('replicas') or 0) else 'medium',
                category='Rollout Issues', message="; ".join(parts),
                file_path=cr.get('file') or sts.get('file') or 'cluster-resources',
                resource=name, resource_kind=kind, dedupe_key=f"rollout:{kind}:{name}",
            )
            self.issues[-1]['next_steps'] = steps

    def _record_kraft_migration_log(self, line: str, rel: str):
        """"Migration current status SETUP/SubPhaseSetupKRaftControllerHealthy: …, requeuing" of the operator log"""
        m = kraft_migration.STATUS_LINE_RE.search(line)
        if not m:
            return
        ts = kraft_migration._parse_ts(line[:120])
        seen = self.kraft_migration_log.setdefault((m.group(1), m.group(2)), {'count': 0, 'first': None, 'last': None, 'file': rel})
        seen['count'] += 1
        seen['reason'] = m.group(3).strip()
        if ts and (seen['first'] is None or ts < seen['first']):
            seen['first'] = ts
        if ts and (seen['last'] is None or ts > seen['last']):
            seen['last'] = ts

    def _check_kraft_migrations(self):
        """One finding per KRaftMigrationJob: phase / sub-phase, how long it has been there, the last error and the next
        steps of the sub-phase (kraft_migration.py). From the operator log alone when the bundle has no KMJ CR."""
        names = set(self.kraft_migrations) | set(self.kraft_migration_events)
        if not names and self.kraft_migration_log:
            names = {'<name not in the bundle>'}
        for name in sorted(names):
            cr = self.kraft_migrations.get(name) or {}
            found = kraft_migration.finding(name, cr.get('status') or {}, self.kraft_migration_events.get(name) or [],
                                            self.kraft_migration_log)
            if found is None:
                continue
            log_file = next((v['file'] for v in self.kraft_migration_log.values()), None)
            self._add_issue(
                severity=found['severity'], category='KRaft Migration', message=found['message'],
                file_path=cr.get('file') or log_file or 'event.yaml',
                resource=name, resource_kind='KRaftMigrationJob', dedupe_key=f"kraft-migration-finding:{name}",
            )
            issue = self.issues[-1]
            issue.update(next_steps=found['next_steps'], docs=found['docs'], runbooks=['kraft_migration'],
                         phase=found['phase'], sub_phase=found['sub_phase'])
            # built after the walk: attribute it here, to the KRaftController side when nothing better is known
            self._assign_component(issue)
            if issue.get('component') in (None, 'other', 'operator'):
                issue['component'] = 'kraftcontroller'

    def _mark_transient(self):
        """Probe failures and back-offs of the events / kubectl output of a pod that is Running and Ready in the bundle,
        with few restarts: low, the pod recovered (a Kafka pod not Ready while it starts, Connect restarted before Kafka
        was up). Its pod status findings (restarted N times, still waiting) keep their severity."""
        for issue in self.issues:
            if issue['category'] not in _TRANSIENT_CATEGORIES or issue.get('line_number') and 'event' not in issue['file'].lower():
                continue
            kind, pod = issue.get('_resource') or ('', '')
            if kind != 'Pod':
                found = _EVENT_POD_RE.search(issue['message'])
                pod = found.group(1) if found else ''
            if issue['message'].startswith('Container '):
                continue
            if pod in self.pod_health:
                ready, restarts = self.pod_health[pod]
                why = f"pod {pod} is Running and Ready in the bundle, {restarts} restart(s)"
            else:
                # no pod manifest (trimmed bundle): its StatefulSet has every replica ready and updated
                statefulset = _POD_SUFFIX_RES[0].sub('', pod)
                ready, restarts = self.statefulset_ready.get(statefulset, False), 0
                why = f"StatefulSet {statefulset} has every replica ready in the bundle"
            if not ready or restarts >= _TRANSIENT_MAX_RESTARTS:
                continue
            issue['severity'] = 'low'
            issue['transient'] = True
            issue['message'] += f" [transient: {why}]"

    def _check_pod_config(self, pod: Dict, file_path: str):
        """Check pod status for issues"""
        name = (pod.get('metadata') or {}).get('name', '?')
        status = pod.get('status') or {}
        phase = status.get('phase', '')

        if phase in ('Failed', 'Unknown'):
            self._add_issue(
                severity='high',
                category='Pod Status',
                message=f"Pod {name} in {phase} phase: {status.get('reason', '')} {status.get('message', '')}".strip(),
                file_path=file_path,
                resource=name, resource_kind='Pod',
                context=yaml.safe_dump(status, default_flow_style=False),
            )
        elif phase == 'Pending':
            unscheduled = [c for c in status.get('conditions') or []
                           if c.get('type') == 'PodScheduled' and c.get('status') == 'False']
            self._add_issue(
                severity='high' if unscheduled else 'medium',
                category='Scheduling Issues' if unscheduled else 'Pod Status',
                message=f"Pod {name} is Pending"
                        + (f": {unscheduled[0].get('message', '')}" if unscheduled else ''),
                file_path=file_path,
                resource=name, resource_kind='Pod',
            )

        statuses = [(c, True) for c in status.get('initContainerStatuses') or []] + \
                   [(c, False) for c in status.get('containerStatuses') or []]
        containers = status.get('containerStatuses') or []
        spec_images = [str(c.get('image', '')) for c in (pod.get('spec') or {}).get('containers') or [] if isinstance(c, dict)]
        if spec_images:
            # the image of the spec has the tag; the status one is sometimes only a digest
            status_image = str(containers[0].get('image', '')) if containers else ''
            self.pod_images[name] = status_image if environment.image_version(status_image) else spec_images[0]
        self.pod_health[name] = (
            phase == 'Running' and bool(containers) and all(c.get('ready') for c in containers),
            max([c.get('restartCount', 0) or 0 for c, _ in statuses] or [0]),
        )
        for container, is_init in statuses:
            cname = f"{name}/{container.get('name', '?')}" + (' (init)' if is_init else '')
            state = container.get('state') or {}
            last_state = container.get('lastState') or {}
            restarts = container.get('restartCount', 0) or 0

            waiting = state.get('waiting')
            if waiting and waiting.get('reason') not in _TRANSIENT_WAITING:
                reason = waiting.get('reason', '')
                match = self._classify(self._k8s_re, reason)
                severity, category = (match[0], match[1]) if match else ('medium', 'Container Status')
                if is_init and category == 'Pod Failures':
                    category = 'Init Container Issues'
                self._add_issue(
                    severity=severity,
                    category=category,
                    message=f"Container {cname} waiting: {reason} - {waiting.get('message', '')}",
                    file_path=file_path,
                    resource=name, resource_kind='Pod',
                )

            terminated = state.get('terminated')
            if terminated and terminated.get('exitCode', 0) != 0 and not (is_init and terminated.get('reason') == 'Completed'):
                self._add_issue(
                    severity='high',
                    category='Init Container Issues' if is_init else 'Pod Failures',
                    message=f"Container {cname} terminated: {terminated.get('reason', '')} exitCode={terminated.get('exitCode')}",
                    file_path=file_path,
                    resource=name, resource_kind='Pod',
                )

            last_terminated = last_state.get('terminated') or {}
            if last_terminated.get('reason') == 'OOMKilled':
                self._add_issue(
                    severity='critical',
                    category='Resource Issues',
                    message=f"Container {cname} was OOMKilled (lastState, exitCode={last_terminated.get('exitCode')}, restarts={restarts})",
                    file_path=file_path,
                    resource=name, resource_kind='Pod',
                )
            elif last_terminated and last_terminated.get('exitCode', 0) != 0 and restarts:
                self._add_issue(
                    severity='medium',
                    category='Pod Failures',
                    message=f"Container {cname} previously terminated: {last_terminated.get('reason', '')} exitCode={last_terminated.get('exitCode')} (restarts={restarts})",
                    file_path=file_path,
                    resource=name, resource_kind='Pod',
                )

            if restarts >= 3:
                self._add_issue(
                    severity='high' if restarts >= 10 else 'medium',
                    category='Pod Failures',
                    message=f"Container {cname} restarted {restarts} times",
                    file_path=file_path,
                    resource=name, resource_kind='Pod',
                )

    def _check_confluent_component_config(self, component: Dict, file_path: str):
        """Check a CFK custom resource (any kind under platform.confluent.io)"""
        spec = component.get('spec') or {}
        status = component.get('status') or {}
        metadata = component.get('metadata') or {}
        kind = component.get('kind', '')
        ref = f"{kind}/{metadata.get('name', '?')}"

        annotations = metadata.get('annotations') or {}
        if str(annotations.get('platform.confluent.io/block-reconcile', '')).lower() == 'true':
            self.blocked_crs.add(metadata.get('name'))
            self._add_issue(
                severity='low',
                category='Reconciliation Blocked',
                message=f"{ref} has platform.confluent.io/block-reconcile=true",
                file_path=file_path,
                resource=metadata.get('name'), resource_kind=kind,
            )

        if metadata.get('deletionTimestamp') and metadata.get('finalizers'):
            self._add_issue(
                severity='medium',
                category='Finalizer Issues',
                message=f"{ref} is being deleted since {metadata['deletionTimestamp']} but still has finalizers {metadata['finalizers']}",
                file_path=file_path,
                resource=metadata.get('name'), resource_kind=kind,
            )

        if 'replicas' in spec and spec.get('replicas') == 0:
            self._add_issue(
                severity='medium',
                category='Configuration',
                message=f"{ref} has 0 replicas - component is scaled down",
                file_path=file_path,
                resource=metadata.get('name'), resource_kind=kind,
            )

        # Component CRs report `phase`, Connector / KafkaTopic / ConfluentRolebinding… report `state`. A
        # KRaftMigrationJob gets its own finding (_check_kraft_migrations)
        for key in (() if kind == 'KRaftMigrationJob' else ('phase', 'state')):
            value = status.get(key)
            if not isinstance(value, str) or not value or value.upper() in _GOOD_CR_STATES:
                continue
            failed = re.search(r'FAIL|ERROR|DEGRADED|CRASH', value, re.IGNORECASE) is not None
            category = 'Connect Issues' if kind == 'Connector' else 'Component Status'
            self._add_issue(
                severity='high' if failed else 'medium',
                category=category,
                message=f"{ref} status.{key} is {value}",
                file_path=file_path,
                resource=metadata.get('name'), resource_kind=kind,
                context=yaml.safe_dump(status, default_flow_style=False, sort_keys=False)[:2000],
            )

        replicas = status.get('replicas', spec.get('replicas'))
        ready = status.get('readyReplicas')
        if isinstance(replicas, int) and isinstance(ready, int) and ready < replicas:
            self._add_issue(
                severity='high' if ready == 0 else 'medium',
                category='Component Status',
                message=f"{ref} has {ready}/{replicas} ready replicas",
                file_path=file_path,
                resource=metadata.get('name'), resource_kind=kind,
            )

        failed_tasks = status.get('failedTasks')
        if failed_tasks:
            self._add_issue(
                severity='high',
                category='Connect Issues',
                message=f"{ref} has failed tasks: {json.dumps(failed_tasks, default=str)[:300]}",
                file_path=file_path,
                resource=metadata.get('name'), resource_kind=kind,
            )

        for condition in status.get('conditions') or []:
            if not isinstance(condition, dict):
                continue
            condition_type = condition.get('type', '')
            text = f"{condition.get('reason', '')} {condition.get('message', '')}"
            bad_when_false = _GOOD_WHEN_TRUE_RE.search(condition_type) or _FAILURE_WORDS_RE.search(text)
            if condition.get('status') == 'False' and bad_when_false and 'progressing' not in condition_type.lower():
                self._add_issue(
                    severity='medium',
                    category='Component Status',
                    message=f"{ref} condition {condition_type} is False: {condition.get('reason', '')} {condition.get('message', '')}".strip(),
                    file_path=file_path,
                    resource=metadata.get('name'), resource_kind=kind,
                )
