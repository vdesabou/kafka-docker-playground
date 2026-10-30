# 🍪 Deep dive: replication between clusters (`mdc-*`, Replicator, MirrorMaker 2, Cluster Linking)

Two Kafka clusters side by side, and the three ways to copy one into the other: **Confluent Replicator** (a
connector, or a standalone executable), **MirrorMaker 2** (Apache Kafka, a set of connectors run by its own process)
and **Cluster Linking** (a feature of Confluent Server brokers, no Connect at all). This is how you reproduce
"the consumers read everything again after the failover", "the offsets of my group were not translated" or "which
one should we use for the migration". The playground has one environment family for it (`mdc-plaintext`,
`mdc-sasl-plain`, `mdc-kerberos`) and a handful of examples in `multi-data-center/` and `ccloud/`. Takes about 20
minutes to read and run.

| You want | Command |
| --- | --- |
| two clusters (`us` and `europe`) with one Connect worker each | `playground start-environment --environment mdc-plaintext` (or `mdc-sasl-plain`, `mdc-kerberos`) |
| a ready-made replication example | `playground run -f multi-data-center/replicator-connect/connect-plaintext.sh` (`replicator-executable`, `mirrormaker2`, `cluster-linking`, see §2) |
| the worker config of one side | `playground container get-properties -c connect-us` (or `connect-europe`) |
| a Kafka command on one cluster | `playground container exec -c broker-europe --command "kafka-consumer-groups --bootstrap-server broker-europe:9092 --describe --group <g>"` |
| a topic, a connector, a group, a schema on one side | `playground topic list --cluster europe`, `playground connector status --cluster us` (or `export PLAYGROUND_CLUSTER=us` once), see §3 |

---

## 1. Mental model (the 3 things to remember)

1. **An `mdc-*` environment is two clusters plus a third one for metrics, all in one compose project.**
   `environment/mdc-plaintext/docker-compose.yml` (plus `docker-compose-kraft.yml` in KRaft mode, the default with
   CP 8) starts:

   | Cluster | Broker | Controller (KRaft) / ZooKeeper | Connect worker | Schema Registry |
   | --- | --- | --- | --- | --- |
   | `us` | `broker-us:9092` | `controller-us` / `zookeeper-us` | `connect-us`, REST on `localhost:8083` | `schema-registry-us`, `localhost:28081` |
   | `europe` | `broker-europe:9092` | `controller-europe` / `zookeeper-europe` | `connect-europe`, REST on `localhost:8283` | `schema-registry-europe`, `localhost:18081` |
   | metrics | `broker-metrics:9092` | `controller-metrics` / `zookeeper-metrics` | none | none |

   Each worker writes to **its own** cluster (`bootstrap.servers=broker-us:9092`, group `connect-us`, internal topics
   `connect-us.config|offsets|status`; the same with `europe`), and has the Replicator plugin installed
   (`plugin.path=/usr/share/confluent-hub-components/confluentinc-kafka-connect-replicator`, installed by
   `start.sh` at the CP version, or at the default tag when that version is not on Confluent Hub, and skipped when that version is already in `confluent-hub/`). Brokers have no port on the host: everything goes through
   `docker exec`. `broker-metrics` receives the metrics reporters and monitoring interceptors of both clusters, for
   Control Center (`--enable-control-center`). `mdc-sasl-plain` and `mdc-kerberos` add their compose file on top of the
   plaintext one, like the single cluster environments (SASL/PLAIN `client` / `client-secret`; Kerberos with a `kdc`
   and a `client` container, brokers named `broker-us.kerberos-demo.local`). In KRaft mode the cluster ids are fixed in
   `docker-compose-kraft.yml`: `NkU3OEVBNTcwNTJENDM2Qk` for `us`, `MkU3OEVBNTcwNTJENDM2Qk` for `europe` and
   `OkU3OEVBNTcwNTJENDM2Qk` for `metrics`.

2. **The three tools copy different things, from different places.**

   | | Replicator | MirrorMaker 2 | Cluster Linking |
   | --- | --- | --- | --- |
   | Runs as | a source connector in a Connect worker (`io.confluent.connect.replicator.ReplicatorSourceConnector`), or the `replicator` executable (a Connect worker of its own) | `connect-mirror-maker <file>` (dedicated mode: a Connect cluster of its own), or its connectors in an existing worker | the destination brokers (Confluent Server, `confluent.cluster.link.enable`), managed with `kafka-cluster-links` / `kafka-mirrors` |
   | Destination topic | same name (`topic.rename.format`, default `${topic}`) | prefixed with the source alias: `EUROPE.sales_EUROPE` (`DefaultReplicationPolicy`) | same name, a **read-only mirror topic** until promoted |
   | Offsets of the records | new offsets in the destination | new offsets in the destination | **the same offsets** (byte for byte copy of the partitions) |
   | Consumer group offsets | translated by timestamp, only for consumers that ran the `ConsumerTimestampsInterceptor` in the source | translated from offset syncs (`sync.group.offsets.enabled`, off by default), approximate | copied as is (`consumer.offset.sync.enable`) |
   | Topic configs, partitions | yes (`topic.config.sync`, `topic.preserve.partitions`, both true by default) | yes (`sync.topic.configs.enabled`, true by default) | yes: `cluster-linking/start-plaintext.sh` changes `retention.ms` and the partitions of the source and checks the mirror |
   | Schemas | yes, by replicating `_schemas` with `schema.registry.topic` (see `ccloud/migrate-schemas-to-confluent-cloud`) | no | no |
   | ACLs | no (no ACL key in its config reference) | yes (`sync.topic.acls.enabled`, true by default) | yes (`acl.sync.enable` + `--acl-filters-json-file`, see `ccloud/cluster-linking-with-service-accounts-only`) |
   | Loop prevention | provenance header `__replicator_id` (`provenance.header.enable`, false by default) | the topic prefix: a topic whose prefix is the source or target alias is not replicated again (`isCycle`) | a link is one way |

