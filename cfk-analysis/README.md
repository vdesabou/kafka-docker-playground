# cfk-analysis

Python tool that powers `playground analyze cfk-bundle`.

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
playground analyze cfk-bundle --sample synthetic          # try it on the sample below
playground analyze cfk-bundle --bundle ./customer-bundle.tar.gz
playground analyze cfk-bundle --bundle ./bundle.tgz --output-dir ./reports      # + HTML report in ./reports
playground analyze cfk-bundle --bundle ./bundle.tar.gz --json > report.json
```

See `playground analyze cfk-bundle --help` for all flags. For a raw ERROR digest of every log in the
bundle, `playground analyze logs -f <bundle>` complements it.

## Sample

`samples/cfk-support-bundle-synthetic.tar.gz` (`--sample synthetic`) is a synthetic bundle in the
`kubectl confluent support-bundle` layout, built by `samples/make_synthetic_bundle.py` (deterministic: same
bytes on every run). It tells one story: kafka-2 crash-looping on an expired TLS certificate with a pending
PersistentVolumeClaim, connect-0 OOMKilled with a FAILED connector task, Schema Registry failing to
authenticate, and operator reconcile errors (19 issues, 4 critical).

```bash
python3 -I cfk-analysis/samples/make_synthetic_bundle.py cfk-analysis/samples/cfk-support-bundle-synthetic.tar.gz
```
