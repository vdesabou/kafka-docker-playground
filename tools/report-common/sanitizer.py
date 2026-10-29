"""
Data Sanitizer of the log analyzers: redacts secrets, IPs, hostnames, emails and LDAP DNs.

- cfk-analysis/analyzer_cli.py sanitizes the results of a CFK support bundle (DataSanitizer.sanitize_results).
- playground analyze logs pipes the digest of each file and the records file of tools/log-analyzer/log_report.py
  through the command line below, with one --state file per run, so a value gets the same placeholder (<IP-1>,
  <HOST-2>…) in the text digest, the HTML report and the JSON:

    python3 -I sanitizer.py --state <file> < text > sanitized-text
    python3 -I sanitizer.py --state <file> --summary        # what was redacted, as JSON
    python3 -I sanitizer.py --state <file> --no-count < t   # same placeholders, secrets not counted twice

  Lines starting with @@PG (the markers of the records file: counts, line numbers, timestamps) are kept as they are.

Best effort: always review the output before sharing it outside Confluent.
"""

import argparse
import json
import os
import re
import sys
from collections import defaultdict
from typing import Dict, Any, Tuple


# Key names whose value is a secret. Keys ending with ref/name/file/path/location/type
# (secretRef, jaas.config.file…) point to a secret but are not one, and are kept.
_SECRET_KEY = (
    r'[\w.-]*(?:password|passwd|pwd|secret|token|api[_.-]?key|apikey|credentials?|'
    r'user\.info|auth\.info|private[_.-]?key|client[_.-]?secret|access[_.-]?key)[\w.-]*'
)
_SECRET_KV_RE = re.compile(
    r'(["\']?)(' + _SECRET_KEY + r')\1(\s*[:=]\s*)'
    r'("(?:[^"\\]|\\.)*"|\'[^\']*\'|\[hidden\]|[^\s,;}\]\)]+)',
    re.IGNORECASE,
)
_SECRET_KEY_KEEP_RE = re.compile(r'(?:ref|refs|name|file|path|location|type|mechanism|enabled)$', re.IGNORECASE)

_SIMPLE_RULES = [
    # PEM blocks (keys and certificates)
    (re.compile(r'-----BEGIN [A-Z ]+-----.*?-----END [A-Z ]+-----', re.DOTALL), '<PEM-REDACTED>'),
    # JWT
    (re.compile(r'\beyJ[\w-]{5,}\.[\w-]{5,}\.[\w-]*'), '<JWT-REDACTED>'),
    # HTTP auth headers
    (re.compile(r'\b(Basic|Bearer)\s+[A-Za-z0-9+/=._~-]{8,}', re.IGNORECASE), r'\1 <REDACTED>'),
    # Credentials embedded in URLs: scheme://user:pass@host
    (re.compile(r'(\b[a-z][a-z0-9+.-]*://)[^\s/:@]+:[^\s/@]+@', re.IGNORECASE), r'\1<REDACTED>@'),
    # Cloud keys
    (re.compile(r'\bAKIA[0-9A-Z]{16}\b'), '<AWS-KEY-REDACTED>'),
    (re.compile(r'\bAIza[0-9A-Za-z\-_]{35}\b'), '<GCP-KEY-REDACTED>'),
    # Long base64 blobs (Secret data, keystores). Dotted / slashed identifiers don't match.
    (re.compile(r'(?<![\w/+=.-])[A-Za-z0-9+/]{40,}={0,2}(?![\w/+=.-])'), '<BASE64-REDACTED>'),
]

# Hostname-looking tokens that are not hostnames
_JAVA_ROOTS = {'java', 'javax', 'jdk', 'sun', 'org', 'io', 'com', 'net', 'scala', 'akka', 'reactor'}
_KEEP_HOST_SUFFIXES = (
    '.svc.cluster.local', '.svc', 'confluent.io', 'confluent.cloud', 'kubernetes.io', 'k8s.io',
    'docker.io', 'docker.com', 'github.com', 'githubusercontent.com', 'apache.org', 'oracle.com',
    'amazonaws.com', 'googleapis.com', 'azure.com', 'microsoft.com', 'gcr.io', 'quay.io', 'redhat.com',
    'cert-manager.io', 'openshift.io', 'example.com',
)
# TLDs considered for hostnames: every 2-letter ccTLD plus common generic / internal ones.
# `state.change.logger` or `ssl.keystore.location` are not hostnames.
_GENERIC_TLDS = {
    'com', 'net', 'org', 'io', 'dev', 'cloud', 'local', 'internal', 'corp', 'lan', 'intra',
    'intranet', 'edu', 'gov', 'mil', 'biz', 'info', 'app', 'ai', 'tech', 'online', 'site',
    'priv', 'private', 'home', 'test', 'cluster', 'global', 'group', 'bank', 'insurance',
}