3. **Offset translation is the heart of a failover, and it is never free.** A consumer group committed offset 10
   in the source. Where should it start in the destination?
   - **Cluster Linking**: at 10, the offsets are the same.
   - **Replicator**: translated through the timestamps of the records, but only if the group's consumers ran the
     `ConsumerTimestampsInterceptor` (it writes `__consumer_timestamps` in the source cluster), and only while no
     consumer of that group is connected to the destination. In the lab: 10 → 10. A group without the interceptor
     doesn't exist in the destination at all.
   - **MirrorMaker 2**: from the offset syncs it records while replicating (`mm2-offset-syncs.<target>.internal`), and
     only with `sync.group.offsets.enabled = true` (false by default). In the lab, a group at 10 of 20 records became
     **1** in the destination: 9 records read twice after the failover.

   Whatever the tool, a consumer that fails over must tolerate duplicates.

---

## 2. The examples

| Example | Tool | Environment | In CI |
| --- | --- | --- | --- |
| `multi-data-center/replicator-connect/connect-plaintext.sh` | Replicator connector, both ways: `sales_EUROPE` to `us` (on `connect-us`), `sales_US` to `europe` (on `connect-europe`) | `mdc-plaintext` | yes |
| `replicator-connect/connect-plaintext-avro.sh`, `connect-plaintext-avro-with-sr-basic-auth.sh` | the same with Avro and the two Schema Registries | `mdc-plaintext` | yes |
| `replicator-connect/connect-sasl-plain.sh`, `connect-kerberos.sh` | the same, with `src.kafka.*` / `dest.kafka.*` security keys | `mdc-sasl-plain`, `mdc-kerberos` | yes |
| `multi-data-center/replicator-executable/executable-plaintext.sh` (`-sasl-plain`, `-kerberos`) | Replicator executable: containers `replicator-us` and `replicator-europe` (image `cp-enterprise-replicator-executable`), each with `consumer.properties` (source), `producer.properties` (destination), `replication.properties` and `WHITELIST`, REST on `18083` | `mdc-*` | yes |
| `multi-data-center/mirrormaker2/mirrormaker2-plaintext.sh` | MirrorMaker 2 dedicated mode, started with `docker exec -d connect-us /usr/bin/connect-mirror-maker /etc/kafka/connect-mirror-maker.properties`, both ways | `mdc-plaintext` | yes |
| `multi-data-center/cluster-linking/start-plaintext.sh` | Cluster link `us` → `europe`, mirror topic, consumer offset sync, group filters, config and partition sync, promotion | `mdc-plaintext` | yes |
| `cluster-linking/start-plaintext-automatic-topic-creation.sh` | the same with `auto.create.mirror.topics.enable` and topic filters | `mdc-plaintext` | yes |
| `cluster-linking/start-plaintext-migrate-sink-connector.sh` | move a sink connector from `connect-us` to `connect-europe`: its group `connect-filestream-sink` follows through the link, the new sink doesn't rewrite the old records | `mdc-plaintext` | yes |
| `multi-data-center/one-to-many-with-offsets-translation/start.sh` | one source (`broker-metrics`), two Replicators (to `europe` and `us`), `offset.timestamps.commit=false` | `mdc-plaintext` | no |
| `multi-data-center/kafka-offsets-migrator/start.sh` | Replicator, then the third party `offset_translator.py` (downloaded at run time) to translate a group | `mdc-plaintext` | no |
| `connect/connect-replicator/replicator.sh` (`-sasl-ssl`, `-2way-ssl`) | Replicator copying `test-topic` to `test-topic-duplicate` **in the same cluster**: to test security settings, not replication between clusters | `plaintext`, `sasl-ssl`, `2way-ssl` | yes |
| `ccloud/replicator/connect-onprem-to-cloud*.sh` | Replicator connector from a local cluster to Confluent Cloud (`dest.kafka.*` read from `${file:/datacloud:…}`); exits 111 with CP 8+ | `ccloud` | no |
| `ccloud/mirrormaker2/mirrormaker2.sh` | MirrorMaker 2 from a local 3-broker cluster (`broker1..3`) to Confluent Cloud, `sync.group.offsets.enabled = true`, empty `replication.policy.separator` / aliases so the topic keeps its name | `ccloud` | no |
| `ccloud/migrate-schemas-to-confluent-cloud/start.sh` | Replicator executable replicating `_schemas` (`schema.registry.topic=_schemas`) into Confluent Cloud Schema Registry in `IMPORT` mode, then the source registry set `READONLY` | `ccloud` | no |
| `ccloud/cluster-linking-with-service-accounts-only/` | notes (no script): a Confluent Cloud cluster link with service accounts and least privilege ACLs | | no |

Gotchas:

