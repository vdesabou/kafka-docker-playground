# cfk-analysis

Python tool behind `playground analyze logs` when the input is (or contains) a CFK support bundle: a folder with
`cluster-details.txt`, or with `cluster-resources/` and `operator/` (`--logs-only` skips it). `playground analyze
cfk-bundle` is kept as a hidden alias.

It scans a Confluent for Kubernetes (CFK) support bundle (`kubectl confluent support-bundle`, or
`playground debug cfk generate-bundle`), as a directory or a `.tar/.tar.gz/.tgz/.zip` archive, and sorts what
it finds into ~30 categories (pod failures, TLS, auth, MDS/RBAC, license, KRaft, replication, storage,
scheduling, …) with concrete remediation steps per category:

- Kubernetes events: `Warning` events (YAML/JSON and `kubectl get events` text), with their count.
- Pods: phase, waiting reasons, restarts, `OOMKilled` / non-zero last termination, init containers.
- Every `platform.confluent.io` custom resource: `status.phase` / `status.state`, ready replicas, `False`
  conditions, failed connector tasks, `block-reconcile`, stuck finalizers. Multi-document YAML and `kind: List`
  are supported.
- Environment: Kubernetes version, CFK operator version (operator image tag or CRD app-version) and the application
  / init image of every component, from `cluster-details.txt` and the CR specs. Checked against the
  [CFK support matrix](https://docs.confluent.io/operator/current/co-supported-environments.html): Kubernetes,
  Confluent Platform and Control Center versions outside the range of the CFK minor, `confluent-init-container`
  on another version than the operator, components on different CP versions (`Compatibility` category).
- Recent changes, newest first: `metadata.managedFields` of the CRs (who changed which part of the spec, e.g.
  `Update by kubectl-edit: spec.image, spec.podTemplate`) and StatefulSets (operator rollouts), pod creation and
  container terminations. Pods and StatefulSets written without `kind` (`pods/pod-<name>.yaml`) are recognized.
- Configuration (`.configuration` of `--json`, ⚙️ section of the HTML report, with a key / value filter): per Kafka,
  ZooKeeper, Schema Registry, Connect and Control Center CR, the `kafka.properties` / `zookeeper.properties` /
  `schemaregistry.properties` / `connect.properties` / `controlcenter.properties`, `jvm.config`, `log4j.properties`
  (and `plugins.json`) that CFK renders in the `<cr>-shared-config` ConfigMap (`cm/configmaps.yaml`), the
  `configOverrides` of the CR and the `KafkaConfig` / `SchemaRegistryConfig` / `DistributedConfig` /
  `ControlCenterConfig values:` dump of each pod log (effective values, defaults included; ZooKeeper logs none); per connector, the
  `spec.configs` of its `Connector` CR and the `…Config values:` dumps of the Connect logs (`SinkConnectorConfig`,
  the config class of the plugin, the clients of a task), attributed with their `[connector|task-0]` context. A
  connector created with the REST API and started before the logs begin has no config in the bundle. Sanitized
  like the rest (secrets as `<REDACTED>`, `${file:…}` references kept).
- JVM default truststore: a CR whose `configOverrides.jvm` (or `KAFKA_OPTS` / `JAVA_TOOL_OPTIONS`) sets
  `-Djavax.net.ssl.trustStore` without `-Djavax.net.ssl.trustStorePassword` (nor `trustStoreType=JKS`) is
  reported, high when its logs have `trustAnchors parameter must be non-empty`: a PKCS12 store read without its
  password has 0 trusted certificates, so the AWS SDK, HTTP connectors and JDBC drivers fail while the Kafka
  clients (their own `ssl.truststore.*`) keep working (`JVM Truststore Issues` category).
- Logs (rotated `.log.N` and `.gz` included): only records with an explicit `ERROR`/`FATAL` level (`WARN` when
  it matches a known category, or always with `--include-warnings`) and uncaught exceptions. Each record is
  classified on its `Caused by:` chain first, identical records are counted, and ERRORs matching no category
  are reported as "Other … (Unclassified)". Connector task / client ids are not part of the identity: one root
  cause failing 27 tasks is one issue, with the tasks listed in `affected` and their connectors (the
  `[connector|task-0]` context of the log record) in `connectors`. Classifications are cached on the record text with
  its digits folded, so a WARN storm of millions of records costs seconds, not minutes.
- Known CFK issues (`runbooks.py`, 📕 section on top of the text digest and of the HTML report, `.runbooks` and
  `issues[].runbooks` of `--json`): the log messages and events of the CFK triage table of Confluent support (roll
  blocked by the pre-roll checks, expired certificate, `INCONSISTENT_CLUSTER_ID`, ZooKeeper to KRaft migration,
  authorizer timeout, license secret, JAAS context, cluster shrink, PVC resize, Multi-Attach…), matched on the message
  and `Caused by:` chain of every issue (and on the INFO lines of the operator logs for the states it logs at INFO: `cluster not rollable from roll pre checks`, `Migration current status …/SubPhase… requeuing`), with what they mean and the public KB / docs links. The internal runbook
  links of Confluent support come from an optional private JSON file, in `$CFK_RUNBOOKS_PRIVATE` (mounted by
  `playground analyze logs` from `PLAYGROUND_CFK_RUNBOOKS_FILE`, default
  `reproduction-models/_miscellaneous/cfk-analysis/runbooks-internal.json`, format in the docstring of `runbooks.py`):
  they are shown with a 🔒 in the text digest, the HTML report and `--json`.
- ZooKeeper to KRaft migration (`kraft_migration.py`, `KRaft Migration` category): one finding per `KRaftMigrationJob`
  with its phase / sub-phase, how long it has been there (its Warning events, the `Migration current status <phase>/<sub-phase>:
  … requeuing` lines of the operator log), the last error, and the `next_steps` of that sub-phase (from the public
  migration docs and known issues), with `docs` links. `high` when stuck (`InputError` / 10+ Warning events, or 30
  minutes in the same sub-phase), `critical` in `FAILURE`, `low` in `DUAL-WRITE` (the expected pause before the
  finalize or rollback annotation), nothing once `COMPLETE`. Built from the operator log alone when the bundle has no
  KMJ CR. Sample: `samples/cfk-support-bundle-kraft-migration.tar.gz` (`make_kraft_migration_bundle.py`,
  `playground analyze logs --sample cfk_kraft_migration`).
- What runs vs what the CRs ask for (`Rollout Issues` category): a CR whose image version is not the one of its
  StatefulSet (the operator did not apply the CR: `block-reconcile`, operator down) or of some of its pods (roll not
  complete), with the StatefulSet roll (updated / ready replicas, current and update revisions) and the
  `block-reconcile` annotation. What a pod runs comes from its manifest, else from the CP version it logs at startup
  (`Kafka version: 7.4.1-ce`, Kafka, KRaftController, Connect and Schema Registry). `next_steps` per cause.
- ResourceQuota: the `FailedCreate … exceeded quota` events (one per pod a controller tried to create) become one
  finding per quota and controller, with requested / used / allowed for the exceeded resources, and a note when the
  controller is the CFK operator (its new pod cannot start).
- Each Warning event once: the rows of `kubectl get events` (`event.txt`) also in the YAML events (`event.yaml`) are
  dropped (`coverage.duplicate_events`), and a copy of the bundle inside the bundle (an archive extracted next to its
  content) is analyzed once (`coverage.skipped_copies`).
- Log coverage (`.coverage.log_windows`, 🕰️ panel of the HTML report): the first and last timestamp of each log, with
  the start of its pod when the bundle has its manifest; one `Bundle Coverage` finding when a log starts more than
  30 minutes after its pod started, or when the operator log starts after the last change of the CRs.
- A CR with the `platform.confluent.io/block-reconcile` condition `True` but without the annotation (the condition is
  not cleared when the annotation is removed): one low finding for all of them.
- Sample of the rollout, quota, coverage and stale condition findings: `samples/cfk-support-bundle-rollout.tar.gz`
  (`make_rollout_bundle.py`, `playground analyze logs --sample cfk_rollout`).
- Changes before the failure (`Recent Changes` category): the changes of the CRs and StatefulSet rollouts of the
  timeline in the hour before the first critical / high issue get `before_failure` (⚠️ in the 🕒 Recent changes of the
  text digest and of the HTML report), and one finding lists them. The time of an issue is the first timestamp of
  its event, or the timestamp of its log record (as written in the log).
- Connect plugins (`Plugin Issues` category): for a Connect CR with `spec.build.onDemand` plugins, installed by the
  `config-init-container` of each pod at its start, one finding when that init container fails or crash-loops, when
  its log has an install error (host not resolved / unreachable, checksum mismatch, no space left under
  `storageLimit`, plugin not on Confluent Hub), or when it took 5 minutes or more; and one finding per Connector CR
  whose `spec.class` is not among the installed plugins of its Connect (`status.connectorPlugins`).
- Several bundles (`compare.py`): `playground analyze logs -f a -f b` writes the JSON of each analysis next to its HTML
  report (`analyzer_cli.py --json-out`, with `collected`, the newest timestamp of the bundle, and `label`) and
  compares them, sorted by collection time, each one with the previous one: same cluster (CRs in common), versions,
  changes of the CRs between the two collections, issues fixed / new / still there (matched on category, component,
  instance and message, digits / timestamps / numbered placeholders folded), known CFK issues, KRaft migration phase,
  verdict. Text, `cfk-bundles-comparison-*.html`, `"comparison"` in `--json`. Samples:
  `--sample cfk_rollout --sample cfk_rollout_after` (`make_rollout_bundle.py --after`).
- Transient pod symptoms: `Unhealthy` (probe failed) and `BackOff` events of a pod that is Running with every
  container ready in the bundle, and fewer than 3 restarts, are `low` with `"transient": true` (a broker not Ready
  while it starts, Connect restarted before Kafka was up). Rows of `Normal` events in kubectl text output (a PVC
  `WaitForFirstConsumer`) and the `key = value` lines of a `…Config values:` dump are not issues.
- `False` conditions are reported only when `True` is the healthy value (`*-ready`, `*-available`…) or their
  reason says something failed: `garbage-collecting` / `config-revision-hash` `False` are normal.

Each issue is attributed to a `component` (`kafka`, `kraftcontroller`, `zookeeper`, `connect`, `schemaregistry`,
`ksqldb`, `controlcenter`, `kafkarestproxy`, `operator`, or `other` for nodes, volumes and unknown pods) and, when
known, to an `instance` (the CR name, e.g. `connect-peh`). They come from the bundle layout
(`cluster-resources/<type>/<name>/`), the CFK custom resources (a `Connector` belongs to its `connectClusterRef`),
the `platform.confluent.io/type` / `app` pod labels and, for events, the involved object. `--component connect`
keeps only the Connect issues (text, JSON and HTML); the HTML report also has Component / Instance buttons, a
Connector picker when log records have a Connect connector context, and its search filters single issues.

Sensitive values (secrets, IPs, hostnames, emails, LDAP DNs) are sanitized by default. This is best effort:
review the output before sharing it.

## Files

- `analyzer.py` — detection engine over logs / events / pods / CFK CRs, with coverage counters. Its log patterns
  come from `tools/report-common/known_causes.py` (shared with the known causes of `playground analyze logs`, mounted
  in `/tmp/report-common`): the first one that matches, in declaration order, wins; a WARN record counts only when it
  matches a known cause, not a catch-all (`hint: False`, any Kafka exception…).
- `environment.py` — `cluster-details.txt` parser, CFK support matrix checks, change timeline.
- `tools/report-common/sanitizer.py` (shared with the plain log digest of `playground analyze logs`) — redacts
  secrets first, then emails / LDAP DNs / IPs / hostnames.
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
playground analyze logs --sample cfk_bundle          # try it on the sample below
playground analyze logs -f ./customer-bundle.tar.gz
playground analyze logs -f ./bundle.tgz --output-dir ./reports      # + HTML report in ./reports
playground analyze logs -f ./bundle.tar.gz --json > report.json
playground analyze logs -f ./bundle.tar --component connect          # only the Connect issues
```

See `playground analyze logs --help` for all flags. For a raw ERROR digest of every log in the
bundle, `playground analyze logs -f <bundle> --logs-only` complements it.

## Sample

`samples/cfk-support-bundle-synthetic.tar.gz` (`--sample synthetic`) is a synthetic bundle in the
`kubectl confluent support-bundle` layout, built by `samples/make_synthetic_bundle.py` (deterministic: same
bytes on every run). It tells one story: kafka-2 crash-looping on an expired TLS certificate with a pending
PersistentVolumeClaim, connect-0 OOMKilled with a FAILED connector task, Schema Registry failing to
authenticate, and operator reconcile errors (19 issues, 4 critical). It also has a `cluster-details.txt` and a
`kubectl edit` of the Kafka CR, for the Environment and Recent changes sections, and the `<cr>-shared-config`
ConfigMaps of Kafka, Schema Registry and Connect, `configOverrides`, `Connector` CR configs and config dumps in the
logs, for the Configuration section.

```bash
python3 -I cfk-analysis/samples/make_synthetic_bundle.py cfk-analysis/samples/cfk-support-bundle-synthetic.tar.gz
```