# Last label of a file name, not a TLD: connect-distributed.properties:12 is a file and a line number
_FILE_EXTENSIONS = {
    'properties', 'java', 'scala', 'kt', 'py', 'sh', 'yaml', 'yml', 'json', 'xml', 'log', 'conf', 'cfg', 'txt', 'jar',
    'html', 'md', 'sql', 'gz', 'zip', 'tar', 'tgz', 'jks', 'pem', 'crt', 'key', 'p12', 'keytab', 'jaas', 'avsc', 'proto',
}
# a name in a URL (https://host), with a port (host:9092) or with its IP (host/10.0.0.1:2888, a java InetSocketAddress,
# the IP being already <IP-1>): a hostname whatever its TLD (.anz, .corp…)
_HOST_AFTER_RE = re.compile(r':\d{2,5}\b|/(?:<IP-|\d{1,3}\.\d)')


class DataSanitizer:
    """Sanitizes sensitive data from analysis results"""

    def __init__(self):
        self.ip_map = {}
        self.hostname_map = {}
        self.email_map = {}
        self.dn_map = {}
        self.secrets_redacted = 0
        # domains of the hostnames seen in a URL / with a port (emh-irdc.test.anz -> test.anz): another name in
        # them is a hostname too, whatever its TLD
        self.learned_suffixes = set()
        # defaultdict so new prefixes (e.g. 'ipv6') don't KeyError on first use.
        self.counter = defaultdict(lambda: 1)

        self.patterns = {
            'ipv4': re.compile(r'(?<![\w.])(?:(?:25[0-5]|2[0-4]\d|1?\d?\d)\.){3}(?:25[0-5]|2[0-4]\d|1?\d?\d)(?![\w.])'),
            'ipv6': re.compile(r'\b(?:[0-9a-fA-F]{1,4}:){7}[0-9a-fA-F]{1,4}\b'),
            'email': re.compile(r'\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b'),
            'ldap_dn': re.compile(r'\b(?:uid|cn|ou|dc|o)=[^,\s"\']+(?:,\s*(?:uid|cn|ou|dc|o|c|l|st)=[^,\s"\']+)+', re.IGNORECASE),
            'hostname': re.compile(r'(?<![\w.-])(?:[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}(?![\w-])'),
        }

    def sanitize_results(self, results: Dict[str, Any]) -> Dict[str, Any]:
        """Sanitize entire analysis results"""
        sanitized = results.copy()
        # the domains of the bundle first, so that the first texts get them too
        self.learn(json.dumps(results, default=str))

        if 'issues' in sanitized:
            sanitized['issues'] = [self.sanitize_issue(issue) for issue in sanitized['issues']]

        if 'metadata' in sanitized:
            sanitized['metadata'] = self.sanitize_dict(sanitized['metadata'])

        if sanitized.get('environment'):
            sanitized['environment'] = self.sanitize_dict(sanitized['environment'])

        if sanitized.get('timeline'):
            sanitized['timeline'] = [self.sanitize_dict(c) for c in sanitized['timeline']]

        if 'coverage' in sanitized:
            coverage = dict(sanitized['coverage'])
            coverage['unparsable_files'] = [self.sanitize_path(p) for p in coverage.get('unparsable_files', [])]
            sanitized['coverage'] = coverage

        sanitized['redaction_summary'] = self.get_redaction_summary()
        return sanitized

    def sanitize_issue(self, issue: Dict[str, Any]) -> Dict[str, Any]:
        """Sanitize a single issue"""
        sanitized = issue.copy()

        for key in ('message', 'context'):
            if key in sanitized:
                sanitized[key] = self.sanitize_text(sanitized[key])

        if 'caused_by' in sanitized:
            sanitized['caused_by'] = [self.sanitize_text(c) for c in sanitized['caused_by']]

        if sanitized.get('affected'):
            sanitized['affected'] = [self.sanitize_text(a) for a in sanitized['affected']]

        if 'file' in sanitized:
            sanitized['file'] = self.sanitize_path(sanitized['file'])

        if sanitized.get('instance'):
            sanitized['instance'] = self.sanitize_path(f"/{sanitized['instance']}/").strip('/')

        return sanitized

    def sanitize_text(self, text: str) -> str:
        """Sanitize sensitive data from text.

        Secrets are redacted first, on the full value (quoted strings included), so a
        later rule can't rewrite the key name and let the value through.
        """
        if not text:
            return text

        self.learn(text)
        sanitized = self._redact_secret_values(text)
        for pattern, repl in _SIMPLE_RULES:
            sanitized, n = pattern.subn(repl, sanitized)
            self.secrets_redacted += n

        sanitized = self._redact_with_map(sanitized, self.patterns['email'], self.email_map, 'EMAIL')
        sanitized = self._redact_with_map(sanitized, self.patterns['ldap_dn'], self.dn_map, 'LDAP-DN')
        sanitized = self._redact_ips(sanitized)
        sanitized = self._redact_with_map(sanitized, self.patterns['ipv6'], self.ip_map, 'IPV6')
        sanitized = self._redact_hostnames(sanitized)
        return sanitized

    def sanitize_path(self, path: str) -> str:
        """Sanitize file paths: hostnames / IPs / emails, plus customer-looking cluster folders"""
        if not path:
            return path

        sanitized = re.sub(r'/[a-z]+-(?:prod|production|staging|dev)[^/]*/', '/cluster-prod/', path)
        sanitized = re.sub(r'/[a-z]+-cluster[^/]*/', '/cluster/', sanitized)
        sanitized = self._redact_with_map(sanitized, self.patterns['email'], self.email_map, 'EMAIL')
        sanitized = self._redact_ips(sanitized)
        return sanitized

    def sanitize_dict(self, data: Dict[str, Any]) -> Dict[str, Any]:
        """Recursively sanitize dictionary"""
        sanitized = {}
        for key, value in data.items():
            if isinstance(value, str):
                sanitized[key] = self.sanitize_text(value)
            elif isinstance(value, dict):
                sanitized[key] = self.sanitize_dict(value)
            elif isinstance(value, list):
                sanitized[key] = [
                    self.sanitize_text(v) if isinstance(v, str)
                    else self.sanitize_dict(v) if isinstance(v, dict)
                    else v
                    for v in value
                ]
            else:
                sanitized[key] = value
        return sanitized

    def _redact_secret_values(self, text: str) -> str:
        def replacer(match):
            quote, key, sep, value = match.group(1), match.group(2), match.group(3), match.group(4)
            if _SECRET_KEY_KEEP_RE.search(key) or value.startswith('<') or value.startswith('${'):
                return match.group(0)
            # already masked by the application (password=********, [hidden])
            if re.fullmatch(r'["\']?(?:\*+|\[hidden\])["\']?', value):
                return match.group(0)
            self.secrets_redacted += 1
            return f"{quote}{key}{quote}{sep}<REDACTED>"

        return _SECRET_KV_RE.sub(replacer, text)

    def _redact_with_map(self, text: str, pattern, mapping: Dict, prefix: str) -> str:
        """Redact matches with consistent placeholders"""
        def replacer(match):
            original = match.group(0)
            if original not in mapping:
                mapping[original] = f'<{prefix}-{self.counter[prefix.lower()]}>'
                self.counter[prefix.lower()] += 1
            return mapping[original]

        return pattern.sub(replacer, text)

    def _redact_ips(self, text: str) -> str:
        """Redact IPv4 addresses, but not 4-part versions (7.6.0.1, image:7.6.0.1, v7.6.0.1)"""
        def replacer(match):
            original = match.group(0)
            before = text[max(0, match.start() - 60):match.start()]
            if re.search(r'(?:(?<![a-z])v|version[\s=:"]*|[\w.-]+/[\w.-]+:)$', before, re.IGNORECASE):
                return original
            if original not in self.ip_map:
                self.ip_map[original] = f'<IP-{self.counter["ip"]}>'
                self.counter['ip'] += 1
            return self.ip_map[original]

        return self.patterns['ipv4'].sub(replacer, text)

    def _confident_host(self, text: str, match) -> bool:
        """a name in a URL, with a port or with its IP: a hostname whatever its TLD"""
        return (text[max(0, match.start() - 3):match.start()] == '://'
                or _HOST_AFTER_RE.match(text, match.end()) is not None)

    def learn(self, text: str):
        """Domains of the hostnames of the text that are sure to be hostnames (see learned_suffixes)"""
        for match in self.patterns['hostname'].finditer(text):
            labels = match.group(0).lower().split('.')
            if (len(labels) >= 3 and labels[-1] not in _FILE_EXTENSIONS and labels[0] not in _JAVA_ROOTS
                    and not match.group(0).lower().endswith(_KEEP_HOST_SUFFIXES) and self._confident_host(text, match)):
                self.learned_suffixes.add('.'.join(labels[-2:]))

    def _redact_hostnames(self, text: str) -> str:
        """Redact hostnames while keeping Java classes / packages, Kubernetes identifiers and public domains"""
        def is_hostname(match) -> bool:
            host = match.group(0)
            labels = host.split('.')
            tld = labels[-1]
            after = text[match.end():match.end() + 1]
            if host.lower().endswith(_KEEP_HOST_SUFFIXES):
                return False
            if labels[0].lower() in _JAVA_ROOTS:
                return False  # org.apache.kafka…, io.confluent…, java.lang…
            if after in ('.', '(', '$', '='):
                return False  # dotted identifier (kafka.server.KafkaServer) or config key (basic.auth.user.info=)
            if tld.lower() in _FILE_EXTENSIONS:
                return False
            if self._confident_host(text, match):
                return True
            if any(host.lower().endswith('.' + suffix) for suffix in self.learned_suffixes):
                return True
            if any(c.isupper() for c in host):
                return False  # hostnames are lower case in practice, Java classes are not
            if not (len(tld) == 2 or tld.lower() in _GENERIC_TLDS):
                return False
            return True

        def replacer(match):
            hostname = match.group(0)
            if not is_hostname(match):
                return hostname
            if hostname not in self.hostname_map:
                self.hostname_map[hostname] = f'<HOST-{self.counter["host"]}>'
                self.counter['host'] += 1
            return self.hostname_map[hostname]

        return self.patterns['hostname'].sub(replacer, text)

    def get_redaction_summary(self) -> Dict[str, int]:
        """Get summary of what was redacted"""
        return {
            'ip_addresses': len(self.ip_map),
            'hostnames': len(self.hostname_map),
            'emails': len(self.email_map),
            'ldap_dns': len(self.dn_map),
            'secrets': self.secrets_redacted,
        }