- **The `mdc-*` examples start their environment themselves**, some with `playground start-environment --environment
  mdc-plaintext` (`replicator-executable`, `cluster-linking`), some by calling `environment/mdc-plaintext/start.sh`
  directly (`replicator-connect`, `mirrormaker2`). Both record `run.environment=mdc-plaintext`. They don't read
  `PLAYGROUND_ENVIRONMENT`: `playground run --environment sasl-ssl` doesn't turn them into another type, pick the
  `-sasl-plain` / `-kerberos` variant.
- **The Replicator connector runs on the destination side** in `replicator-connect` (`replicate-europe-to-us` on
  `connect-us`): Replicator is a *source* connector, it reads remotely with `src.kafka.*` and its worker writes
  locally. The executable does the same: `replicator-us` consumes from `broker-europe` and produces to `broker-us`.
- `one-to-many-with-offsets-translation` and `kafka-offsets-migrator` run `docker container exec connect-europe
  playground connector create-or-update …` (the CLI inside the container, without `-i`): they are not in CI, read
  them as notes rather than as working scripts.
- Cluster Linking needs CP 7.0+ (the examples exit 111 before), and `cp-server` brokers: the default
  `CP_KAFKA_IMAGE`, not `cp-kafka`.

---

## 3. Pick a cluster: `--cluster us|europe`

The CLI reads `run.environment` (`playground state get run.environment`). An `mdc-*` environment has two clusters, so
the `topic`, `consumer-group`, `connector`, `schema`, `broker` and `quota` commands need to know which one you mean.
**It is never guessed**:

| Set it with | Scope |
| --- | --- |
| `--cluster us` or `--cluster europe` on the command | that command, and the `playground` commands it runs itself |
| `export PLAYGROUND_CLUSTER=europe` | the shell session |
| `playground state set run.cluster us` | every command, until you change it (`playground state set run.cluster ""`) |

In that order: the flag wins over the variable, which wins over the state. Without any of them the command stops before
doing anything:

```text
🔥 ❌ mdc-plaintext runs two clusters: pass --cluster us|europe, or set it for the session with 'export PLAYGROUND_CLUSTER=us' or 'playground state set run.cluster us'
```

What the cluster selects:

| | `us` | `europe` |
| --- | --- | --- |
| broker (`topic`, `consumer-group`, `broker`, `quota`, `connector show-lag`, `offsets`) | `broker-us:9092`, broker id 1 | `broker-europe:9092`, broker id 1 |
| Connect REST API (`connector …`) | `connect-us`, `localhost:8083` | `connect-europe`, `localhost:8283` |
| Schema Registry (`schema …`, Avro / Protobuf / JSON Schema in `topic produce` / `consume`) | `schema-registry-us`, `localhost:28081` | `schema-registry-europe`, `localhost:18081` |
| `topic produce` / `consume` run in | `connect-us` | `connect-europe` |

The security follows the environment: `mdc-sasl-plain` uses the `client` user (`environment/mdc-sasl-plain/client/client.properties`,
mounted as `/tmp/client.properties` in the brokers and workers), `mdc-kerberos` runs the tools in the `client`
container with the `connect` principal and `/etc/kafka/<producer|consumer|command>-<cluster>.properties`, on the
broker FQDN (`broker-us.kerberos-demo.local:9092`). The `metrics` cluster can't be selected (no Connect worker, no
Schema Registry): reach `broker-metrics` with `playground container exec`.

```bash
# produce in europe, read the replicated records in us
playground topic produce --cluster europe --topic sales_EUROPE --nb-messages 20 --value 'european_sale_%g'
playground topic consume --cluster us --topic sales_EUROPE --min-expected-messages 20
# a connector on the us worker
playground connector create-or-update --cluster us --connector replicate-europe-to-us < config.json
playground connector status --cluster us
# a group, on each side
playground consumer-group describe --cluster europe --group my-app
playground consumer-group describe --cluster us --group my-app
```

- `playground status` shows the connectors and the topics of each cluster (`🌍 Cluster us`, `🌍 Cluster europe`),
  unless one is selected.
- **A data center goes down**: `playground broker stop --cluster europe --broker 1 --kill` (a crash, `docker kill`) or
  without `--kill` (controlled shutdown), `playground broker health --cluster europe` (exit 1), then `playground broker
  start --cluster europe --broker 1` (waits for a healthy cluster). Each cluster has one broker: id 1. `broker metrics
  --cluster us` reads the JMX metrics of `broker-us`.
- **The commands that take a container name never needed a cluster**: `container exec|logs|get-properties|cp|restart|recreate
  -c connect-us` (or `broker-europe`, `replicator-us`…), `debug thread-dump|heap-dump -c connect-europe`…
  `playground stop` and `playground container recreate` replay `run.docker_command`, recorded by the `mdc-*` `start.sh`.
- In a single cluster environment `--cluster` is ignored.

Gotchas:

- `playground connector create-or-update` with a customer config rewrites the bootstrap servers and the Schema Registry
  url that are not playground hosts to `broker-<cluster>:9092` and `http://schema-registry-<cluster>:8081`. A
  Replicator config keeps its `src.kafka.bootstrap.servers` / `dest.kafka.bootstrap.servers` when they name
  `broker-us` / `broker-europe`: they are containers of the playground.
- Most `multi-data-center/` examples still use `kafka-*` tools and `curl` through `playground container exec`, with an
  explicit `--bootstrap-server broker-us:9092` or `broker-europe:9092`: both ways work.
