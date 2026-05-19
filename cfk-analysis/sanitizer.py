"""
Data Sanitizer for CFK Bundle Analyzer
Redacts sensitive information from analysis results
"""

import re
from collections import defaultdict
from typing import Dict, Any, List


class DataSanitizer:
    """Sanitizes sensitive data from analysis results"""

    def __init__(self):
        self.ip_map = {}
        self.hostname_map = {}
        self.email_map = {}
        # defaultdict so new prefixes (e.g. 'ipv6') don't KeyError on first use.
        self.counter = defaultdict(lambda: 1)

        # Patterns for sensitive data
        self.patterns = {
            'ipv4': r'\b(?:[0-9]{1,3}\.){3}[0-9]{1,3}\b',
            'ipv6': r'\b(?:[0-9a-fA-F]{1,4}:){7}[0-9a-fA-F]{1,4}\b',
            'email': r'\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,}\b',
            'hostname': r'\b(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,}\b',
            'aws_key': r'AKIA[0-9A-Z]{16}',
            'gcp_key': r'AIza[0-9A-Za-z\-_]{35}',
            'token': r'[a-zA-Z0-9_-]{20,}',  # Generic long tokens
            'password_field': r'(password|passwd|pwd)\s*[:=]\s*[^\s]+',
            'api_key': r'(api[_-]?key|apikey)\s*[:=]\s*[^\s]+',
        }

    def sanitize_results(self, results: Dict[str, Any]) -> Dict[str, Any]:
        """Sanitize entire analysis results"""
        sanitized = results.copy()

        # Sanitize issues
        if 'issues' in sanitized:
            sanitized['issues'] = [self.sanitize_issue(issue) for issue in sanitized['issues']]

        # Sanitize metadata if present
        if 'metadata' in sanitized:
            sanitized['metadata'] = self.sanitize_dict(sanitized['metadata'])

        return sanitized

    def sanitize_issue(self, issue: Dict[str, Any]) -> Dict[str, Any]:
        """Sanitize a single issue"""
        sanitized = issue.copy()

        # Sanitize text fields
        if 'message' in sanitized:
            sanitized['message'] = self.sanitize_text(sanitized['message'])

        if 'file' in sanitized:
            sanitized['file'] = self.sanitize_path(sanitized['file'])

        if 'context' in sanitized:
            sanitized['context'] = self.sanitize_text(sanitized['context'])

        return sanitized

    def sanitize_text(self, text: str) -> str:
        """Sanitize sensitive data from text"""
        if not text:
            return text

        sanitized = text

        # Redact IPv4 addresses
        sanitized = self._redact_with_map(
            sanitized,
            self.patterns['ipv4'],
            self.ip_map,
            'IP'
        )

        # Redact IPv6 addresses
        sanitized = self._redact_with_map(
            sanitized,
            self.patterns['ipv6'],
            self.ip_map,
            'IPV6'
        )

        # Redact emails
        sanitized = self._redact_with_map(
            sanitized,
            self.patterns['email'],
            self.email_map,
            'EMAIL'
        )

        # Redact hostnames (careful not to redact common service names)
        sanitized = self._redact_hostnames(sanitized)

        # Redact cloud provider keys
        sanitized = re.sub(self.patterns['aws_key'], '<AWS-KEY-REDACTED>', sanitized)
        sanitized = re.sub(self.patterns['gcp_key'], '<GCP-KEY-REDACTED>', sanitized)

        # Redact password fields
        sanitized = re.sub(
            self.patterns['password_field'],
            r'\1=<REDACTED>',
            sanitized,
            flags=re.IGNORECASE
        )

        # Redact API key fields
        sanitized = re.sub(
            self.patterns['api_key'],
            r'\1=<REDACTED>',
            sanitized,
            flags=re.IGNORECASE
        )

        return sanitized

    def sanitize_path(self, path: str) -> str:
        """Sanitize file paths to remove customer identifiers"""
        if not path:
            return path

        # Replace customer-specific directory names with generic ones
        # Common patterns: /customer-name/, /prod-cluster/, etc.
        sanitized = re.sub(r'/[a-z]+-(?:prod|production|staging|dev)[^/]*/', '/cluster-prod/', path)
        sanitized = re.sub(r'/[a-z]+-cluster[^/]*/', '/cluster/', sanitized)

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

    def _redact_with_map(self, text: str, pattern: str, mapping: Dict, prefix: str) -> str:
        """Redact matches with consistent placeholders"""
        def replacer(match):
            original = match.group(0)
            if original not in mapping:
                mapping[original] = f'<{prefix}-{self.counter[prefix.lower()]}>'
                self.counter[prefix.lower()] += 1
            return mapping[original]

        return re.sub(pattern, replacer, text)

    def _redact_hostnames(self, text: str) -> str:
        """Redact hostnames while preserving common service names"""
        # Don't redact common Kubernetes/Confluent service names
        exclude_patterns = [
            r'\.svc\.cluster\.local$',
            r'^kafka$',
            r'^zookeeper$',
            r'^connect$',
            r'^schemaregistry$',
            r'^ksqldb$',
            r'^controlcenter$',
            r'confluent\.cloud$',
            r'amazonaws\.com$',
            r'gcp\.com$',
            r'azure\.com$',
        ]

        def should_exclude(hostname: str) -> bool:
            for pattern in exclude_patterns:
                if re.search(pattern, hostname, re.IGNORECASE):
                    return True
            return False

        def replacer(match):
            hostname = match.group(0)
            if should_exclude(hostname):
                return hostname
            if hostname not in self.hostname_map:
                self.hostname_map[hostname] = f'<HOST-{self.counter["host"]}>'
                self.counter['host'] += 1
            return self.hostname_map[hostname]

        return re.sub(self.patterns['hostname'], replacer, text)

    def get_redaction_summary(self) -> Dict[str, int]:
        """Get summary of what was redacted"""
        return {
            'ip_addresses': len(self.ip_map),
            'hostnames': len(self.hostname_map),
            'emails': len(self.email_map),
        }


def sanitize_for_sharing(results: Dict[str, Any]) -> tuple[Dict[str, Any], Dict[str, int]]:
    """
    Convenience function to sanitize results for sharing
    Returns: (sanitized_results, redaction_summary)
    """
    sanitizer = DataSanitizer()
    sanitized = sanitizer.sanitize_results(results)
    summary = sanitizer.get_redaction_summary()
    return sanitized, summary