def _load_state(sanitizer: DataSanitizer, path: str):
    try:
        with open(path, encoding="utf-8") as f:
            state = json.load(f)
    except (OSError, ValueError):
        return
    sanitizer.ip_map = state.get("ip_map", {})
    sanitizer.hostname_map = state.get("hostname_map", {})
    sanitizer.email_map = state.get("email_map", {})
    sanitizer.dn_map = state.get("dn_map", {})
    sanitizer.secrets_redacted = state.get("secrets_redacted", 0)
    sanitizer.counter.update(state.get("counter", {}))
    sanitizer.learned_suffixes = set(state.get("learned_suffixes", []))


def _save_state(sanitizer: DataSanitizer, path: str):
    with open(path, "w", encoding="utf-8") as f:
        json.dump({"ip_map": sanitizer.ip_map, "hostname_map": sanitizer.hostname_map, "email_map": sanitizer.email_map,
                   "dn_map": sanitizer.dn_map, "secrets_redacted": sanitizer.secrets_redacted,
                   "counter": dict(sanitizer.counter), "learned_suffixes": sorted(sanitizer.learned_suffixes)}, f)


def sanitize_stream(sanitizer: DataSanitizer, text: str) -> str:
    """Sanitizes text, keeping the @@PG marker lines of a records file as they are"""
    out, block = [], []
    for line in text.split("\n"):
        if line.startswith("@@PG"):
            if block:
                out.append(sanitizer.sanitize_text("\n".join(block)))
                block = []
            out.append(line)
        else:
            block.append(line)
    if block:
        out.append(sanitizer.sanitize_text("\n".join(block)))
    return "\n".join(out)