- **In the `ccloud` examples, `playground topic …` targets Confluent Cloud** (the `ccloud` environment is not
  filtered): `migrate-schemas-to-confluent-cloud` produces to the local cluster with `playground container exec -c
  connect --command "kafka-avro-console-producer --bootstrap-server broker:9092 …"` for that reason.
- `playground container exec` passes stdin to the container (`docker exec -i`): a heredoc or a pipe works.
- A process started in the background with `container exec` (`nohup … &`, like MirrorMaker 2 in the lab) keeps
  running after the command returns; stop it with `pkill` in the same container.

---

## 4. Offset translation, tool by tool

### Replicator

```text
source cluster                                        destination cluster
my-app (interceptor) ──commits──> __consumer_offsets
                     ──writes───> __consumer_timestamps ──read by Replicator──> __consumer_offsets (my-app, translated)
```

- The consumers of the source need `interceptor.classes=io.confluent.connect.replicator.offsets.ConsumerTimestampsInterceptor`
  and the jar `timestamp-interceptor-<version>.jar` on their classpath. It is in the lib folder of the Replicator
  plugin (`/usr/share/confluent-hub-components/confluentinc-kafka-connect-replicator/lib/timestamp-interceptor-8.4.0.jar`
  in the lab). Java clients only, and it needs WRITE and DESCRIBE on `__consumer_timestamps` with ACLs.
- On a single broker cluster, `__consumer_timestamps` needs `timestamps.topic.replication.factor=1` (it is created
  by the interceptor).
- Replicator keys: `offset.translator.tasks.max` (-1: every task translates), `offset.translator.batch.period.ms`
  (60000: the lab uses 5000), `offset.timestamps.commit` (true: Replicator also writes timestamps for its own
  group, for a later failback; `one-to-many-with-offsets-translation` sets it to false), `offset.topic.commit` (true,
  required by the translation). `playground connector-plugin config-key --key offset.translator.batch.period.ms
  --connector-class io.confluent.connect.replicator.ReplicatorSourceConnector` prints the doc offline.
- Translated offsets are written only while the group has no member in the destination: stop the consumers, wait
  for the translation, then start them on the other side.

### MirrorMaker 2

- `MirrorSourceConnector` copies the records and records **offset syncs** (upstream offset → downstream offset) in
  `mm2-offset-syncs.<target>.internal`, in the source cluster. `MirrorCheckpointConnector` turns the source groups'
  commits into checkpoints in `<source>.checkpoints.internal` in the target and, with
  `sync.group.offsets.enabled = true`, writes them into the target groups that have no active member.
- A group ahead of the closest sync is translated to that sync's downstream offset **plus one** (`OffsetSyncStore`:
  "we can translate the upstream offset only 1 downstream offset past the offset sync itself", to never skip a
  record). Syncs are not written for every record (`offset.lag.max`, 100 by default), so a group in the middle of the
  replicated data is translated backwards: in the lab, offset 10 → 1.
- Defaults to know: `emit.checkpoints.interval.seconds`, `sync.group.offsets.interval.seconds` 60,
  `refresh.groups.interval.seconds` 600 (the lab sets all of them to 5).
- In the `cp-server-connect` 8.4 image, `connect-mirror-maker` finds no log4j2 configuration: its log holds
  `ERROR Reconfiguration failed: No configuration found …` and no INFO lines (lab step 4). Look at the topics and the
  groups, not at the log.
- Dedicated mode creates Connect topics in both clusters, named after the other one (`mm2-configs|offsets|status.EUROPE.internal`
  in `us`, `mm2-*.US.internal` in `europe`, even with `US->EUROPE.enabled = false`), a `heartbeats` topic in both, and
  `EUROPE.heartbeats` in `us` (lab step 4).

### Cluster Linking

- `consumer.offset.sync.enable=true` on the link, with group filters (`--consumer-group-filters-json-file`), copies
  the committed offsets every `consumer.offset.sync.ms`. The offsets are the same on both sides, so there is nothing
  to translate.
- The sync keeps overwriting the destination group: the `cluster-linking/start-plaintext.sh` example
  shows a group moved by a consumer in the destination, then put back by the next sync, until the group is excluded
  from the filters.
- A mirror topic refuses writes (`InvalidRequestException: Cannot append records to read-only mirror topic`).
  `kafka-mirrors --promote --topics <t>` stops the mirror (`State: STOPPED`) and makes it writable; the consumer group
  offsets copied before stay (lab step 5).

---

## 5. Hands-on lab (≈20 min)

The lab starts its own `mdc-plaintext` environment (the override `docker-compose.mdc-plaintext.replication.yml` of
the lab folder only enables cluster links on `broker-europe`), then replays the three tools on the same data.

```bash
playground start-environment --environment mdc-plaintext --docker-compose-override-file "$PWD/other/deep-dive-labs/docker-compose.mdc-plaintext.replication.yml"
```

**Step 1: two clusters, one environment**

```bash
playground state get run.environment
# mdc-plaintext
playground status
# connect-europe   Up About a minute   confluentinc/cp-server-connect:8.4.0
# connect-us       Up About a minute   confluentinc/cp-server-connect:8.4.0
# … schema-registry-us, schema-registry-europe, broker-us, broker-europe, broker-metrics,
#   controller-europe, controller-metrics, controller-us
# 🌍 Cluster us                                                 <- then its connectors and topics
# 🌍 Cluster europe
playground container get-properties -c connect-us | grep -E "^bootstrap|^group.id|storage.topic|plugin.path"
# bootstrap.servers=broker-us:9092
# config.storage.topic=connect-us.config
# group.id=connect-us
# offset.storage.topic=connect-us.offsets
# plugin.path=/usr/share/confluent-hub-components/confluentinc-kafka-connect-replicator
# status.storage.topic=connect-us.status
playground container get-properties -c connect-europe | grep "^bootstrap"
# bootstrap.servers=broker-europe:9092
```

