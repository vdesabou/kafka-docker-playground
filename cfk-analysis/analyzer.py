"""
CFK Bundle Analyzer - Core analysis engine
Analyzes Confluent for Kubernetes support bundles for common issues
"""

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
from collections import defaultdict
from typing import Dict, List, Any, Tuple


class CFKBundleAnalyzer:
    """Main analyzer class for CFK support bundles"""

    def __init__(self, bundle_path: str):
        self.bundle_path = bundle_path
        self.issues = []
        self.issue_signatures = set()  # For deduplication
        self.summary = {
            'total_issues': 0,
            'critical': 0,
            'high': 0,
            'medium': 0,
            'low': 0,
            'files_analyzed': 0,
            'analysis_time': None
        }

        # Common error patterns
        self.error_patterns = {
            'crashloopbackoff': {
                'pattern': r'CrashLoopBackOff|Back-off restarting failed container',
                'severity': 'critical',
                'category': 'Pod Failures'
            },
            'oom_killed': {
                'pattern': r'OOMKilled|Out of memory',
                'severity': 'critical',
                'category': 'Resource Issues'
            },
            'image_pull_error': {
                'pattern': r'ImagePullBackOff|ErrImagePull|Failed to pull image',
                'severity': 'high',
                'category': 'Image Issues'
            },
            'tls_handshake': {
                'pattern': r'TLS handshake|certificate verify failed|x509|SSL|tls: bad certificate',
                'severity': 'high',
                'category': 'Certificate/TLS Issues'
            },
            'authentication_failed': {
                'pattern': r'authentication failed|unauthorized|401|403 Forbidden|SASL authentication failed',
                'severity': 'high',
                'category': 'Authentication Issues'
            },
            'connection_refused': {
                'pattern': r'connection refused|connect: connection refused|Connection reset by peer',
                'severity': 'high',
                'category': 'Network Issues'
            },
            'timeout': {
                # Bare `timeout` matches config keys like `timeoutSeconds: 30`.
                # Require an actual error phrasing.
                'pattern': r'\btimed out\b|deadline exceeded|i/o timeout|Read timed out|operation timed out|Connect timed out',
                'severity': 'medium',
                'category': 'Network Issues'
            },
            'dns_error': {
                'pattern': r'no such host|DNS resolution failed|dial tcp: lookup',
                'severity': 'high',
                'category': 'Network Issues'
            },
            'evicted': {
                'pattern': r'Evicted|The node was low on resource',
                'severity': 'high',
                'category': 'Resource Issues'
            },
            'pending_pod': {
                'pattern': r'FailedScheduling|Insufficient cpu|Insufficient memory|PodInitializing',
                'severity': 'medium',
                'category': 'Scheduling Issues'
            },
            'rbac_error': {
                'pattern': r'RBAC|forbidden: User .* cannot|is forbidden',
                'severity': 'high',
                'category': 'RBAC Issues'
            },
            'volume_mount': {
                'pattern': r'failed to mount|MountVolume.SetUp failed|Unable to attach or mount volumes',
                'severity': 'high',
                'category': 'Volume Issues'
            },
            'operator_error': {
                'pattern': r'operator error|reconcile error|Failed to reconcile',
                'severity': 'medium',
                'category': 'Operator Issues'
            },
            'kafka_error': {
                # Drop loose `kafka.*error` (matches "kafka producer ready, no errors").
                # Escape dots so `org.apache.kafka` doesn't match arbitrary chars.
                'pattern': r'org\.apache\.kafka\.[^\s]+Exception|\bKafkaException\b',
                'severity': 'medium',
                'category': 'Kafka Issues'
            },
            'java_error': {
                # Escape dots: unescaped `.` matches any char and produces false
                # positives on package-name fragments.
                'pattern': r'\bjava\.lang\.OutOfMemoryError\b|\bjava\.lang\.NullPointerException\b|\bjava\.io\.IOException\b',
                'severity': 'medium',
                'category': 'Application Errors'
            },
            'mds_error': {
                'pattern': r'MDS.*failed|metadata service.*error|TokenBasedSecurityStore.*Exception|RBAC.*token',
                'severity': 'high',
                'category': 'MDS/RBAC Issues'
            },
            'license_error': {
                # Drop `confluent.*license` — it matches every config snippet
                # containing strings like `confluent-license-producer`.
                'pattern': r'license has expired|license is invalid|LicenseManagerException|license verification failed|License manager.{0,40}error',
                'severity': 'critical',
                'category': 'License Issues'
            },
            'schema_registry_error': {
                'pattern': r'SchemaRegistryException|Subject .{0,80}not found|Schema .{0,40}(?:not found|incompatible)',
                'severity': 'medium',
                'category': 'Schema Registry Issues'
            },
            'ksqldb_error': {
                # Drop the loose `.*error|.*failed` alternatives; they match
                # kubectl table headers like `TASKS-FAILED`.
                'pattern': r'\bKsqlException\b|KSQL_PARSING_EXCEPTION',
                'severity': 'medium',
                'category': 'KsqlDB Issues'
            },
            'connect_error': {
                # Drop `task.*failed` (matches `TASKS-FAILED` column header)
                # and `connector.*error` (matches healthy connector logs).
                'pattern': r'\bConnectException\b|connector .{0,40}is in FAILED state',
                'severity': 'medium',
                'category': 'Connect Issues'
            },
            'controlcenter_error': {
                # Tighten — original loose `.*` alternatives caught every
                # routine Control Center log line.
                'pattern': r'ControlCenter.{0,40}Exception|c3 .{0,40}failed to',
                'severity': 'medium',
                'category': 'Control Center Issues'
            },
            'zookeeper_error': {
                'pattern': r'zookeeper.*exception|ZK.*error|Session.*expired|ConnectionLoss',
                'severity': 'high',
                'category': 'Zookeeper Issues'
            },
            'kraft_error': {
                'pattern': r'KRaft.*error|controller.*election.*failed|metadata.*log|quorum.*error',
                'severity': 'high',
                'category': 'KRaft Issues'
            },
            'replication_error': {
                'pattern': r'replication.*failed|replica.*lag|ISR.*shrink|under.*replicated',
                'severity': 'high',
                'category': 'Replication Issues'
            },
            'storage_error': {
                'pattern': r'disk.*full|no space left|PersistentVolumeClaim.*pending|storage.*error',
                'severity': 'critical',
                'category': 'Storage Issues'
            },
            'finalizer_stuck': {
                'pattern': r'finalizer.*blocking|DELETING.*stuck|deletion.*blocked',
                'severity': 'medium',
                'category': 'Finalizer Issues'
            },
            'reconcile_blocked': {
                'pattern': r'block-reconcile=true|reconciliation.*blocked|reconcile.*disabled',
                'severity': 'low',
                'category': 'Reconciliation Blocked'
            },
            'init_container_error': {
                'pattern': r'init.*container.*failed|init:.*Error|init:.*CrashLoopBackOff',
                'severity': 'high',
                'category': 'Init Container Issues'
            },
            'liveness_probe_failed': {
                'pattern': r'Liveness probe failed|Readiness probe failed|probe.*unhealthy',
                'severity': 'high',
                'category': 'Health Check Issues'
            },
            'rest_proxy_error': {
                'pattern': r'rest.proxy.*error|kafka-rest.*exception|REST API.*failed',
                'severity': 'medium',
                'category': 'REST Proxy Issues'
            }
        }

        # Combine all 30 patterns into a single regex with named groups so a
        # whole log line is categorized in ONE search instead of 30.
        # - Lowercase both the line (per-line) and the pattern (once at compile
        #   time) and drop the IGNORECASE flag — IGNORECASE adds non-trivial
        #   per-char overhead in CPython's `re` engine.
        # - Replace unbounded `.*` with `.{0,160}` so a pattern like
        #   `init.*container.*failed` doesn't trigger O(n²) backtracking on
        #   long lines containing "init" but not "failed".
        # Real CFK bundles routinely contain 5M+ log lines; the original
        # per-line × per-pattern loop was 150M regex calls and would hang
        # for tens of minutes.
        def _bound_wildcards(p: str) -> str:
            return p.replace('.*', '.{0,160}')

        self._pattern_meta = {}
        combined_parts = []
        for name, info in self.error_patterns.items():
            group = f"p_{name}"
            combined_parts.append(
                f"(?P<{group}>{_bound_wildcards(info['pattern']).lower()})"
            )
            self._pattern_meta[group] = (info['severity'], info['category'], name)
        self._combined_re = re.compile('|'.join(combined_parts))

        # Cheap literal-only line screen. A line that contains NONE of these
        # tokens cannot match any specific pattern (verified by hand against
        # the 30 patterns). Using `any(tok in s)` over a tuple of literals is
        # ~3x faster than a precompiled regex alternation in CPython:
        # `str.__contains__` is a tight C loop.
        self._screen_tokens = (
            'error', 'fail', 'exception', 'fatal', 'severe', 'warn',
            'crashloop', 'backoff', 'oomkilled', 'killed', 'evicted',
            'imagepull', 'failedscheduling', 'unhealthy',
            'mountvolume', 'podinitializing', 'unable to attach',
            'no space left', 'persistentvolumeclaim',
            'unauthorized', 'forbidden', 'refused', 'reset by peer',
            'timeout', 'timed out', 'deadline', 'no such host',
            'dial tcp', 'x509', 'sasl', 'tls: bad', 'rbac',
            'expired', 'connectionloss', 'finalizer', 'deletion',
            'block-reconcile', 'reconciliation',
            'tokenbasedsecuritystore', 'kafkaexception',
            'ksqlexception', 'connectexception', 'outofmemoryerror',
            'nullpointerexception', 'ioexception', 'liveness probe',
            'readiness probe', 'license', 'low on resource',
            'metadata service', 'out of memory', 'pull image',
            'reconcile error', 'subject', 'under-replicated',
            'isr shrink', 'underminisr', 'disk', 'insufficient',
            'controller election', 'metadata log',
        )

    def analyze(self) -> Dict[str, Any]:
        """Main analysis method"""
        start_time = datetime.now()

        # Analyze different file types
        self._analyze_logs()
        self._analyze_events()
        self._analyze_yaml_configs()
        self._analyze_pod_status()

        # Calculate summary
        self.summary['analysis_time'] = (datetime.now() - start_time).total_seconds()
        self.summary['total_issues'] = len(self.issues)

        for issue in self.issues:
            severity = issue.get('severity', 'low')
            if severity in self.summary:
                self.summary[severity] += 1

        return {
            'summary': self.summary,
            'issues': sorted(self.issues, key=lambda x: self._severity_order(x['severity']))
        }

    def _severity_order(self, severity: str) -> int:
        """Return numeric order for severity sorting"""
        order = {'critical': 0, 'high': 1, 'medium': 2, 'low': 3}
        return order.get(severity, 4)

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
        (re.compile(r'\b\d{6,}\b'), '<NUM>'),
        (re.compile(r'\(\S+\.java:\d+\)'), '(<JAVA>)'),
        (re.compile(r'\s+'), ' '),
    ]

    def _normalize_signature(self, text: str) -> str:
        out = text
        for pat, repl in self._NORMALIZE_PATTERNS:
            out = pat.sub(repl, out)
        return out.strip()[:160]

    def _add_issue(self, severity: str, category: str, message: str,
                   file_path: str, line_number: int = None, context: str = None):
        """Add an issue to the issues list with deduplication"""
        # Normalize the message so near-duplicate log lines (differing only
        # by timestamp, request ID, line number) collapse into one issue.
        signature = f"{category}:{file_path}:{self._normalize_signature(message)}"

        if signature in self.issue_signatures:
            return

        self.issue_signatures.add(signature)

        issue = {
            'severity': severity,
            'category': category,
            'message': message,
            'file': file_path,
            'timestamp': datetime.now().isoformat()
        }

        if line_number:
            issue['line_number'] = line_number
        if context:
            issue['context'] = context

        self.issues.append(issue)

    def _analyze_logs(self):
        """Analyze log files for errors and warnings"""
        log_extensions = ['.log', '.txt']

        for root, dirs, files in os.walk(self.bundle_path):
            for file in files:
                if any(file.endswith(ext) for ext in log_extensions):
                    file_path = os.path.join(root, file)
                    self._analyze_log_file(file_path)

    # Skip lines that are obviously noise.
    # - log4j:WARN / SLF4J init noise
    # - Stack-frame continuations ("\tat com.foo.bar(...)", "... 3 more")
    # - Empty lines
    # - Config dumps: `key: value` / `key=value` / JVM flag rows
    #   These match many of our pattern literals (`timeout`, `kafka`, `license`,
    #   `connector`, `task`) inside YAML/properties/JVM-flag content embedded
    #   in broker startup logs, producing false positives.
    _NOISE_SKIP = re.compile(
        r'(log4j:WARN|SLF4J:|TRACE\s|^\s*at\s+\S+\(|^\s*\.\.\. \d+ more|^\s*$|'
        r'^\s*[A-Za-z_-][\w.-]*\s*[:=]\s*\S|'                # YAML / properties: key: value, key=value
        r'^\s*(bool|intx|uintx|double|ccstr|ccstrlist|size_t)\s+\w+\s*[:=]|'  # JVM flag dump
        r'^\s*\d+\s+[A-Z_]+\s+=)',                            # numbered config dump rows
        re.IGNORECASE,
    )

    def _analyze_log_file(self, file_path: str):
        """Analyze a single log file"""
        try:
            with open(file_path, 'r', encoding='utf-8', errors='ignore') as f:
                lines = f.readlines()
                self.summary['files_analyzed'] += 1

                relative_path = os.path.relpath(file_path, self.bundle_path)

                screen_tokens = self._screen_tokens
                noise_skip = self._NOISE_SKIP
                for line_num, line in enumerate(lines, 1):
                    line_lower = line.lower()

                    # Fast-path screen: skip lines that contain no error-related
                    # token. `any(tok in s)` is the cheapest screen in CPython.
                    if not any(t in line_lower for t in screen_tokens):
                        continue

                    # Drop config dumps, stack-frame continuations, SLF4J noise.
                    # These match pattern literals (`kafka`, `timeout`, etc.)
                    # without representing an actual error.
                    if noise_skip.search(line):
                        continue

                    # One combined regex search per line via `finditer` returns
                    # every distinct pattern that matched, with `m.lastgroup`
                    # identifying which one. ~30x fewer regex calls than a
                    # per-line × per-pattern loop, and patterns run without
                    # the IGNORECASE flag because we lowered both sides.
                    seen_groups = set()
                    for m in self._combined_re.finditer(line_lower):
                        gname = m.lastgroup
                        if gname is None or gname in seen_groups:
                            continue
                        seen_groups.add(gname)
                        severity, category, error_name = self._pattern_meta[gname]
                        context_lines = lines[max(0, line_num - 3):min(len(lines), line_num + 2)]
                        self._add_issue(
                            severity=severity,
                            category=category,
                            message=f"Found {error_name.replace('_', ' ').title()}: {line.strip()[:200]}",
                            file_path=relative_path,
                            line_number=line_num,
                            context=''.join(context_lines)
                        )
        except Exception as e:
            print(f"Error analyzing log file {file_path}: {str(e)}")

    def _analyze_events(self):
        """Analyze Kubernetes events"""
        for root, dirs, files in os.walk(self.bundle_path):
            for file in files:
                if 'event' in file.lower() and (file.endswith('.yaml') or file.endswith('.json')):
                    file_path = os.path.join(root, file)
                    self._analyze_event_file(file_path)

    def _analyze_event_file(self, file_path: str):
        """Analyze Kubernetes events file"""
        try:
            with open(file_path, 'r', encoding='utf-8') as f:
                content = f.read()
                self.summary['files_analyzed'] += 1

                # Try to parse as YAML/JSON
                try:
                    if file_path.endswith('.json'):
                        data = json.loads(content)
                    else:
                        data = yaml.safe_load(content)

                    if isinstance(data, dict) and 'items' in data:
                        events = data['items']
                    elif isinstance(data, list):
                        events = data
                    else:
                        events = [data]

                    for event in events:
                        if isinstance(event, dict):
                            self._process_event(event, file_path)

                except (json.JSONDecodeError, yaml.YAMLError):
                    # Fallback to text analysis
                    self._analyze_log_file(file_path)

        except Exception as e:
            print(f"Error analyzing event file {file_path}: {str(e)}")

    def _process_event(self, event: Dict, file_path: str):
        """Process a single Kubernetes event"""
        event_type = event.get('type', '')
        reason = event.get('reason', '')
        message = event.get('message', '')

        if event_type == 'Warning' or event_type == 'Error':
            severity = 'high' if event_type == 'Error' else 'medium'
            relative_path = os.path.relpath(file_path, self.bundle_path)

            self._add_issue(
                severity=severity,
                category='Kubernetes Events',
                message=f"{reason}: {message}",
                file_path=relative_path,
                context=json.dumps(event, indent=2)
            )

    def _analyze_yaml_configs(self):
        """Analyze YAML configuration files"""
        for root, dirs, files in os.walk(self.bundle_path):
            for file in files:
                if file.endswith(('.yaml', '.yml')) and 'event' not in file.lower():
                    file_path = os.path.join(root, file)
                    self._analyze_yaml_file(file_path)

    def _analyze_yaml_file(self, file_path: str):
        """Analyze a single YAML configuration file"""
        try:
            with open(file_path, 'r', encoding='utf-8') as f:
                data = yaml.safe_load(f)
                self.summary['files_analyzed'] += 1

                if not isinstance(data, dict):
                    return

                kind = data.get('kind', '')
                relative_path = os.path.relpath(file_path, self.bundle_path)

                # Check for common configuration issues
                if kind == 'Pod':
                    self._check_pod_config(data, relative_path)
                elif kind in ['Kafka', 'Zookeeper', 'Connect', 'SchemaRegistry', 'KsqlDB', 'ControlCenter']:
                    self._check_confluent_component_config(data, relative_path)

        except Exception as e:
            print(f"Error analyzing YAML file {file_path}: {str(e)}")

    def _check_pod_config(self, pod: Dict, file_path: str):
        """Check pod configuration for issues"""
        status = pod.get('status', {})
        phase = status.get('phase', '')

        # Check pod phase
        if phase in ['Failed', 'Unknown']:
            self._add_issue(
                severity='high',
                category='Pod Status',
                message=f"Pod in {phase} state",
                file_path=file_path,
                context=yaml.dump(status)
            )

        # Check container statuses
        container_statuses = status.get('containerStatuses', [])
        for container in container_statuses:
            state = container.get('state', {})
            if 'waiting' in state:
                reason = state['waiting'].get('reason', '')
                message = state['waiting'].get('message', '')
                self._add_issue(
                    severity='medium',
                    category='Container Status',
                    message=f"Container waiting: {reason} - {message}",
                    file_path=file_path
                )

    def _check_confluent_component_config(self, component: Dict, file_path: str):
        """Check Confluent component configuration"""
        spec = component.get('spec', {})
        status = component.get('status', {})
        kind = component.get('kind', '')

        # Check replicas
        replicas = spec.get('replicas', 1)
        if replicas == 0:
            self._add_issue(
                severity='medium',
                category='Configuration',
                message=f"{kind} has 0 replicas - component is scaled down",
                file_path=file_path
            )

        # Check status conditions
        conditions = status.get('conditions', [])
        for condition in conditions:
            if isinstance(condition, dict):
                condition_type = condition.get('type', '')
                condition_status = condition.get('status', '')

                if condition_status == 'False' and condition_type != 'Progressing':
                    self._add_issue(
                        severity='medium',
                        category='Component Status',
                        message=f"{kind} condition {condition_type} is False: {condition.get('message', '')}",
                        file_path=file_path
                    )

    def _analyze_pod_status(self):
        """Analyze pod status from describe output"""
        for root, dirs, files in os.walk(self.bundle_path):
            for file in files:
                if 'describe' in file.lower() or 'pod' in file.lower():
                    file_path = os.path.join(root, file)
                    if file.endswith('.txt') or file.endswith('.log'):
                        self._analyze_log_file(file_path)
