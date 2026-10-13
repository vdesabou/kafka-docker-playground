# cfk-analysis

Python tool that powers `playground debug cfk cfk-bundle-analyze`.

It scans a Confluent for Kubernetes (CFK) support bundle (`kubectl confluent support-bundle`, or
`playground debug cfk generate-bundle`), as a directory or a `.tar/.tar.gz/.tgz/.zip` archive, and sorts what
it finds into ~30 categories (pod failures, TLS, auth, MDS/RBAC, license, KRaft, replication, storage,
scheduling, …) with concrete remediation steps per category:

- Kubernetes events: `Warning` events (YAML/JSON and `kubectl get events` text), with their count.
- Pods: phase, waiting reasons, restarts, `OOMKilled` / non-zero last termination, init containers.
- Every `platform.confluent.io` custom resource: `status.phase` / `status.state`, ready replicas, `False`
  conditions, failed connector tasks, `block-reconcile`, stuck finalizers. Multi-document YAML and `kind: List`
  are supported.
- Logs (rotated `.log.N` and `.gz` included): only records with an explicit `ERROR`/`FATAL` level (`WARN` when
  it matches a known category, or always with `--include-warnings`) and uncaught exceptions. Each record is
  classified on its `Caused by:` chain first, identical records are counted, and ERRORs matching no category
  are reported as "Other … (Unclassified)".

Sensitive values (secrets, IPs, hostnames, emails, LDAP DNs) are sanitized by default. This is best effort:
review the output before sharing it.

## Files

- `analyzer.py` — detection engine over logs / events / pods / CFK CRs, with coverage counters.
- `sanitizer.py` — redacts secrets first, then emails / LDAP DNs / IPs / hostnames.
- `recommendations.py` — category → concrete CFK remediation steps mapping.
- `html_report.py` — self-contained offline HTML report (no CDN dependency).
- `analyzer_cli.py` — CLI entrypoint: safe extraction → analyze → sanitize → render.
- `Dockerfile` / `requirements.txt` — runtime image (`python:3.12-slim` + `PyYAML`). The playground builds it
  once (tag derived from these two files) and mounts the code at run time.

## Exit codes

`0` analysis done (whatever was found, read the summary), `64` invalid, unsafe or empty bundle, anything else
is a tool failure.

## Usage

Always go through the playground CLI:

```bash
playground debug cfk cfk-bundle-analyze --bundle ./customer-bundle.tar.gz
playground debug cfk cfk-bundle-analyze --bundle ./bundle.tgz --html
playground debug cfk cfk-bundle-analyze --bundle ./bundle.tar.gz --json > report.json
```

See `playground debug cfk cfk-bundle-analyze --help` for all flags. For a raw ERROR digest of every log in the
bundle, `playground debug analyze-logs -f <bundle>` complements it.