**Step 2: pick the cluster with `--cluster`**

```bash
playground topic list
# 🔥 ❌ mdc-plaintext runs two clusters: pass --cluster us|europe, or set it for the session with 'export PLAYGROUND_CLUSTER=us' or 'playground state set run.cluster us'   <- exit 1
playground topic create --topic lab_cluster_selector --cluster europe
playground topic list --cluster europe
# lab_cluster_selector
playground topic list --cluster us                     # not there: another cluster
PLAYGROUND_CLUSTER=europe playground topic describe --topic lab_cluster_selector
# Topic: lab_cluster_selector …
playground connector status --cluster us
# 💤 No … connector is running !
playground consumer-group list --cluster europe         # exit 0
playground topic delete --topic lab_cluster_selector --cluster europe
playground broker health --cluster europe
# ✅ cluster is healthy
playground broker stop --cluster europe --broker 1 --kill
# 🔫 Killing broker 1 (container broker-europe): no controlled shutdown, like a crash
# 🎓 see the impact with 'playground broker health --cluster europe', start it again with 'playground broker start --broker 1 --cluster europe'
playground broker health --cluster us                   # the other data center doesn't notice
playground broker start --cluster europe --broker 1
# ✅ cluster is healthy, broker 1 started in …s
```

The next steps keep the `kafka-*` tools through `playground container exec`, with an explicit `--bootstrap-server`: what
the `multi-data-center/` examples do.

**Step 3: Replicator connector, `europe` → `us`, with offset translation**

20 records in `europe`, then two applications read the first 10: `app-with-interceptor` with the
`ConsumerTimestampsInterceptor`, `app-without-interceptor` without it.

```bash
seq -f "european_sale_%g" 20 | playground container exec -c broker-europe --command "kafka-console-producer --bootstrap-server broker-europe:9092 --topic sales_EUROPE"
playground container exec -c connect-europe --command "ls /usr/share/confluent-hub-components/confluentinc-kafka-connect-replicator/lib | grep -E 'timestamp|interceptor'"
# jakarta.interceptor-api-2.1.0.jar
# logging-interceptor-4.10.0.jar
# timestamp-interceptor-8.4.0.jar
playground container exec -c connect-europe --command "CLASSPATH=\$(ls /usr/share/confluent-hub-components/confluentinc-kafka-connect-replicator/lib/timestamp-interceptor-*.jar) kafka-console-consumer --bootstrap-server broker-europe:9092 --topic sales_EUROPE --from-beginning --max-messages 10 --group app-with-interceptor --consumer-property interceptor.classes=io.confluent.connect.replicator.offsets.ConsumerTimestampsInterceptor --consumer-property timestamps.topic.replication.factor=1"
# european_sale_1 … european_sale_10
# Processed a total of 10 messages
playground container exec -c connect-europe --command "kafka-console-consumer --bootstrap-server broker-europe:9092 --topic sales_EUROPE --from-beginning --max-messages 10 --group app-without-interceptor"
# Processed a total of 10 messages
playground container exec -c broker-europe --command "kafka-topics --bootstrap-server broker-europe:9092 --list"
# __consumer_offsets
# __consumer_timestamps                <- created by the interceptor, in the source cluster
# …
playground container exec -c broker-europe --command "kafka-consumer-groups --bootstrap-server broker-europe:9092 --describe --group app-with-interceptor"
# GROUP                TOPIC           PARTITION  CURRENT-OFFSET  LOG-END-OFFSET  LAG
# app-with-interceptor sales_EUROPE    0          10              20              10
```

The Replicator connector runs on `connect-us`, created with `curl` from inside the container (`playground connector
create-or-update --cluster us --connector replicate-europe-to-us` does the same):

```bash
playground container exec -c connect-us --command "curl -s -X PUT -H 'Content-Type: application/json' --data @- http://localhost:8083/connectors/replicate-europe-to-us/config" << 'EOF'
{
  "connector.class": "io.confluent.connect.replicator.ReplicatorSourceConnector",
  "key.converter": "io.confluent.connect.replicator.util.ByteArrayConverter",
  "value.converter": "io.confluent.connect.replicator.util.ByteArrayConverter",
  "header.converter": "io.confluent.connect.replicator.util.ByteArrayConverter",
  "src.kafka.bootstrap.servers": "broker-europe:9092",
  "dest.kafka.bootstrap.servers": "broker-us:9092",
  "src.consumer.group.id": "replicate-europe-to-us",
  "topic.whitelist": "sales_EUROPE",
  "provenance.header.enable": "true",
  "offset.translator.batch.period.ms": "5000",
  "confluent.topic.replication.factor": "1"
}
EOF
playground container exec -c connect-us --command "curl -s http://localhost:8083/connectors/replicate-europe-to-us/status"
# {"name":"replicate-europe-to-us","connector":{"state":"RUNNING","worker_id":"connect-us:8083","version":"8.4.0"},"tasks":[{"id":0,"state":"RUNNING",…}],"type":"source"}
playground container exec -c broker-us --command "kafka-console-consumer --bootstrap-server broker-us:9092 --topic sales_EUROPE --from-beginning --max-messages 20 --timeout-ms 120000 --property print.headers=true"
# __replicator_id:MkU3OEVBNTcwNTJENDM2Qk,sales_EUROPE,1793189867473	european_sale_1      <- the provenance header
# …
# Processed a total of 20 messages
playground container exec -c broker-us --command "kafka-consumer-groups --bootstrap-server broker-us:9092 --describe --group app-with-interceptor"
# Consumer group 'app-with-interceptor' has no active members.
# app-with-interceptor sales_EUROPE    0          10              20              10      <- translated: 10 in us too
playground container exec -c broker-us --command "kafka-consumer-groups --bootstrap-server broker-us:9092 --describe --group app-without-interceptor"
# Error: Executing consumer group command failed due to org.apache.kafka.common.errors.GroupIdNotFoundException: Group app-without-interceptor not found.
playground container exec -c broker-us --command "kafka-console-consumer --bootstrap-server broker-us:9092 --topic sales_EUROPE --max-messages 10 --timeout-ms 60000 --group app-with-interceptor"
# european_sale_11 … european_sale_20         <- the failover of app-with-interceptor: no duplicate, no gap
# Processed a total of 10 messages
```