def main() -> int:
    ap = argparse.ArgumentParser(description="Redact secrets, IPs, hostnames, emails and LDAP DNs of the text on stdin")
    ap.add_argument("--state", help="JSON file with the placeholders given so far, read and updated")
    ap.add_argument("--summary", action="store_true", help="print what was redacted (JSON) instead of filtering stdin")
    ap.add_argument("--no-count", action="store_true",
                    help="do not count the secrets of this text (a digest of records sanitized again later)")
    args = ap.parse_args()
    sanitizer = DataSanitizer()
    if args.state and os.path.exists(args.state):
        _load_state(sanitizer, args.state)
    if args.summary:
        print(json.dumps(sanitizer.get_redaction_summary()))
        return 0
    secrets = sanitizer.secrets_redacted
    sys.stdout.write(sanitize_stream(sanitizer, sys.stdin.read()))
    if args.no_count:
        sanitizer.secrets_redacted = secrets
    if args.state:
        _save_state(sanitizer, args.state)
    return 0


def sanitize_for_sharing(results: Dict[str, Any]) -> Tuple[Dict[str, Any], Dict[str, int]]:
    """
    Convenience function to sanitize results for sharing
    Returns: (sanitized_results, redaction_summary)
    """
    sanitizer = DataSanitizer()
    sanitized = sanitizer.sanitize_results(results)
    summary = sanitizer.get_redaction_summary()
    return sanitized, summary


if __name__ == "__main__":
    sys.exit(main())
