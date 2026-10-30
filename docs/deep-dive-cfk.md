# 🍪 Deep dive: Confluent for Kubernetes (`--environment cfk`)

The same connector example runs on Docker Compose or on Kubernetes, managed by Confluent for Kubernetes (CFK), by
changing one flag. The playground starts a local Kubernetes cluster ([k3d](https://k3d.io)), installs the CFK operator,
deploys Kafka, Connect and Schema Registry as CFK custom resources, translates the example's compose override into
Kubernetes, and the `playground` commands then talk to pods instead of containers. This is how you reproduce "it works
with Docker, not in our CFK cluster", check what a `Connector` resource does, or produce a CFK support bundle and
read it. Takes about 15 minutes to read, and about 10 minutes to run the lab.

> [!TIP]
> 🎬 The video session [☸️ What is wrong in this CFK cluster?](/sessions?id=☸️-what-is-wrong-in-this-cfk-cluster)
> shows `playground analyze logs` on a customer support bundle, in 5 minutes. This page goes further: how the
> environment is built, what every command does differently on Kubernetes, what is not supported, a hands-on lab and
> recipes for support repros.

| You want | Command |
| --- | --- |
| a connector example on CFK | `playground run -f <connect/ example> --environment cfk` |
| the same with RBAC (MDS, LDAP, `ConfluentRolebinding`) | `--environment cfk-rbac` |
| an environment without an example | `playground start-environment --environment cfk` |
| what is running | `playground status` (`kubectl -n confluent get pods`) |
| the `Connector` resource the CLI would apply | `playground connector create-or-update -c <name> --dry-run << EOF … EOF` |
| the status of a connector, CFK side and Connect side | `playground connector status -c <name>` |
| a support bundle of the namespace | `playground debug cfk generate-bundle` |
| the operator code that logs an error, at the version of a bundle (Confluent only) | `playground debug cfk sourcecode --bundle <bundle> --grep "<message>"` |
| what is wrong in a support bundle (yours or the customer's) | `playground analyze logs -f <dir\|.tar.gz\|.zip>` |
| is this example red on CFK in CI? | `playground get-ci-result --test <dir> --environment cfk --logs` |

---

## 1. Mental model (the 3 things to remember)

1. **One k3d cluster, one CFK operator, CRs in namespace `confluent`.** `environment/cfk/start.sh` creates (or reuses)
   the k3d cluster `playground-cfk`: one k3s server running in a Docker container, 24 GB of memory by default
   (`K3D_MEMORY`). It installs the operator with Helm (`helm upgrade --install confluent-operator
   confluentinc/confluent-for-kubernetes`, `CFK_VERSION`, default `3.3.0`, mapped to its chart version), then applies
   the CRs of [`environment/cfk/confluent-platform.yaml`](https://github.com/vdesabou/kafka-docker-playground/blob/master/environment/cfk/confluent-platform.yaml):
   `KRaftController`, `Kafka`, `Connect`, `SchemaRegistry` (and `ControlCenter` with `--enable-control-center`).
   KRaft only, one replica each, the CP images of `--tag` (the broker is always `cp-server`). The images are pulled
   (and the connect one patched with the playground tools) in your Docker daemon, then copied into the node with
   `k3d image import`: the cluster doesn't pull them itself. The cluster and the operator are **kept between runs**:
   the next run empties the namespace (CRs, pods, PVCs) but keeps the operator (`♻️ Reusing Confluent for Kubernetes
   CFK version 3.3.0 …`), so it starts in a few minutes instead of reinstalling everything.

2. **The example's compose override becomes Kubernetes.** An example doesn't change to run on CFK: it starts
   `--environment "${PLAYGROUND_ENVIRONMENT}"` with its `docker-compose.plaintext.yml`, and `start.sh` translates it,
   then merges everything into the manifest before the first apply (connect-0 starts once, with its final spec):

   | In the compose override | On CFK |
   | --- | --- |
   | `CONNECT_PLUGIN_PATH` of `connect` (`/usr/share/confluent-hub-components/<owner>-<name>`) | `spec.build.type: onDemand` of the `Connect` CR: the plugin is installed from Confluent Hub at the version of `--connector-tag` (latest otherwise); a local plugin or `--connector-zip` is served by an HTTP server on your machine (port `18080`) and installed from that URL |
   | the `environment` of `connect` | `spec.podTemplate.envVars` of the `Connect` CR |
   | files mounted in `connect` | Kubernetes Secrets mounted in connect-0 (a file too large for a Secret is baked into the image instead) |
   | every other service (a database, a mock server…) | a Pod named after the service, and a Service when it declares ports: the example reaches it by the same name |

   The worker configuration is in `configOverrides.server` of the `Connect` CR: converters (`StringConverter` key,
   `AvroConverter` value), `plugin.path`, replication factors 1, bootstrap `kafka:9071`, Schema Registry
   `http://schemaregistry:8081`.

3. **The CLI maps names and switches transport, from `run.environment`.** Nothing to pass on the command line:
   - container names become pod names: `connect` → `connect-0`, `broker` / `kafka` → `kafka-0`, `schema-registry`
     → `schemaregistry-0`, `control-center` → `controlcenter-0` (a pod name works too);
   - `docker exec` becomes `kubectl -n confluent exec`: `topic produce` / `topic consume` and the `kafka-*` tools run
     in connect-0 against `kafka:9071`, with Schema Registry at `http://schemaregistry:8081`;
   - the REST calls from your machine go through `kubectl port-forward`: Connect on `localhost:8083`, Schema Registry
     on `localhost:8081` (and `9021`, `8088`, `8082` for Control Center, ksqlDB, REST Proxy). A CLI call that finds
     the Connect port-forward dead starts a new one (`🔀 Starting CFK port-forward for Connect on localhost:8083`);
   - connectors are `Connector` resources (create, update, delete, and pause / resume / restart with annotations), and
     `topic create` / `topic delete` act on `KafkaTopic` resources.

---

## 2. What each command does on CFK

| Command | On CFK |
| --- | --- |
| `connector create-or-update` | builds a `Connector` CR (`spec.class`, `spec.taskMax`, `spec.configs`, `connectClusterRef: connect`) and `kubectl apply`s it, then waits for the CR to be ready and (default, or `--wait`) for the tasks to be RUNNING. `--dry-run` prints the CR. Locally, the CR is printed on every apply (`📄 Generated Connector CRD manifest used for apply:`) |
| `connector status` | `kubectl get connector` (state, connector status, tasks ready, `app-ready` condition) **and** the usual status from the Connect REST API |
| `connector show-config` | `spec.configs` of the CR (`using CFK Connector CR`) |
| `connector update` | opens the CR in your editor (interactive), then `kubectl apply` |
| `connector pause` / `resume` / `restart` | `kubectl annotate connector <c> platform.confluent.io/pause-connector=true` / `resume-connector=true` / `restart-connector=true` (`restart-task=<id>` with `--task-id`) |
| `connector delete` | `kubectl delete connector` |
| `connector stop` | the Connect REST API (CFK has no annotation for it) |
| `connector wait` | the Connect REST API through the port-forward, started again on each failed try (the pod was restarted) |
| `connector plugins` | `status.connectorPlugins` of the `Connect` CR |
| `topic create` / `delete` / `describe` | a `KafkaTopic` CR (`replicas: 1`, `partitionCount`) / `kubectl delete kafkatopic` / `kubectl describe kafkatopic` + `kafka-topics --describe` |
| `topic produce` / `consume`, `get-number-records`, `consumer-group`, `show-lag` | the console tools in connect-0, `kafka:9071` |
| `container exec` / `logs` / `cp` / `get-properties` / `get-ip-addresses` | `kubectl exec` / `kubectl logs --all-containers` (`--previous` for the instance before a restart) / `kubectl cp` / … on the pod |
| `container restart` / `kill` | delete the pod (`kill` with `--grace-period=0 --force`): the StatefulSet creates a new one |
| `container kill-all` | deletes every pod of the namespace except the operator, and kills the port-forwards |
| `container exec --root` | patches the CR to run as root (`runAsUser: 0`), runs the command, restores the CR: two pod restarts |
| `container set-environment-variables` | patches `spec.podTemplate.envVars` of the CR (the previous value is kept in `playground.ini`, `--restore-original-values` puts it back): a pod restart |
| `container change-jdk`, `debug jscissors --restart` | build a new Connect image, import it into k3d and patch the CR (connect only) |
| `debug thread-dump --jstack`, `debug heap-dump` | attach a debug container with a JDK to the pod (the CP images have a JRE only): no restart |
| `debug flight-recorder` | `jcmd` in the pod (no JMX port to record over) |
| `debug tcp-dump`, `block-traffic`, `degrade-traffic` | an ephemeral `nicolaka/netshoot` container in the pod (`kubectl debug`) |
| `debug cfk generate-bundle` | `kubectl confluent support-bundle --namespace confluent` (cfk environments only) |
| `debug cfk sourcecode` | clones the private `confluentinc/confluent-operator` at the tag of a CFK version or bundle (no environment needed) |
| `stop` | runs `environment/cfk/stop.sh` and kills the port-forwards: **the k3d cluster keeps running** |

Not supported, or different:

| Command or flag | On CFK |
| --- | --- |
| `connector benchmark`, `run --benchmark` | `❌ benchmark is not available with the cfk environment yet` (`--benchmark` is ignored with a warning) |
| `container recreate` | `❌ container recreate is not supported in cfk mode`: use `restart` (the pod is recreated from the CR) |
| `container pause` | refused: there is no `docker pause` for a pod |
| `connector create-or-update --initial-state` | `❌ --initial-state is not supported with CFK Connector CRD` |
| `connector create-or-update --wait-for-zero-lag` | ignored, with `⏭️ --wait-for-zero-lag is not supported with CFK Connector CRD path` |
| `connector validate`, `create-or-update --validate` | basic checks only (`connector.class` present), no `config/validate` call |
| `connector diff --defaults` | refused (no validation endpoint to read the defaults from) |
| `topic produce --validate` | needs a local connect container: refused |
| `--enable-jmx-grafana`, `--enable-kcat`, `--enable-conduktor`, `--enable-flink` | `⚠️ … is not implemented in environment/cfk/start.sh` |
| `ENABLE_ZOOKEEPER` | ignored: the CFK deployment is KRaft only |
| `--enable-ksqldb`, `--enable-rest-proxy` | plain Deployments on `cfk`, `KsqlDB` / `KafkaRestProxy` CRs on `cfk-rbac` |
| `--enable-multiple-brokers`, `--enable-multiple-connect-workers` | `replicas: 3` on the `Kafka` / `Connect` CR (pods `connect-0`, `connect-1`, `connect-2`) |

Gotchas:

- **The connector name is a Kubernetes resource name**: lower case letters, digits, `-` and `.` only. `MySink` or
  `my_sink` are refused before anything is applied. A customer's connector name with capitals can't be reproduced as
  is: rename it.
- **The `Connector` CR is not the connector status**: `app-ready: True` means the CR was applied, not that the tasks
  run. Its `tasksReady` and `failedTasks` are refreshed at the next reconcile of the operator, so they lag behind the
  Connect REST API: `0/1` tasks ready while the task is RUNNING, a FAILED task with `app-ready: True` and no
  `failedTasks` for about 15 seconds (see the lab). `connector status` prints both: read the second table.
  `create-or-update` and `connector wait` use the REST API for that reason.
- **`create-or-update` rewrites two hosts in every string value of the config**: `broker:9092` → `kafka:9071` and
  `schema-registry` → `schemaregistry`. That's what lets the examples' configs work unchanged, but it applies to any
  value: a topic or a file name containing `schema-registry` is renamed too. `--dry-run` shows the result.
- **Nothing is added for security on `cfk`**: the cluster is plaintext, `add_connector_config_based_on_environment`
  does nothing. On `cfk-rbac`, the config gets the same keys as on `rbac-sasl-plain` (`principal.service.name` /
  `principal.service.password` = `connectorSA`, the JAAS of `confluent.topic.*`…), and the CR gets
  `connectRest.authentication.type: bearer` with the secret `connector-submitter`.
- **A pod restart loses what was written in the pod**: files copied with `container cp`, `/tmp/output.json` of a
  FileStream sink, packages installed with `exec --root`. Only the CR survives. `exec --root`,
  `set-environment-variables` and `change-jdk` themselves restart the pod: apply them first.
- **The port-forwards are processes on your machine**, logged in `/tmp/connect-port-forward.log`,
  `/tmp/schema-registry-port-forward.log` (started by `start.sh`) and `/tmp/playground-cfk-connect-port-forward.log`
  (restarted by the CLI). When connect-0 is deleted, the Connect one dies with it: the next `playground connector …`
  call starts a new one, and `connector wait` keeps starting one until the new pod answers. A `curl localhost:8083`
  of your own in between fails.
- **`topic create` only sets the partitions**: the `KafkaTopic` CR has `replicas: 1` and `partitionCount`, the extra
  `kafka-topics` arguments (`--config retention.ms=…`) are not applied. `topic produce` creates a missing topic the
  same way (`kafkatopic.platform.confluent.io/filestream created`), but a topic created by a connector or a client
  (`auto.create.topics.enable=true` in the `Kafka` CR) has no `KafkaTopic` resource: `kubectl describe kafkatopic`
  doesn't find it, `kafka-topics --describe` does, and `topic delete` (`kubectl delete kafkatopic`) can't delete it.
- **`playground stop` leaves the cluster up** (and its memory reserved): `k3d cluster stop playground-cfk` to pause
  it, `k3d cluster delete playground-cfk` to start from scratch (the next run creates it again and reinstalls the
  operator).

---

## 3. Variables of the environment

| Variable | Default | What it changes |
| --- | --- | --- |
| `CFK_VERSION` | `3.3.0` | the CFK operator (Helm chart) and the init container image; versions 2.9.5 to 3.3.0 are mapped in `start.sh` |
| `K3D_MEMORY` | `24g` | memory of the k3d server node, at creation only |
| `K3D_CLUSTER_NAME` | `playground-cfk` | the k3d cluster |
| `CFK_NAMESPACE_RESET_MODE` | `keep-operator` | how the namespace is emptied before a run: `namespace` force-deletes the namespace, operator included (also the fallback when the namespace can't be emptied in 90 seconds) |
| `CFK_CONNECTOR_ARCHIVE_HOST` | detected | the host the cluster uses to download a local plugin archive (`host.docker.internal` on macOS, the gateway of the k3d network on Linux) |
| `CP_*_IMAGE` / `CP_*_TAG` | from `--tag` | the images of the CRs, as with Docker |

---

## 4. `cfk-rbac`

`environment/cfk-rbac/start.sh` is the same `start.sh` with `CFK_ENVIRONMENT=cfk-rbac`: `authorization.type: rbac`
on the CRs, MDS with an LDAP provider (an `openldap-0` pod), a `KafkaRestClass`, bearer secrets for the components and
the default role bindings as `ConfluentRolebinding` resources
([`role-bindings.yaml`](https://github.com/vdesabou/kafka-docker-playground/blob/master/environment/cfk-rbac/role-bindings.yaml)).
No TLS, SASL/PLAIN against LDAP. The users are those of `rbac-sasl-plain` (`superUser`, `connectorSubmitter`,
`connectorSA`, `clientAvroCli`…), so the commands behave the same on both:

- `playground connector …` uses `connectorSubmitter` on the Connect REST API, connectors run as `connectorSA`;
- `topic produce` / `consume` and the `kafka-*` tools authenticate as `admin` with
  `/mnt/secrets/playground-client/client.properties` in connect-0, and `clientAvroCli` on Schema Registry;
- `playground rbac role-binding …` calls MDS through a port-forward on `localhost:8091` (the same port as
  `rbac-sasl-plain`). Those role bindings are not Kubernetes resources: the ones of `role-bindings.yaml` are
  (`kubectl -n confluent get confluentrolebinding`).

See [`environment/cfk-rbac/README.md`](https://github.com/vdesabou/kafka-docker-playground/blob/master/environment/cfk-rbac/README.md)
for the listeners, users and cluster ids, and the [secured environments deep dive](/deep-dive-secured-environments.md)
for the RBAC commands.

---

## 5. Support bundles: generate, then analyze

```bash
playground debug cfk generate-bundle [--follow-logs-duration 60]
playground analyze logs -f /tmp/cfk-support-bundle/<bundle>.tar.gz --output-dir /tmp/cfk-reports
```

- `generate-bundle` runs `kubectl confluent support-bundle --namespace confluent` in `/tmp/cfk-support-bundle`. The
  first time, it installs the `kubectl confluent` plugin: it downloads the CFK bundle of `CFK_VERSION` from
  `packages.confluent.io` and extracts the plugin of your OS and architecture into `/usr/local/bin` (with `sudo` if
  needed, `~/.local/bin` as a last resort). It only works on a running `cfk` / `cfk-rbac` environment.
- `analyze logs` detects a CFK support bundle (a folder with `cluster-details.txt`, or with `cluster-resources/` and
  `operator/`, alone or inside a folder or an archive: `--logs-only` to get the plain log digest instead) and works offline on any bundle made by `kubectl confluent support-bundle`: a customer's one, or
  yours. It prints the environment (Kubernetes and CFK versions, images, checked against the support matrix), the
  recent changes, and the issues by category (pod failures, resources, TLS, auth, connect…) with the next steps. Its
  HTML report also shows the **configuration** of Kafka, ZooKeeper, Schema Registry, Connect and Control Center: the
  properties CFK renders (`kafka.properties`, `connect.properties`… of the `<cr>-shared-config` ConfigMaps,
  `configOverrides`, `jvm.config`, `log4j.properties`, the effective config logged at startup) and the config of each
  connector (`Connector` CRs, `…ConnectorConfig values:` dumps of the Connect logs), with a key / value filter.
  **📕 Known CFK issues**: the log messages and events of the CFK triage table of Confluent support (roll blocked by
  the pre-roll checks, expired certificate, `INCONSISTENT_CLUSTER_ID`, ZooKeeper to KRaft migration, authorizer that
  doesn't start, license secret, `Could not obtain JAAS context`…) are matched on every issue, and on the INFO lines of
  the operator logs for the states it logs at INFO (`cluster not rollable from roll pre checks`, `Migration current
  status …/SubPhase… requeuing`), and listed first, with
  what they mean and the public KB / docs to read ([`cfk-analysis/runbooks.py`](https://github.com/vdesabou/kafka-docker-playground/blob/master/cfk-analysis/runbooks.py)).
  Confluent support adds the internal runbook of each one with a private file, `PLAYGROUND_CFK_RUNBOOKS_FILE`
  (default `reproduction-models/_miscellaneous/cfk-analysis/runbooks-internal.json`): those links are printed in the
  terminal, the HTML report and `--json`, with a 🔒. Probe failures and back-offs of a pod that is Running and Ready
  in the bundle, with fewer than 3 restarts, are `low` and marked `transient` (a pod not Ready while Kafka starts),
  and neither the `Normal` events of kubectl output nor the lines of a `…Config values:` dump are issues.
  **🚚 ZooKeeper to KRaft migration**: each `KRaftMigrationJob` gets one finding (`KRaft Migration` category) with its
  phase / sub-phase, how long it has been there (its Warning events and the `Migration current status … requeuing`
  lines of the operator log), its last error and the next steps of that sub-phase (Kafka roll not complete,
  KRaftController not Ready, ZooKeeper authentication, znodes to remove for a rollback…), from the operator log alone
  when the bundle has no `KRaftMigrationJob` CR. `high` when stuck (`InputError` events, or 30 minutes in the same
  sub-phase), `low` in `DUAL-WRITE`, the expected pause before the finalize or rollback annotation.
  **🔄 What runs vs what the CRs ask for**: a CR whose image version is not the one of its StatefulSet (the operator
  did not apply it: `block-reconcile`, operator down) or of some of its pods (from their manifest, else from the
  `Kafka version: …-ce` they log at startup) is one finding, with the roll of the StatefulSet and the next steps. The
  `exceeded quota` events become one finding per ResourceQuota and controller (requested / used / allowed), each Warning
  event is counted once when the bundle has both `event.txt` and `event.yaml`, and a copy of the bundle inside the
  bundle is analyzed once. **🕰️ Log coverage**: the time range of each log (HTML panel, `.coverage.log_windows`), and
  one `Bundle Coverage` finding when a log starts long after its pod started or after the last change of the CRs
  (the bundle keeps the end of each log: ask for `kubectl logs --since=…`). CRs that keep the "Reconcile is blocked."
  condition after the `block-reconcile` annotation was removed are one low finding: the condition is not cleared.
  **🕒 Changes before the failure**: the changes of the CRs and StatefulSet rollouts in the hour before the first
  critical / high issue are marked ⚠️ in the Recent changes and listed in one finding. **🧩 Connect plugins**: a Connect
  whose `spec.build.onDemand` plugins cannot be installed (its `config-init-container` fails, an install error in its
  log, or an init of 5 minutes or more, typical of an air-gapped cluster) is one finding with the next steps, and so
  is a Connector CR whose class is not among the installed plugins of its Connect (`status.connectorPlugins`).
  **🔁 Several bundles** (`-f before.tar.gz -f after.tar.gz`): after the analysis of each one, they are compared, sorted
  by collection time (their newest timestamp), each one with the previous one: same cluster or not (CRs in common),
  versions, changes of the CRs between the two collections, issues fixed / new / still there (with their
  occurrences), known CFK issues, KRaft migration phase, and a verdict (`better`, `worse`, `changed`, `no change`,
  `different clusters`), in the terminal, a `cfk-bundles-comparison-*.html` report and `"comparison"` in `--json`.
  `--sample cfk_rollout --sample cfk_rollout_after` shows one. It
  sanitizes secrets, IPs and hostnames by default (best effort), and writes an HTML report in `--output-dir` (default
  `./log-analysis-output`: pass a `/tmp` folder), with Component / Instance / Connector filters. The location of each
  issue (`confluent/connect/logs/connect-0.log:33`, `pods.yaml`) opens the file at that line (the `name:` of the pod or
  CR for a YAML file) in a page written in `<report>-files/` next to the report, and its ✏️ opens it in the editor of
  `playground config editor`: the file of the bundle folder, or a copy next to the page for an archive. `--component connect`,
  `--severity high`, `--json` (`"type": "cfk-bundle"`); `--sample cfk_bundle` to see a report without a bundle (`--sample cfk_kraft_migration` for a stuck migration, `--sample cfk_rollout` for a half-done upgrade).
  `analyze cfk-bundle --bundle <bundle>` still works, as a hidden alias.
- `debug cfk sourcecode` (Confluent only: the source of the operator is the private repository
  `confluentinc/confluent-operator`, `gh auth login` and VPN) answers "which code logs this error?" at the exact
  version of the cluster. The helm chart version of CFK (`0.1718.10` for CFK 3.3.0) is also the image tag of the
  operator and the git tag `v0.1718.10`: `--cfk-version 3.3.0`, `--operator-tag 0.1718.10` or `--bundle <bundle>` (read
  from its `cluster-details.txt` or operator Deployment) pick it, the tag is cloned once (shallow) in
  `/tmp/cfk-operator-sourcecode/` and the folder is the last line printed. `--grep "<message>"` gives each match with its
  GitHub link; a message built from a template (`fmt.Errorf("missing inter %s credentials …")`) is found from its
  longest literal part. `--compare-with 3.3.0` says whether the message is still there in another version and which of
  its files changed; `--only-show-url` only prints the links.

---

## 6. Hands-on lab (≈10 min)

The lab is the script [`other/deep-dive-labs/cfk.sh`](https://github.com/vdesabou/kafka-docker-playground/blob/master/other/deep-dive-labs/cfk.sh):
CI runs it every night in the cfk job and checks the outputs below. It needs `kubectl`, `k3d`, `helm` and about 24 GB
of memory for Docker. In CI, the environment took about 5 minutes to start (k3d cluster created, images imported,
operator installed), the whole lab about 8 minutes.

**Step 1: the FileStream sink on Kubernetes**

```bash
playground start-environment --environment cfk --docker-compose-override-file "$PWD/connect/connect-filestream-sink/docker-compose.plaintext.yml"
# (the lab uses other/deep-dive-labs/docker-compose.plaintext.yml, the same one-line override: the FileStream plugin path)
# 🚀 Creating k3d cluster playground-cfk with memory 24g (configure with K3D_MEMORY env var)
# 🕸️ Install Confluent for Kubernetes version 3.3.0 (helm chart version 0.1718.10), you can change it by setting CFK_VERSION environment variable
# kraftcontroller.platform.confluent.io/kraftcontroller created
# kafka.platform.confluent.io/kafka created
# connect.platform.confluent.io/connect created
# schemaregistry.platform.confluent.io/schemaregistry created
# 🚦 CFK pod connect-0 is ready! (took 117 seconds)
# 🗂️ Schema Registry is reachable at http://127.0.0.1:8081
# 🔌 Connect REST API is reachable at http://127.0.0.1:8083
playground status
# NAME                                 READY   STATUS    RESTARTS      AGE
# confluent-operator-f66c6465d-lh8hg   1/1     Running   0             2m5s
# connect-0                            1/1     Running   2 (85s ago)   2m2s     <- restarted while Kafka was starting
# kafka-0                              1/1     Running   0             76s
# kraftcontroller-0                    1/1     Running   0             2m2s
# schemaregistry-0                     0/1     Running   0             31s
playground topic produce -t filestream --nb-messages 5 --value '{"id": %g, "name": "name-%g"}'
# 🆕 Creating topic filestream
# kafkatopic.platform.confluent.io/filestream created                           <- a KafkaTopic resource
playground connector create-or-update --connector filestream-sink --wait << EOF
{
     "tasks.max": "1",
     "connector.class": "org.apache.kafka.connect.file.FileStreamSinkConnector",
     "topics": "filestream",
     "file": "/tmp/output.json",
     "key.converter": "org.apache.kafka.connect.storage.StringConverter",
     "value.converter": "org.apache.kafka.connect.json.JsonConverter",
     "value.converter.schemas.enable": "false"
}
EOF
# connector.platform.confluent.io/filestream-sink created
# Waiting for CFK connector filestream-sink to reconcile
# CFK connector filestream-sink is ready
# ✅ 🌎onprem connector filestream-sink is RUNNING (1 task(s)) after 5 seconds
playground connector status -c filestream-sink
# ☸️ kubectl -n confluent get connector filestream-sink
# NAME              STATUS    CONNECTORSTATUS   TASKS-READY   AGE
# filestream-sink   CREATED                     0/1           10s
# ☸️ CFK status details
#    state: CREATED
#    tasksReady: 0/1
#    app-ready: True
#    reason: Created
#    message: Application is created
# 🧩 Displaying status for 🌎onprem connector filestream-sink
# filestream-sink                ✅ RUNNING  0:🟢 RUNNING      -
playground container exec -c connect --command "cat /tmp/output.json"
# 🪄 Executing command in pod connect-0 with bash
# {name=name-1, id=1}
# … {name=name-5, id=5}
```

The CR and the Connect REST API don't agree for a few seconds: the CR still shows `0/1` tasks ready when the task is
already RUNNING (a few seconds later, `kubectl get connector` showed `RUNNING 1/1`). Trust the second table.

**Step 2: what the CLI does on Kubernetes**

```bash
playground connector create-or-update -c lab-rewrites --dry-run << 'EOF'
{
  "tasks.max": "1",
  "connector.class": "org.apache.kafka.connect.file.FileStreamSinkConnector",
  "topics": "filestream",
  "file": "/tmp/output.json",
  "confluent.topic.bootstrap.servers": "broker:9092",
  "value.converter": "io.confluent.connect.avro.AvroConverter",
  "value.converter.schema.registry.url": "http://schema-registry:8081"
}
EOF
# 🌵 --dry-run: Connector CRD manifest that would be applied:
#     apiVersion: platform.confluent.io/v1beta1
#     kind: Connector
#     metadata:
#       name: lab-rewrites
#       namespace: confluent
#     spec:
#       class: org.apache.kafka.connect.file.FileStreamSinkConnector
#       taskMax: 1
#       connectClusterRef:
#         name: connect
#       configs:
#         topics: "filestream"
#         file: "/tmp/output.json"
#         confluent.topic.bootstrap.servers: "kafka:9071"                    <- was broker:9092
#         value.converter: "io.confluent.connect.avro.AvroConverter"
#         value.converter.schema.registry.url: "http://schemaregistry:8081"  <- was schema-registry
playground connector create-or-update -c FileStream_Sink --dry-run << 'EOF'
{ "connector.class": "org.apache.kafka.connect.file.FileStreamSinkConnector", "topics": "filestream" }
EOF
# ❌ with CFK, the connector name is the name of a Kubernetes Connector resource: lower case letters, digits, '-' and '.' only (FileStream_Sink is not valid)
playground connector show-config -c filestream-sink
# 🧰 Current config for 🌎onprem connector filestream-sink (using CFK Connector CR)
# { "file": "/tmp/output.json", "key.converter": "org.apache.kafka.connect.storage.StringConverter", "topics": "filestream", … }
playground connector validate -c filestream-sink
# ⚠️ validation with CFK currently performs basic checks only (no Connect REST validation endpoint)
# ✅ Basic CFK validation passed
playground connector benchmark -c filestream-sink
# ❌ benchmark is not available with the cfk environment yet                       (exit 1)
playground container recreate
# ❌ container recreate is not supported in cfk mode                              (exit 1)
playground topic describe -t filestream
# 🎰 kubectl -n confluent describe kafkatopic filestream
# Kind:         KafkaTopic
# Spec:
#   Partition Count:  1
#   Replicas:         1
# …
# Topic: filestream	TopicId: …	PartitionCount: 1	ReplicationFactor: 1	Configs: min.insync.replicas=1,segment.bytes=1073741824
```

**Step 3: pause, resume, restart: annotations and pod deletions**

```bash
playground connector pause -c filestream-sink
# ☸️ kubectl annotate connector filestream-sink -n confluent platform.confluent.io/pause-connector=true --overwrite
playground connector wait -c filestream-sink --state PAUSED --max-wait 120
# ✅ 🌎onprem connector filestream-sink is PAUSED (1 task(s)) after 0 seconds
playground connector resume -c filestream-sink
# ☸️ kubectl annotate connector filestream-sink -n confluent platform.confluent.io/resume-connector=true --overwrite
playground connector wait -c filestream-sink --max-wait 120
# ⌛ 🌎onprem connector filestream-sink is PAUSED (1/1 task(s) RUNNING)
# ✅ 🌎onprem connector filestream-sink is RUNNING (1 task(s)) after 11 seconds
playground container restart -c connect
# 🔁 Restarting pod connect-0
# pod "connect-0" deleted from confluent namespace
playground connector wait -c filestream-sink --max-wait 300
# 🔀 Starting CFK port-forward for Connect on localhost:8083
# 🔀 Restarting CFK port-forward for Connect on localhost:8083
# ⚠️ Could not reach CFK Connect REST API on localhost (tried 8083/8283/8383)     <- the new connect-0 is not up yet
# ⌛ 🌎onprem connector filestream-sink is not available yet (0/0 task(s) RUNNING)
# ✅ 🌎onprem connector filestream-sink is RUNNING (1 task(s)) after 18 seconds
playground topic produce -t filestream --nb-messages 3 --value '{"id": "after-restart-%g"}'
playground container exec -c connect --command "cat /tmp/output.json"
# {id=after-restart-1}
# {id=after-restart-2}
# {id=after-restart-3}            <- the 5 first records were in the old pod: the file is gone with it
playground topic get-number-records -t filestream
# 8
```

**Step 4: a failed task, the logs, a support bundle**

```bash
playground connector create-or-update -c filestream-broken --no-wait << 'EOF'
{
  "tasks.max": "1",
  "connector.class": "org.apache.kafka.connect.file.FileStreamSinkConnector",
  "topics": "filestream",
  "file": "/does/not/exist/output.json",
  "key.converter": "org.apache.kafka.connect.storage.StringConverter",
  "value.converter": "org.apache.kafka.connect.json.JsonConverter",
  "value.converter.schemas.enable": "false"
}
EOF
playground connector wait -c filestream-broken --state FAILED --max-wait 180
kubectl -n confluent get connector filestream-broken -o jsonpath='{.status.failedTasks}'
# {"task-0":{"id":0,"retryCount":1,"workerID":"connect-0.connect.confluent.svc.cluster.local:8083"}}
# empty until the next reconcile of the CR (15 seconds in the lab): the lab waits for it before taking the bundle
playground connector status -c filestream-broken
# filestream-broken   CREATED                     0/1           19s     <- the CR is happy: app-ready True
# filestream-broken              ✅ RUNNING  0:🛑 FAILED   tasks: org.apache.kafka.connect.errors.ConnectException: Couldn't find or create file '/does/not/exist/output.json' for FileStream…
playground container logs -c connect --errors
# 🔎 2 distinct record(s), 2 occurrence(s), in 5711 lines
# 🔴 ERROR x1 … Could not get listing for plugin path: /mnt/plugins. Ignoring.     <- harmless: /mnt/plugins of plugin.path doesn't exist
# 🔴 ERROR x1 … ERROR [filestream-broken|task-0] WorkerSinkTask{id=filestream-broken-0} Task threw an uncaught and unrecoverable exception…
#     Caused by: java.nio.file.NoSuchFileException: /does/not/exist/output.json
playground debug cfk generate-bundle
# ⚠️  kubectl confluent plugin not found. Installing...
# ⏳ Downloading CFK bundle version 3.3.0...                                      (364 MB, first time only)
# ✅ Confluent kubectl plugin installed successfully!
# ✅ Support bundle generated successfully!
# 📦 Bundle: /tmp/cfk-support-bundle/support-bundle-ns-confluent-2026-10-28T12-57-53Z.tar.gz
playground analyze logs -f /tmp/cfk-support-bundle/support-bundle-ns-confluent-<date>.tar.gz --output-dir /tmp/lab-cfk-bundle
# Files analyzed:   43  (4 pods, 7 CFK CRs, 83 events, 10 log/text files with 24546 lines, 0 skipped)
# Total issues:     35
# Kubernetes:       v1.35.5+k3s1
# CFK operator:     3.3.0 (image tag 0.1718.10)
# Recent changes (newest first, 12 of 15)
#   2026-10-28T12:56:58Z  Connector/filestream-broken  Update by kubectl-client-side-apply: spec.class, spec.configs, spec.connectClusterRef, spec.taskMax
#   2026-10-28T12:56:05Z  Pod/connect-0  Pod created on k3d-playground-cfk-server-0     <- the container restart of step 3
# ## Connect Issues  (2 issues, worst=high)
#   [HIGH] [connect/connect] application-resources/connector/filestream-broken.yaml
#          Connector/filestream-broken has failed tasks: {"task-0": {"id": 0, "retryCount": 2, "workerID": "connect-0.connect.confluent.svc.cluster.local:8083"}}
#   [MED ] [connect/connect] cluster-resources/connect/connect/logs/connect-0.log:5562  (x3)
#            Affects 1 task(s): filestream-broken-0
#            Caused by: org.apache.kafka.connect.errors.ConnectException: Couldn't find or create file '/does/not/exist/output.json' for FileStreamSinkTask
# ## Compatibility  (4 issues, worst=high)
#   [HIGH] [connect/connect] cluster-details.txt
#          connect runs Confluent Platform 8.4.0, outside the range supported by CFK 3.3.0: 7.5 - 8.3 (8.4.0)
playground analyze logs -f /tmp/cfk-support-bundle/support-bundle-ns-confluent-<date>.tar.gz --component connect --output-dir /tmp/lab-cfk-bundle
# Total issues:     6
# By component:     connect 6
# Filtered on:      --component connect
```

Read the full report with a critical eye, as you would a customer's: on this healthy cluster the `BackOff` of
connect-0 restarting while Kafka was starting is only `low`, marked `[transient: pod connect-0 is Running and Ready in
the bundle, …]`, and the report also lists the `Compatibility` issues: the
support matrix of the analyzer
([`cfk-analysis/environment.py`](https://github.com/vdesabou/kafka-docker-playground/blob/master/cfk-analysis/environment.py))
gives CP 7.5 to 8.3 for CFK 3.3, and the playground runs its default CP version. `--component connect` keeps the 6
issues of Connect.

**Step 5: stop**

```bash
playground stop
# 🔀 Stopping CFK port-forward process(es): 17470 25556
k3d cluster list
# NAME             SERVERS   AGENTS   LOADBALANCER
# playground-cfk   1/1       0/0      true            <- still running
k3d cluster delete playground-cfk    # when you are done with CFK
```

---

## 7. Recipes for support repros

| Customer setup or symptom | Command |
| --- | --- |
| "we upgraded the CR but the pods still run the old version" (support bundle) | `playground analyze logs -f <bundle>`: the 🔄 `Rollout Issues` finding says what each pod runs, how far the roll got, and why (`block-reconcile`, operator not applying, roll blocked) |
| "here is a new bundle, what changed since the last one?" | `playground analyze logs -f <older bundle> -f <newer bundle>`: the 🔁 comparison gives the verdict, the changes of the CRs between the two, and the issues fixed / new / still there |
| "the ZooKeeper to KRaft migration is stuck" (support bundle) | `playground analyze logs -f <bundle>`: the 🚚 `KRaft Migration` finding gives the sub-phase, since when, the last error and the next steps; `--sample cfk_kraft_migration` to see one |
| "the connector works with Docker, not on our CFK cluster" | the same example with `--environment cfk`, then `connector create-or-update --dry-run` to compare the `Connector` CR with theirs |
| "the customer deploys connectors with a `Connector` CR" | the example under `cfk`, `connector status` shows the CR state next to the Connect state; `kubectl -n confluent get connector <c> -o yaml` for the whole resource |
| "the Connect pods do not start / the plugins do not install" (support bundle) | `playground analyze logs -f <bundle>`: the 🧩 `Plugin Issues` finding gives the plugins of `spec.build.onDemand`, the state of the `config-init-container`, the install error and the next steps (air-gapped: `plugins.url` on an internal server or a custom image) |
| "a plugin is missing / the wrong version on our Connect pods" | `--environment cfk --connector-tag <version>`: the plugin comes from `spec.build.onDemand` like on their cluster; `playground connector plugins` lists what the `Connect` CR reports |
| "a connector restart / pause through annotations does nothing" | `playground connector pause` / `resume` / `restart` print the `kubectl annotate` they run: try the same on the lab connector |
| "the Connect pod was restarted and the connector lost its state" | `playground container restart -c connect` (deletes connect-0), then `connector wait`, `container logs -c connect --previous` for the instance before |
| "the customer sent a support bundle" | `playground analyze logs -f <bundle> --output-dir /tmp/cfk-reports` (no environment needed), `--component connect` |
| "which operator code logs this error? is it fixed after version X?" | `playground debug cfk sourcecode --bundle <bundle> --grep "<message>" [--compare-with <version>]` (private repository, Confluent only) |
| "what would a support bundle of my repro look like?" | `playground debug cfk generate-bundle`, then `analyze logs` on it |
| "RBAC on CFK: `ConfluentRolebinding`, MDS, LDAP" | `--environment cfk-rbac`, `playground rbac role-binding list --principal User:connectorSA`, `kubectl -n confluent get confluentrolebinding` |
| "another CFK version" | `CFK_VERSION=3.2.3 playground run -f <example> --environment cfk` (2.9.5 to 3.3.0) |
| "is this example also red on CFK in CI?" | `playground get-ci-result --test <dir> --environment cfk --logs`; `playground start-ci --cfk --test-list "<dir>"` to run it there |

In a repro model, keep `PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"cfk"}` at the top: `playground run` without
`--environment` then uses CFK, and the model still runs elsewhere. An example that can't work on Kubernetes (it needs
`docker run --network=host`, a fixed hostname, HDFS or Kerberos) skips it:

```bash
if [[ "$PLAYGROUND_ENVIRONMENT" == cfk* ]]
then
  logwarn "this test is not supported with cfk"
  exit 111
fi
```

About 40 `connect/` scripts do that. In CI, the nightly `cfk` job runs every `connect/` example of the matrix on
CFK (and this lab): results are stored with a `-cfk` suffix, and failures get their own issues, `🔥 <dir> (cfk)`.

---

## 8. Cheat sheet

```bash
playground run -f <connect/ example> --environment cfk|cfk-rbac [--tag <cp>] [--connector-tag <v>] [--enable-control-center]
playground start-environment --environment cfk [--docker-compose-override-file <example override>]
CFK_VERSION=3.2.3 K3D_MEMORY=16g playground run -f <example> --environment cfk
playground status                                      # kubectl -n confluent get pods
playground connector create-or-update -c <lower-case-name> [--dry-run] << EOF … EOF
playground connector status|show-config|pause|resume|restart|delete -c <c>
playground container exec|logs|restart|kill -c connect|kafka|schemaregistry   # pods connect-0, kafka-0…
playground debug cfk generate-bundle [--follow-logs-duration 60]
playground analyze logs -f <dir|.tar.gz|.zip> [--component connect] [--severity high] --output-dir /tmp/cfk-reports
k3d cluster delete playground-cfk                      # playground stop keeps the cluster
```

- One k3d cluster `playground-cfk`, the CFK operator kept between runs, CRs in namespace `confluent`.
- The compose override is translated: plugins → `spec.build.onDemand`, environment → `podTemplate.envVars`, other
  services → pods.
- Pods, not containers: `connect-0`, `kafka:9071`, `schemaregistry:8081`, REST through port-forwards on localhost.
- Connectors are `Connector` CRs: lower case names, `broker:9092` / `schema-registry` rewritten, annotations for
  pause / resume / restart.
- Not on CFK: `benchmark`, `container recreate` / `pause`, `--initial-state`, `--wait-for-zero-lag`, real validation.
- Sources: [`environment/cfk/start.sh`](https://github.com/vdesabou/kafka-docker-playground/blob/master/environment/cfk/start.sh),
  [`confluent-platform.yaml`](https://github.com/vdesabou/kafka-docker-playground/blob/master/environment/cfk/confluent-platform.yaml),
  [`environment/cfk-rbac/`](https://github.com/vdesabou/kafka-docker-playground/tree/master/environment/cfk-rbac),
  [`connector/create-or-update.sh`](https://github.com/vdesabou/kafka-docker-playground/blob/master/scripts/cli/src/commands/connector/create-or-update.sh),
  `resolve_container_name_for_environment` / `get_connect_url_and_security` / `get_security_broker` in
  [`cli_function.sh`](https://github.com/vdesabou/kafka-docker-playground/blob/master/scripts/cli/src/lib/cli_function.sh).

---

**Links**

- 🎬 Video session: [☸️ What is wrong in this CFK cluster?](/sessions?id=☸️-what-is-wrong-in-this-cfk-cluster)
- 🍪 Deep dives: [secured environments](/deep-dive-secured-environments.md) (RBAC commands),
  [`connector create-or-update`](/deep-dive-connector-create-or-update.md),
  [containers](/deep-dive-container-lifecycle.md), [JVM diagnostics](/deep-dive-jvm-diagnostics.md),
  [a slow or broken network](/deep-dive-network-traffic.md)
- 📖 [How it works: connector using non-plaintext environment](/how-it-works?id=🔏-connector-using-non-plaintext-environment)
- 🧠 CLI reference: [playground debug cfk generate-bundle](/playground%20debug%20cfk%20generate-bundle),
  [playground analyze logs](/playground%20analyze%20logs), [playground run](/playground%20run)
- 📚 [Confluent for Kubernetes documentation](https://docs.confluent.io/operator/current/overview.html),
  [support bundle](https://docs.confluent.io/operator/current/co-troubleshooting.html#support-bundle)