The translation was there as soon as the 20 records were (`offset.translator.batch.period.ms=5000`). Without the
interceptor, the group doesn't exist in `us`: a consumer of `app-without-interceptor` there would start from
`auto.offset.reset`. The value of `__replicator_id` starts with the id of the origin cluster: the local cluster id
of `europe` printed by `kafka-cluster-links --list` in step 5 is the same, `MkU3OEVBNTcwNTJENDM2Qk`.

**Step 4: MirrorMaker 2, `europe` → `us`, with group offset sync**

MirrorMaker 2 in dedicated mode, in the `connect-us` container (like `multi-data-center/mirrormaker2`), one flow,
the sync intervals shortened to 5 seconds:

```bash
playground container exec -c connect-us --command "cat > /tmp/mm2.properties" << 'EOF'
clusters = EUROPE, US
EUROPE.bootstrap.servers = broker-europe:9092
US.bootstrap.servers = broker-us:9092
EUROPE->US.enabled = true
EUROPE->US.topics = sales_EUROPE
US->EUROPE.enabled = false
sync.group.offsets.enabled = true
emit.checkpoints.interval.seconds = 5
sync.group.offsets.interval.seconds = 5
refresh.groups.interval.seconds = 5
refresh.topics.interval.seconds = 5
replication.factor = 1
checkpoints.topic.replication.factor = 1
heartbeats.topic.replication.factor = 1
offset-syncs.topic.replication.factor = 1
config.storage.replication.factor = 1
offset.storage.replication.factor = 1
status.storage.replication.factor = 1
EOF
playground container exec -c connect-us --command "nohup connect-mirror-maker /tmp/mm2.properties > /tmp/mm2.log 2>&1 < /dev/null &"
playground container exec -c broker-us --command "kafka-console-consumer --bootstrap-server broker-us:9092 --topic EUROPE.sales_EUROPE --from-beginning --max-messages 20 --timeout-ms 180000"
# european_sale_1 … european_sale_20
# Processed a total of 20 messages              <- in EUROPE.sales_EUROPE: the source alias is the prefix
playground container exec -c broker-us --command "kafka-consumer-groups --bootstrap-server broker-us:9092 --describe --group app-without-interceptor"
# GROUP                   TOPIC               PARTITION  CURRENT-OFFSET  LOG-END-OFFSET  LAG
# app-without-interceptor EUROPE.sales_EUROPE 0          1               20              19     <- 10 in europe, 1 in us
playground container exec -c broker-us --command "kafka-consumer-groups --bootstrap-server broker-us:9092 --describe --group app-with-interceptor"
# app-with-interceptor EUROPE.sales_EUROPE 0          1               20              19      <- MirrorMaker 2
# app-with-interceptor sales_EUROPE        0          20              20              0       <- Replicator (step 3), then read in us
playground container exec -c broker-us --command "kafka-console-consumer --bootstrap-server broker-us:9092 --topic EUROPE.sales_EUROPE --max-messages 1 --timeout-ms 60000 --group app-without-interceptor"
# european_sale_2                               <- the failover reads european_sale_2 … european_sale_10 a second time
```

The group had committed 10 in `europe`. The only offset sync below 10 was the one of the first record (0 → 0),
and MirrorMaker 2 translates "after a sync" to the sync's downstream offset + 1: 1, still 1 fifteen seconds later.
Both groups get it, the interceptor plays no role here. The internal topics show where each piece lives:

```bash
playground container exec -c broker-us --command "kafka-topics --bootstrap-server broker-us:9092 --list"
# EUROPE.checkpoints.internal  EUROPE.heartbeats  EUROPE.sales_EUROPE  heartbeats
# mm2-configs.EUROPE.internal  mm2-offsets.EUROPE.internal  mm2-status.EUROPE.internal  sales_EUROPE …
playground container exec -c broker-europe --command "kafka-topics --bootstrap-server broker-europe:9092 --list"
# __consumer_timestamps  heartbeats  mm2-offset-syncs.US.internal  sales_EUROPE …      <- offset syncs: in the source
playground container exec -c connect-us --command "head -1 /tmp/mm2.log"
# … main ERROR Reconfiguration failed: No configuration found for '3c46e67a' at 'null' in 'null'
playground container exec -c connect-us --command "pkill -f '[M]irrorMaker'"
```

