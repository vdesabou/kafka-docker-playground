# cfk-analysis

Python tool that powers `playground debug cfk-bundle-analyze`.

It scans a Confluent for Kubernetes (CFK) support bundle — a directory or
`.tar/.tar.gz/.tgz/.zip` archive — for ~30 issue categories (pod failures,
TLS, auth, MDS/RBAC, license, KRaft, replication, storage, scheduling, …)
and prints concrete remediation steps per category. Sensitive values
(IPs, hostnames, emails, credentials) are sanitized by default.

## Files

- `analyzer.py` — pattern-matching engine over logs / events / YAML CRs / describes.
- `sanitizer.py` — redacts IPs / hostnames / emails / API keys / secrets.
- `recommendations.py` — category → concrete CFK remediation steps mapping.
- `html_report.py` — self-contained offline HTML report (no CDN dependency).
- `analyzer_cli.py` — CLI entrypoint: extract → analyze → sanitize → render.
- `requirements.txt` — `Flask` is only needed for the optional standalone web UI
  shipped outside the playground; the CLI uses only `PyYAML` from this list.

## Usage

Always go through the playground CLI:

```bash
playground debug cfk-bundle-analyze --bundle ./customer-bundle.tar.gz
playground debug cfk-bundle-analyze --bundle ./bundle.tgz --html
playground debug cfk-bundle-analyze --bundle ./bundle.tar.gz --json > report.json
```

See `playground debug cfk-bundle-analyze --help` for all flags.
