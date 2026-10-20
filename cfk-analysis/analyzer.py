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
    'controlcenter': 'controlcenter', 'kafkarestproxy': 'kafkarestproxy',
}
# Sub-folders of a component folder that are not the CR name
_GENERIC_DIRS = {'logs', 'pods', 'cm', 'sts', 'svc', 'pv', 'pvc', 'pdb', 'deployment', 'secrets'}
# Last resort for names that are not in the bundle: keywords, most specific first
_NAME_KEYWORDS = (
    ('kraft', 'kraftcontroller'), ('zookeeper', 'zookeeper'), ('schemaregistry', 'schemaregistry'),
    ('schema-registry', 'schemaregistry'), ('ksql', 'ksqldb'), ('controlcenter', 'controlcenter'),
    ('control-center', 'controlcenter'), ('restproxy', 'kafkarestproxy'), ('kafka-rest', 'kafkarestproxy'),
    ('operator', 'operator'), ('connect', 'connect'), ('replicator', 'connect'), ('kafka', 'kafka'),
)
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
        self.error_patterns = {
            'oom_killed': {
                'pattern': r'OOMKilled|java\.lang\.OutOfMemoryError|Out of memory',
                'severity': 'critical',
                'category': 'Resource Issues'
            },
            'license_error': {
                'pattern': r'license has expired|license is invalid|LicenseManagerException|license verification failed|License manager.{0,40}error',
                'severity': 'critical',
                'category': 'License Issues'
            },
            'storage_error': {
                'pattern': r'no space left on device|disk.{0,20}full|KafkaStorageException|log director(?:y|ies).{0,60}offline|PersistentVolumeClaim.{0,80}pending',
                'severity': 'critical',
                'category': 'Storage Issues'
            },
            'tls_handshake': {
                'pattern': r'SSLHandshakeException|SSLException|SSL handshake failed|PKIX path|unable to find valid certification path|certificate verify failed|x509:|tls: bad certificate|tls handshake (?:error|failure|timeout)|bad_certificate|certificate_unknown|handshake_failure|certificate (?:has )?expired',
                'severity': 'high',
                'category': 'Certificate/TLS Issues'
            },
            'authentication_failed': {
                'pattern': r'SaslAuthenticationException|AuthenticationException|authentication failed|failed authentication|invalid credentials|\b401 unauthorized\b|\bunauthorized\b|http (?:status|code|error)[ :=]*401',
                'severity': 'high',
                'category': 'Authentication Issues'
            },
            'mds_error': {
                'pattern': r'MDS.{0,40}failed|metadata service.{0,40}error|TokenBasedSecurityStore.{0,80}Exception|RBAC.{0,40}token|MdsException',
                'severity': 'high',
                'category': 'MDS/RBAC Issues'
            },
            'rbac_error': {
                'pattern': r'forbidden: User .{0,80} cannot|is forbidden|(?:Topic|Group|Cluster|TransactionalId)?AuthorizationException|not authorized to access|\b403 forbidden\b|http (?:status|code|error)[ :=]*403',
                'severity': 'high',
                'category': 'RBAC Issues'
            },
            'replication_error': {
                'pattern': r'InvalidReplicationFactorException|NotEnoughReplicas(?:AfterAppend)?Exception|replication factor.{0,60}(?:larger|greater) than|under.?min.?isr|replica fetcher.{0,60}(?:error|failed)|replication.{0,40}failed',
                'severity': 'high',
                'category': 'Replication Issues'
            },
            'kraft_error': {
                'pattern': r'KRaft.{0,80}error|controller.{0,40}election.{0,40}failed|quorum.{0,40}(?:error|timeout|unavailable)|NotControllerException|RaftClient.{0,80}(?:error|exception)|metadata log.{0,40}(?:corrupt|failed|error)',
                'severity': 'high',
                'category': 'KRaft Issues'
            },
            'zookeeper_error': {
                'pattern': r'zookeeper.{0,160}exception|SessionExpiredException|zookeeper.{0,80}session.{0,40}expired|KeeperException|ConnectionLoss',
                'severity': 'high',
                'category': 'Zookeeper Issues'
            },
            'dns_error': {
                'pattern': r'no such host|DNS resolution failed|dial tcp: lookup|UnknownHostException|Couldn\'t resolve server',
                'severity': 'high',
                'category': 'Network Issues'
            },
            'connection_refused': {
                'pattern': r'connection refused|Connection reset by peer|NoRouteToHostException|Broken pipe',
                'severity': 'high',
                'category': 'Network Issues'
            },
            'timeout': {
                'pattern': r'\btimed out\b|deadline exceeded|i/o timeout|TimeoutException',
                'severity': 'medium',
                'category': 'Network Issues'
            },
            'volume_mount': {
                'pattern': r'failed to mount|MountVolume\.SetUp failed|Unable to attach or mount volumes',
                'severity': 'high',
                'category': 'Volume Issues'
            },
            'operator_error': {
                'pattern': r'reconcile error|Failed to reconcile|Reconciler error|operator error',
                'severity': 'medium',
                'category': 'Operator Issues'
            },
            'schema_registry_error': {
                'pattern': r'SchemaRegistryException|RestClientException|Subject .{0,80}not found|Schema .{0,40}(?:not found|incompatible)',
                'severity': 'medium',
                'category': 'Schema Registry Issues'
            },
            'ksqldb_error': {
                'pattern': r'\bKsqlException\b|KSQL_PARSING_EXCEPTION|KsqlStatementException',
                'severity': 'medium',
                'category': 'KsqlDB Issues'
            },
            'connect_error': {
                'pattern': r'\bConnectException\b|\bRetriableException\b|connector .{0,40}is in FAILED state|Task threw an uncaught and unrecoverable exception|WorkerSinkTask|WorkerSourceTask',
                'severity': 'medium',
                'category': 'Connect Issues'
            },
            'controlcenter_error': {
                'pattern': r'ControlCenter.{0,40}Exception|c3 .{0,40}failed to',
                'severity': 'medium',
                'category': 'Control Center Issues'
            },
            'rest_proxy_error': {
                'pattern': r'kafka-rest.{0,80}exception|kafkarest.{0,80}exception|REST API.{0,40}failed',
                'severity': 'medium',
                'category': 'REST Proxy Issues'
            },
            'finalizer_stuck': {
                'pattern': r'finalizer.{0,80}blocking|deletion.{0,40}blocked',
                'severity': 'medium',
                'category': 'Finalizer Issues'
            },
            'reconcile_blocked': {
                'pattern': r'block-reconcile|reconciliation.{0,40}blocked',
                'severity': 'low',
                'category': 'Reconciliation Blocked'
            },
            'kafka_error': {
                'pattern': r'org\.apache\.kafka\.\S+Exception|\bKafkaException\b',
                'severity': 'medium',
                'category': 'Kafka Issues'
            },
            'java_error': {
                'pattern': r'java\.lang\.NullPointerException|java\.io\.IOException|java\.lang\.IllegalStateException|java\.lang\.IllegalArgumentException',
                'severity': 'medium',
                'category': 'Application Errors'
            },
        }

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
            parts.append(f"(?P<{group}>{info['pattern'].lower()})")
            meta[group] = (info['severity'], info['category'], name)
            priority[group] = index
        return re.compile('|'.join(parts)), meta, priority

    def analyze(self) -> Dict[str, Any]:
        """Main analysis method"""
        start_time = datetime.now()

        for name in ('cluster-resources', 'operator', 'misc'):
            if os.path.isdir(os.path.join(self.bundle_path, name)):
                self.coverage['layout'].append(name)

        for root, dirs, files in os.walk(self.bundle_path):
            dirs.sort()
            for file in sorted(files):
                file_path = os.path.join(root, file)
                if os.path.islink(file_path):
                    self.coverage['skipped_files'] += 1
                    continue
                self._index_path(self._rel(file_path))
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
        for issue in self.issues:
            self._assign_component(issue)

        self.summary['analysis_time'] = (datetime.now() - start_time).total_seconds()
        self.summary['total_issues'] = len(self.issues)
        for issue in self.issues:
            severity = issue.get('severity', 'low')
            if severity in self.summary:
                self.summary[severity] += 1

        return {
            'summary': self.summary,
            'coverage': self.coverage,
            'issues': sorted(
                self.issues,
                key=lambda x: (_SEVERITY_ORDER.get(x['severity'], 4), -x.get('count', 1)),
            ),
        }

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
                   dedupe_key: str = None, resource: str = None, resource_kind: str = None):
        """Add an issue, or bump the occurrence count of an identical one.

        Identical means same category, same file (rotated logs of the same pod count
        as the same file) and the same normalized message.
        `resource` / `resource_kind` name the pod or CR the issue is about, to find its
        component when the file is shared (events, pods.yaml).
        """
        file_key = re.sub(r'\.log(?:\.[\w-]+)?(?:\.gz)?$', '.log', file_path)
        signature = f"{category}:{file_key}:{dedupe_key or self._normalize_signature(message)}"

        existing = self.issue_index.get(signature)
        if existing is not None:
            existing['count'] = existing.get('count', 1) + count
            if _SEVERITY_ORDER[severity] < _SEVERITY_ORDER[existing['severity']]:
                existing['severity'] = severity
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

        self.issue_index[signature] = issue
        self.issues.append(issue)

    # ── Component attribution ─────────────────────────────────────────────

    def _index_component(self, name: str, component: str, instance: str = None):
        if name and component in COMPONENTS:
            self.component_index.setdefault(name, (component, instance or name))

    def _index_path(self, file_path: str):
        """cluster-resources/<type>/<name>/... names a CR of that type"""
        parts = file_path.replace('\\', '/').split('/')[:-1]
        for index, part in enumerate(parts[:-1]):
            if index > 0 and parts[index - 1] == 'cluster-resources' and part.lower() in COMPONENTS:
                self._index_component(parts[index + 1], part.lower())

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

    def _lookup_resource(self, kind: str, name: str):
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
        """Return (severity, category, name) of the first pattern, in declaration order, that matches"""
        regex, meta, priority = compiled
        best = None
        for m in regex.finditer(text.lower()):
            if best is None or priority[m.lastgroup] < priority[best]:
                best = m.lastgroup
        return meta[best] if best else None

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

            level = self._detect_level(line)
            if level is None and _EXCEPTION_HEAD_RE.match(line):
                level = 'ERROR'
            if level is not None:
                record = (line_num, level, line, [])
                continue

            line_lower = line.lower()
            if any(t in line_lower for t in k8s_screen):
                self._handle_k8s_line(rel, lines, line_num, line)

        flush()

    def _handle_record(self, rel: str, lines: List[str], line_num: int, level: str,
                       head: str, caused_by: List[str]):
        text = head + ' ' + ' '.join(caused_by)
        # The root cause (last Caused by) wins over the symptom when both match.
        match = None
        for candidate in reversed(caused_by):
            match = self._classify(self._error_re, candidate)
            if match:
                break
        if match is None:
            match = self._classify(self._error_re, head) or self._classify(self._k8s_re, text)

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

        context_lines = lines[max(0, line_num - 3):min(len(lines), line_num + 2)]
        self._add_issue(
            severity=severity,
            category=category,
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
            kind = obj.get('kind', '')
            api_version = str(obj.get('apiVersion', ''))
            metadata = obj.get('metadata') or {}
            if kind == 'Pod':
                self.coverage['pods'] += 1
                labels = metadata.get('labels') or {}
                self._index_component(metadata.get('name'), str(labels.get('platform.confluent.io/type', '')).lower(),
                                      labels.get('app'))
                self._check_pod_config(obj, relative_path)
            elif kind == 'Event':
                self._process_event(obj, file_path)
            elif api_version.startswith('platform.confluent.io/'):
                self.coverage['custom_resources'] += 1
                # a Connector belongs to its Connect cluster
                cluster = ((obj.get('spec') or {}).get('connectClusterRef') or {}).get('name')
                self._index_component(metadata.get('name'), _KIND_COMPONENT.get(kind.lower(), ''), cluster)
                self._check_confluent_component_config(obj, relative_path)

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

        # Component CRs report `phase`, Connector / KafkaTopic / ConfluentRolebinding… report `state`
        for key in ('phase', 'state'):
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
            if condition.get('status') == 'False' and 'progressing' not in condition_type.lower():
                self._add_issue(
                    severity='medium',
                    category='Component Status',
                    message=f"{ref} condition {condition_type} is False: {condition.get('reason', '')} {condition.get('message', '')}".strip(),
                    file_path=file_path,
                    resource=metadata.get('name'), resource_kind=kind,
                )