**Step 5: Cluster Linking, `us` → `europe`, with consumer offset sync**

```bash
seq -f "us_sale_%g" 20 | playground container exec -c broker-us --command "kafka-console-producer --bootstrap-server broker-us:9092 --topic sales_US"
playground container exec -c broker-us --command "kafka-console-consumer --bootstrap-server broker-us:9092 --topic sales_US --from-beginning --max-messages 5 --group app-cl"
# us_sale_1 … us_sale_5
playground container exec -c broker-europe --command "cat > /tmp/cl-groups.json" << 'EOF'
{"groupFilters": [{"name": "*", "patternType": "LITERAL", "filterType": "INCLUDE"}]}
EOF
playground container exec -c broker-europe --command "kafka-cluster-links --bootstrap-server broker-europe:9092 --create --link us-to-europe --config bootstrap.servers=broker-us:9092,metadata.max.age.ms=5000,consumer.offset.sync.enable=true,consumer.offset.sync.ms=3000 --consumer-group-filters-json-file /tmp/cl-groups.json"
# Cluster link 'us-to-europe' creation successfully completed.
playground container exec -c broker-europe --command "kafka-mirrors --create --mirror-topic sales_US --link us-to-europe --bootstrap-server broker-europe:9092"
# Created topic sales_US.
playground container exec -c broker-europe --command "kafka-consumer-groups --bootstrap-server broker-europe:9092 --describe --group app-cl"
# GROUP           TOPIC           PARTITION  CURRENT-OFFSET  LOG-END-OFFSET  LAG
# app-cl          sales_US        0          5               20              15      <- the same offset: nothing to translate
playground container exec -c broker-europe --command "kafka-cluster-links --list --link us-to-europe --include-topics --bootstrap-server broker-europe:9092"
# Link name: 'us-to-europe', link ID: '…', remote cluster ID: '…', local cluster ID: 'MkU3OEVBNTcwNTJENDM2Qk', remote cluster available: 'true', link state: 'ACTIVE', topics: [sales_US]
echo europe_sale_1 | playground container exec -c broker-europe --command "kafka-console-producer --bootstrap-server broker-europe:9092 --topic sales_US"
# ERROR Error when sending message to topic sales_US …
# org.apache.kafka.common.errors.InvalidRequestException: Cannot append records to read-only mirror topic 'sales_US'
playground container exec -c broker-europe --command "kafka-mirrors --promote --topics sales_US --bootstrap-server broker-europe:9092"
# Request for stopping topic sales_US's mirror was successfully scheduled. Please use the describe command with the --pending-stopped-only option to monitor progress.
playground container exec -c broker-europe --command "kafka-mirrors --describe --topics sales_US --bootstrap-server broker-europe:9092"
# Topic: sales_US	LinkName: us-to-europe	…	State: STOPPED	…
# 	Partition: 0	State: STOPPED	LocalLogEndOffset: 20	StoppedLogEndOffset: 20	DataWrittenSinceStopped: 0
echo europe_sale_1 | playground container exec -c broker-europe --command "kafka-console-producer --bootstrap-server broker-europe:9092 --topic sales_US"
playground container exec -c broker-europe --command "kafka-get-offsets --bootstrap-server broker-europe:9092 --topic sales_US"
# sales_US:0:21                                 <- writable after the promotion
playground container exec -c broker-europe --command "kafka-console-consumer --bootstrap-server broker-europe:9092 --topic sales_US --max-messages 5 --timeout-ms 60000 --group app-cl"
# us_sale_6 … us_sale_10                        <- the failover of app-cl: it continues where it stopped in us
playground container exec -c broker-europe --command "kafka-cluster-links --bootstrap-server broker-europe:9092 --delete --link us-to-europe"
# Cluster link 'us-to-europe' deletion successfully completed.
```

In CI the whole lab takes about 6 minutes, half of it to start the environment. Not replayed: the Replicator
executable and the SASL / Kerberos variants (same mechanics, run the examples of §2), and the Confluent Cloud
examples (they need Confluent Cloud credentials and are not in CI).

```bash
playground stop
```

---

## 6. Recipes for support repros

| Customer symptom or question | Commands |
| --- | --- |
| "Replicator, MirrorMaker 2 or Cluster Linking?" | see the table of §1: same offsets and no Connect to run → Cluster Linking (Confluent Server on both ends, or Confluent Cloud); topic renaming, filtering, a Connect cluster already there → Replicator (or MirrorMaker 2 when only Apache Kafka is allowed). Replay the three on the same data with the lab (steps 3 to 5) |
| "consumer offsets not translated" (Replicator) | the consumers didn't run the `ConsumerTimestampsInterceptor` (no `__consumer_timestamps` in the source: `kafka-topics --list` on the source broker), or a member of the group is connected in the destination, or `offset.topic.commit=false`. Lab step 3: `app-without-interceptor` doesn't exist in `us` |
| "consumer offsets not translated" (MirrorMaker 2) | `sync.group.offsets.enabled` is false by default; the group must have committed on a replicated topic, and have no active member in the target. Look at `<source>.checkpoints.internal` in the target |
| "duplicates after failover" | MirrorMaker 2: expected, lab step 4 (a group at 10 restarts at 1). Replicator: the translation goes through timestamps, exact in step 3, and only for consumers with the interceptor. Cluster Linking keeps the offsets (step 5). Make the consumer idempotent, or reset the group in the destination to a timestamp |
| "the consumers in DR started from the beginning / the end" | the group didn't exist in the destination: `auto.offset.reset` decided. `kafka-consumer-groups --describe --group <g>` on both brokers (`GroupIdNotFoundException` = never translated) |
| "messages loop between the two data centers" | Replicator both ways without `provenance.header.enable=true` (`replicator-connect` sets it). MirrorMaker 2 doesn't loop: the prefix marks remote topics |
| "Replicator to Confluent Cloud" | `ccloud/replicator/connect-onprem-to-cloud.sh` (CP 7.x only, exits 111 with 8+): `dest.kafka.*` with `SASL_SSL`, `topic.auto.create=false` and the topic created first |
| "migrate schemas to Confluent Cloud" | `ccloud/migrate-schemas-to-confluent-cloud/start.sh`: destination registry in `IMPORT` mode, `_schemas` replicated with `schema.registry.topic`, source registry `READONLY` |
| "move a sink connector to the DR cluster without rewriting everything" | `multi-data-center/cluster-linking/start-plaintext-migrate-sink-connector.sh`: the group `connect-<connector>` follows through the link |
| "the source data center goes down: what happens to the replication, the consumers?" | `playground broker stop --cluster europe --broker 1 --kill`, look at the Replicator / MirrorMaker 2 tasks (`playground connector status --cluster us`) and the groups on the other side, then `playground broker start --cluster europe --broker 1` |
| "a mirror topic refuses writes" | expected until `kafka-mirrors --promote --topics <t>` (lab step 5) |
| "SASL or Kerberos between the clusters" | `replicator-connect/connect-sasl-plain.sh`, `connect-kerberos.sh`, `replicator-executable/executable-sasl-plain.sh`, `executable-kerberos.sh` |

In a repro model based on an mdc example, use `playground topic|connector|consumer-group|schema … --cluster us|europe`
(or `export PLAYGROUND_CLUSTER=…` at the top of the script); the raw `kafka-*` / `curl` calls through `playground
container exec` with an explicit `--bootstrap-server` keep working too.

---

## 7. Cheat sheet

```bash
playground start-environment --environment mdc-plaintext|mdc-sasl-plain|mdc-kerberos [--docker-compose-override-file <override>]
playground container get-properties -c connect-us|connect-europe
playground container exec -c broker-us|broker-europe --command "kafka-topics --bootstrap-server broker-us:9092 --list"
playground container exec -c broker-us --command "kafka-consumer-groups --bootstrap-server broker-us:9092 --describe --group <g>"
playground container exec -c connect-us --command "curl -s http://localhost:8083/connectors/<c>/status"     # connect-europe: same, from inside
playground container logs -c connect-us --errors      playground debug thread-dump -c connect-europe
playground topic|consumer-group|connector|schema … --cluster us|europe     # or: export PLAYGROUND_CLUSTER=us, playground state set run.cluster us
playground broker health|describe|metrics --cluster europe        playground broker stop --cluster europe --broker 1 --kill   # a data center goes down
# Cluster Linking, on the destination broker:
kafka-cluster-links --bootstrap-server broker-europe:9092 --create --link <l> --config bootstrap.servers=broker-us:9092,consumer.offset.sync.enable=true [--consumer-group-filters-json-file <f>]
kafka-mirrors --create --mirror-topic <t> --link <l> --bootstrap-server broker-europe:9092
kafka-mirrors --promote --topics <t> --bootstrap-server broker-europe:9092
```

- `us` = `broker-us` / `connect-us` (REST `localhost:8083`), `europe` = `broker-europe` / `connect-europe` (REST
  `localhost:8283`), metrics = `broker-metrics`.
- Replicator: same topic name, provenance header, group offsets translated by timestamp for consumers with the
  `ConsumerTimestampsInterceptor` only.
- MirrorMaker 2: `<source>.<topic>`, group offsets with `sync.group.offsets.enabled = true`, approximate.
- Cluster Linking: same name, same offsets, read-only until promoted.
- Sources: [`environment/mdc-plaintext/`](https://github.com/vdesabou/kafka-docker-playground/tree/master/environment/mdc-plaintext),
  [`multi-data-center/`](https://github.com/vdesabou/kafka-docker-playground/tree/master/multi-data-center),
  `get_mdc_cluster` and `get_mdc_client` in [`cli_function.sh`](https://github.com/vdesabou/kafka-docker-playground/blob/master/scripts/cli/src/lib/cli_function.sh).

---

**Links**

- 🍪 Deep dives: [secured environments](/deep-dive-secured-environments.md) (the single cluster types),
  [offsets and lag](/deep-dive-offsets-and-lag.md) (consumer groups on one cluster),
  [containers](/deep-dive-container-lifecycle.md) (`container exec`, `get-properties`)
- 📖 Confluent docs: [Replicator](https://docs.confluent.io/platform/current/multi-dc-deployments/replicator/index.html),
  [consumer offset translation](https://docs.confluent.io/platform/current/multi-dc-deployments/replicator/replicator-failover.html),
  [Cluster Linking](https://docs.confluent.io/platform/current/multi-dc-deployments/cluster-linking/index.html);
  Apache Kafka: [geo-replication with MirrorMaker 2](https://kafka.apache.org/documentation/#georeplication)
- 🧠 CLI reference: [playground container exec](/playground%20container%20exec),
  [playground container get-properties](/playground%20container%20get-properties)
