# 🍪 Deep dive: observability (`--enable-control-center`, `--enable-jmx-grafana`, `broker metrics`)

Where to look when a case is about numbers: is the broker the bottleneck, which partitions are under-replicated, why a
consumer lags, why produce latency went up. The playground gives three levels: one-call digests that read JMX on demand
(nothing to enable), the raw MBeans, and dashboards (Grafana with Prometheus, or Control Center). This page says what
each flag starts, how the metrics flow, the gotchas (`down` targets, unscraped standalone clients), and which metric
answers which support question. Takes about 20 minutes to read and run.

> [!TIP]
> Broker failures, rolling restarts and transactions are in the [brokers and transactions deep dive](/deep-dive-broker.md);
> connector metrics and the dead letter queue in [`connector diagnose`](/deep-dive-connector-troubleshooting.md); lag
> in [offsets and lag](/deep-dive-offsets-and-lag.md); thread dumps, GC logs and flight recordings in
> [JVM diagnostics](/deep-dive-jvm-diagnostics.md).

| You want | Command |
| --- | --- |
| is a broker the bottleneck? (idle threads, queue, p99, ISR shrinks, failed requests) | `playground broker metrics` (`--topic <t>`, `--broker <id>`, `--json`) |
| is a connector making progress? errors, retries, DLQ, poll / put time | `playground connector metrics` (`--connector <name>`, `--watch 10s`, `--json`) |
| is there an active controller? offline partitions? (KRaft) | `playground broker metrics --controller` (also the last section of `broker metrics`) |
| are the connect workers rebalancing? which one runs what? | `playground connector metrics --worker` |
| is Schema Registry slow or failing requests? | `playground schema metrics` |
| a ksqlDB query in ERROR, rebalancing, consuming nothing | `playground ksqldb metrics` |
| the lag of a consumer group or a sink | `playground consumer-group describe --group <g>`, `connector show-lag` |
| the raw MBeans of a container | `playground get-jmx-metrics -c broker` (lists the domains), then `--domain kafka.server`, `--mbean "kafka.server:type=ReplicaManager,*"` or `--all` |
| dashboards over time: Prometheus + Grafana + Pyroscope | `playground run … --enable-jmx-grafana` (or `ENABLE_JMX_GRAFANA=1`) |
| Control Center (Next Gen) and its alerts | `playground run … --enable-control-center` (or `ENABLE_CONTROL_CENTER=1`); `--enable-legacy-control-center` for CP < 8, `--control-center-tag` |
| the metrics of a fully managed connector | `playground connector display-metrics-api` (`display-metrics-api-with-grafana` for graphs) |

---

## 1. Mental model (the 3 things to remember)

1. **Three levels, from the cheapest.** `broker metrics` and `connector metrics` read JMX in the containers when you
   run them, with the `kafka-jmx` tool of the image: always available, no flag, about a second per broker. Below them,
   `get-jmx-metrics` dumps raw MBeans (jmxterm runs in the container). Dashboards need a flag at start: they show a
   trend, the digests show now.
2. **Two separate metric pipelines.**

   ```
   --enable-jmx-grafana     broker / connect / schema-registry JVMs ── JMX exporter agent :1234 ──▶ prometheus :9090 (scrape 15 s) ──▶ grafana :3000
                            the same JVMs ── Pyroscope agent ──▶ pyroscope :4040 (CPU profiles)
                            kafka-lag-exporter :9998, node-exporter, alertmanager :9093
   --enable-control-center  brokers ── Confluent telemetry (OTLP) ──▶ prometheus-c3-v2 (not published, scrape 60 s) ──▶ control-center :9021
                            alertmanager-c3-v2
   ```

   They don't share anything: the metric names differ (`kafka_server_replicamanager_underreplicatedpartitions` in
   Grafana's Prometheus, `io_confluent_kafka_server_partition_under_replicated` in Control Center's), and both flags
   can be on together.
3. **The flags apply at start.** They add Docker Compose profiles and set the JVM agents (`EXTRA_ARGS`) or the
   telemetry exporter of the brokers. On a running environment, run the example again with the flag
   (`playground run -f <example> --enable-jmx-grafana`): `playground re-run` replays the flags of the previous run,
   and they are stored in `playground.ini` (`[flags]`).

---

## 2. The digests: one `metrics` command per component

```bash
playground broker metrics --topic lab-observability
# 📈 Broker metrics (rates and failed requests of topic lab-observability)
# METRIC                                 BROKER 1
# Partitions                             153
# Leaders                                153
# Under-replicated partitions            0
# Under min ISR partitions               0
# Request handler idle (1m)              90%
# Network processor idle                 100%
# Request queue size                     0
# Produce p99                            125 ms
# Fetch consumer p99                     516 ms
# Fetch follower p99                     0 ms
# Messages in/s (1m)                     3680.2
# Bytes in/s (1m)                        150.5 KB
# Bytes out/s (1m)                       -
# ISR shrinks (since start)              0
# ISR expands (since start)              0
# Failed produce requests (since start)  -
# Failed fetch requests (since start)    -
# 🎓 idle below 30% means the broker threads are saturated (num.io.threads, num.network.threads)
#    fetch p99 includes the time a fetch waits for data (fetch.max.wait.ms, replica.fetch.wait.max.ms: 500 ms by default)
```

- One column per broker (`--enable-multiple-brokers`: three). ⚠️ marks idle below 30% and any under-replicated or
  under min ISR partition. `--json` gives the raw values (idle as a ratio: `0.908…`).
- `--topic` restricts the rates and the failed requests to one topic: `-` means the topic had none on that broker.
- It is the same MBeans as the Grafana panels, read once: run it during the load (a `connector benchmark`, a
  `topic produce --nb-messages 1000000`), not after.

```bash
playground connector metrics --connector filestream-sink
# 📈 Task metrics of 🌎onprem connector filestream-sink (sink, connector RUNNING)
# METRIC                TASK 0
# state                 RUNNING
# records read/s        0.1/s
# records sent/s        0.1/s
# put batch avg         0 ms
# offset commit failed  0%
# running ratio         100%
# record errors         0
# retries               0
# sent to DLQ           0
# last error            -
# …
# ✅ Nothing stands out: no error, no skipped record, all tasks made progress
```

The full description, and `connector diagnose` which adds the error digest and the lag, are in the
[`connector diagnose` deep dive](/deep-dive-connector-troubleshooting.md).

`broker metrics` ends with the **controller section** (`--controller` alone, also with `--json`):

```bash
playground broker metrics --controller
# 🗳️ Controller metrics (KRaft controllers)
# METRIC                                  CONTROLLER 4
# Active controller                       yes
# Offline partitions                      0
# Partitions (cluster)                    212
# Topics (cluster)                        15
# Preferred replica imbalance             0
# Last applied record lag                 357 ms
# Unclean leader elections (since start)  0
```

In KRaft the columns are the controller containers (node ids 4, 5, 6 with `--enable-multiple-controllers`); with
ZooKeeper (CP < 8) they are the brokers, one of which is the active controller. A ⚠️ follows when the cluster doesn't
have exactly one active controller.

```bash
playground connector metrics --worker
# 📈 Connect worker metrics
# METRIC                              WORKER connect
# Connectors                          1
# Tasks                               1
# Connector startup failures (total)  0
# Task startup failures (total)       0
# Assigned connectors                 1
# Assigned tasks                      1
# Rebalances (total)                  3
# Failed rebalances (total)           1
# Rebalances per hour                 2.9
# Last rebalance (seconds ago)        67
# Rebalance latency avg               -
# Last heartbeat (seconds ago)        1
```

One column per worker (`--enable-multiple-connect-workers`: three). One failed rebalance is normal when a worker
starts (its first join, before the group coordinator is ready); rebalances that keep growing with a small "last
rebalance" are a rebalance loop.

```bash
playground ksqldb metrics
# 📈 ksqlDB metrics (query states now, rates over the last samples)
# METRIC                    CONTAINER ksqldb-server
# Persistent queries        1
# Running queries           1
# Queries in ERROR          0
# Not running queries       0
# Rebalancing queries       0
# Pending shutdown queries  0
# Pending error queries     0
# Error rate                0.0
# Active queries            1
# Idle queries              1
# Messages consumed/s       0.0
# Messages produced/s       0.0
# Liveness indicator        1
```

The engine statistics of `ksqldb-server` (`io.confluent.ksql.metrics:type=_confluent-ksql-<service id>ksql-engine-query-stats`):
then `ksqldb list` for the state of each query and `ksqldb describe --source <its sink>` for its errors.

```bash
playground schema metrics
# 📈 Schema Registry metrics (rates and latencies over the last samples, counts since the start)
# METRIC                      CONTAINER schema-registry
# Leader                      yes
# Requests/s                  0.7
# Client errors (4xx)/s       0.2
# Server errors (5xx)/s       0.0
# Server errors (5xx, total)  0
# Request latency avg         4 ms
# Request latency p99         77 ms
# Active connections          1
# Registered schemas          1
# Avro schemas created        1
# …
# 🎓 4xx are answers to the client (404: subject or version not found, 409: incompatible schema, 422: invalid schema),
#    not failures of Schema Registry
```

The `kafka.schema.registry` MBeans of the server (`jersey-metrics` for the requests, per status code with
`http_status_code=4xx|5xx`, `jetty-metrics`, `registered-count`, `<format>-schemas-created|deleted`,
`master-slave-role`). ⚠️ only on 5xx: a 404 is the normal answer to a subject or a version that doesn't exist.

All the digests share one engine (`jmx_digest_read` in `cli_function.sh`): `kafka-jmx` in the container when the image
has it (brokers, controllers, connect), jmxterm otherwise (schema-registry, ksqldb-server), one column per container,
⚠️ on the values to look at, `--json` for the raw values.

---

## 3. The raw MBeans: `get-jmx-metrics`

```bash
playground get-jmx-metrics -c broker                                     # 📚 JMX domains of container broker
playground get-jmx-metrics -c broker -d "kafka.server kafka.network"     # every attribute of the MBeans of these domains
playground get-jmx-metrics -c broker --mbean "kafka.server:type=ReplicaManager,*"   # only the MBeans matching a name
playground get-jmx-metrics -c controller -d kafka.controller             # KRaft: the controller metrics are on the controller
playground get-jmx-metrics -c connect --all --open                       # every MBean, in your editor
```

- Without a filter it lists the domains and the digest commands to try, instead of dumping thousands of lines.
  `--mbean` is repeatable, takes a `*` in a value, and the keys can be in any order.

- The MBean lines look like `#mbean = kafka.server:name=UnderReplicatedPartitions,type=ReplicaManager:` (keys in
  alphabetical order, then one line per attribute: `Value`, `Count`, `OneMinuteRate`, `99thPercentile`…).
- JMX ports on the host, for jconsole or VisualVM: broker `10000` (`broker2` `12000`, `broker3` `13000`),
  schema-registry `10001`, connect `10002`, ksqldb-server `10003`, controller `10005`. Since CP 8.4 the
  Schema Registry image opens remote JMX only on request: the environment sets `SCHEMA_REGISTRY_JMX_OPTS` to keep port 10001.
- **KRaft**: `ActiveControllerCount`, `OfflinePartitionsCount`, `GlobalPartitionCount`, `PreferredReplicaImbalanceCount`
  are MBeans of the `controller` container (`kafka.controller:…,type=KafkaController`), not of the brokers.

---

## 4. Grafana, Prometheus, Pyroscope: `--enable-jmx-grafana`

```bash
playground run -f <example> --enable-jmx-grafana
# 🛡️ Prometheus is reachable at http://127.0.0.1:9090
# 📛 Pyroscope is reachable at http://127.0.0.1:4040
# 📊 Grafana is reachable at http://127.0.0.1:3000 (login/password is admin/password) …
```

- **What starts**: `prometheus`, `grafana`, `pyroscope`, `alertmanager`, `node-exporter`, `kafka-lag-exporter`, and a
  JMX exporter agent (port 1234) plus a Pyroscope agent in the broker, controller, connect and schema-registry JVMs.
  Prometheus scrapes the agents every 15 s (jobs `kafka-broker`, `kafka-controller`, `kafka-connect`,
  `schema-registry`, `ksqldb`, `zookeeper`…): the metrics show up in Grafana as soon as the containers are up.
  `playground config open-grafana-in-browser` controls whether Grafana opens at the end of the run.
- **Dashboards** (`/api/search` of Grafana): Confluent Platform overview, Kafka cluster, Kafka Topics, Kafka Quotas,
  Kafka Connect cluster, Schema Registry cluster, ksqlDB cluster, Producers, Consumers, Kafka Lag Exporter,
  Kafka Streams - RocksDb Memory, Cluster Linking, Flink, Zookeeper cluster, and the connector dashboards Confluent
  Oracle CDC, Oracle XStream CDC Monitoring, Debezium Connectors, Mongo connector. Screenshots: [Grafana dashboards](/how-to-use?id=grafana-dashboards).
- **Pyroscope** profiles the CPU of each JVM continuously (`broker.itimer`, `kraft-controller.itimer`,
  `connect.itimer`, `schema-registry.itimer`): the flame graph of a busy broker or task, without a profiler to attach.
- `playground connector benchmark` annotates its measure on the Kafka Connect, connector and Kafka cluster dashboards
  (see [Performance](/toolkit-performance.md)).

**⚠️ Gotchas**

- **`down` targets are normal**: Prometheus scrapes every container an environment can have (`broker2`, `broker3`,
  `connect2`, `ksqldb-server`, `zookeeper`, `jobmanager`…): the ones that are not started stay `down` in
  http://127.0.0.1:9090/targets.
- **KRaft**: the `KafkaController` metrics (active controller, offline partitions, preferred replica imbalance,
  unclean leader elections) come from the `controller` container (job `kafka-controller`), the other panels of the
  Kafka cluster dashboard from the brokers. With ZooKeeper (CP < 8), the active controller is a broker.
- **Producers / Consumers dashboards**: the `kafka-producer` and `kafka-consumer` jobs are commented out in
  `environment/plaintext/prometheus/prometheus.yml`, so standalone clients are not scraped. The consumers and producers
  of the connect worker are (`kafka_consumer_consumer_fetch_manager_metrics_records_lag_max` of a sink, for example).

---

## 5. Control Center: `--enable-control-center`

```bash
playground run -f <example> --enable-control-center        # Control Center Next Gen, http://127.0.0.1:9021
playground run -f <example> --enable-legacy-control-center # the legacy image, CP < 8 only
playground run -f <example> --enable-control-center --control-center-tag <version>
```

- **What starts**: `control-center` (image `confluentinc/cp-enterprise-control-center-next-gen`), `prometheus-c3-v2`
  and `alertmanager-c3-v2` (`confluentinc/cp-enterprise-prometheus` and `cp-enterprise-alertmanager`). Neither of the
  two is published on the host: Control Center is the way in.
- **How it gets broker metrics**: with the flag, the brokers enable their `c3plusplus` telemetry exporter
  (`KAFKA_CONFLUENT_TELEMETRY_EXPORTER_C3PLUSPLUS_ENABLED`, see `determine_c3_telemetry`) and push to
  `prometheus-c3-v2`. To see what Control Center has:

  ```bash
  playground container exec -c prometheus-c3-v2 --shell sh --command "curl -s http://localhost:9090/api/v1/label/__name__/values"
  # … io_confluent_kafka_server_partition_under_replicated, io_confluent_kafka_server_request_channel_request_queue_size,
  # io_confluent_kafka_server_request_handler_pool_request_handler_avg_idle_percent_rate_1_min …
  ```

  (the image has `curl`, not `wget`). Its rules and alerts are evaluated every 60 s (`control-center-v2-config/prometheus.yml`).
- Health+ (Confluent telemetry to Confluent Cloud) is something else: it is turned on when `CONFLUENT_CLOUD_API_KEY`
  and `CONFLUENT_CLOUD_API_SECRET` are set (`docker-compose-telemetry.yml`).
- Examples: [other/control-center-ldap-auth](https://github.com/vdesabou/kafka-docker-playground/tree/master/other/control-center-ldap-auth),
  [other/control-center-readonly-mode](https://github.com/vdesabou/kafka-docker-playground/tree/master/other/control-center-readonly-mode).

---

## 6. Which metric answers which case

| Support question | `broker metrics` row | MBean (`get-jmx-metrics`) | Prometheus (`--enable-jmx-grafana`) / dashboard |
| --- | --- | --- | --- |
| partitions are under-replicated | Under-replicated partitions | `kafka.server:type=ReplicaManager,name=UnderReplicatedPartitions` | `kafka_server_replicamanager_underreplicatedpartitions`, Kafka cluster › Under Replicated Partitions |
| `NotEnoughReplicasException` with `acks=all` | Under min ISR partitions | `kafka.server:type=ReplicaManager,name=UnderMinIsrPartitionCount` | `kafka_server_replicamanager_underminisrpartitioncount`, Kafka cluster › Under Min ISR Partitions |
| replicas keep dropping out of the ISR | ISR shrinks / expands (since start) | `kafka.server:type=ReplicaManager,name=IsrShrinksPerSec` | `kafka_server_replicamanager_isrshrinkspersec`, Kafka cluster › IsrShrinks per Sec |
| the broker is the bottleneck, produce latency is high | Request handler idle (1m), Network processor idle, Request queue size, Produce p99 | `kafka.server:type=KafkaRequestHandlerPool,name=RequestHandlerAvgIdlePercent`, `kafka.network:type=SocketServer,name=NetworkProcessorAvgIdlePercent`, `kafka.network:type=RequestChannel,name=RequestQueueSize`, `kafka.network:type=RequestMetrics,name=TotalTimeMs,request=Produce` | `kafka_server_kafkarequesthandlerpool_requesthandleravgidlepercent`, `kafka_network_socketserver_networkprocessoravgidlepercent`, `kafka_network_requestchannel_requestqueuesize`, `kafka_network_requestmetrics_totaltimems`; Kafka cluster › Thread utilization |
| consumers wait, fetch looks slow | Fetch consumer p99 (500 ms is the default wait, not a problem) | `kafka.network:type=RequestMetrics,name=TotalTimeMs,request=FetchConsumer` | `kafka_network_requestmetrics_totaltimems{request="FetchConsumer"}` |
| how much traffic, which topic | Messages in/s, Bytes in/s, Bytes out/s (`--topic`) | `kafka.server:type=BrokerTopicMetrics,name=MessagesInPerSec` (`,topic=<t>`) | `kafka_server_brokertopicmetrics_messagesinpersec`, Kafka Topics |
| requests fail | Failed produce / fetch requests (since start) | `kafka.server:type=BrokerTopicMetrics,name=FailedProduceRequestsPerSec` | Kafka cluster › Errors |
| no active controller, offline partitions | — | `kafka.controller:type=KafkaController,name=ActiveControllerCount`, `OfflinePartitionsCount` (on `controller` in KRaft) | `kafka_controller_kafkacontroller_activecontrollercount`, `kafka_controller_kafkacontroller_offlinepartitionscount` (job `kafka-controller` in KRaft), Kafka cluster › Active Controllers, Offline Partitions Count |
| a consumer lags | — (`consumer-group describe`) | `kafka.consumer:type=consumer-fetch-manager-metrics,…` (`records-lag-max`) | `kafka_consumer_consumer_fetch_manager_metrics_records_lag_max` (consumers of the connect worker) |
| a connector fails silently, sends to the DLQ | — (`connector metrics`) | `kafka.connect:type=task-error-metrics,connector=<c>,task=<t>` | `kafka_connect_task_error_metrics_deadletterqueue_produce_requests`, `…_total_record_errors`, Kafka Connect cluster |
| long GC pauses, memory | — | `java.lang:type=GarbageCollector,name=*` | `jvm_gc_collection_seconds_sum`, `jvm_memory_bytes_used`, Kafka cluster › Time spent in GC; or `analyze gc-logs` |
| which code burns the CPU | — | — | Pyroscope flame graph of the JVM (`broker.itimer`, `connect.itimer`) |
| Schema Registry is slow or fails requests | — (`schema metrics`: requests/s, 4xx and 5xx errors, p99) | `kafka.schema.registry:type=jersey-metrics` (`http_status_code=5xx` for the server errors) | `kafka_schema_registry_jersey_metrics_request_rate`, `…_request_latency_99`, Schema Registry cluster |
| a ksqlDB query is in ERROR or rebalancing | — (`ksqldb metrics`) | `io.confluent.ksql.metrics:type=_confluent-ksql-<service id>ksql-engine-query-stats` (`ERROR-queries`, `REBALANCING-queries`) | `ksql_ksql_engine_query_stats_error_queries`, ksqlDB cluster |
| the connect workers rebalance in a loop | — (`connector metrics --worker`: rebalances, rebalances per hour, last rebalance) | `kafka.connect:type=connect-coordinator-metrics,client-id=*` | Kafka Connect cluster |

---

## 7. Hands-on lab (≈10 min)

```bash
# Step 1: the playground with the flags (what the lab script does: ENABLE_JMX_GRAFANA=1 ENABLE_CONTROL_CENTER=1 ENABLE_KSQLDB=1)
playground run -f "$PWD/other/deep-dive-labs/observability.sh"
playground status
# … control-center, prometheus-c3-v2, alertmanager-c3-v2, grafana, prometheus, pyroscope, alertmanager, node-exporter, kafka-lag-exporter …

# Step 2: a load, then the digests
playground topic create --topic lab-observability --nb-partitions 3
playground topic produce -t lab-observability --nb-messages 20000 --value '{"id": %g, "name": "name-%g"}'
playground broker metrics --topic lab-observability
# 📈 Broker metrics (rates and failed requests of topic lab-observability)
# METRIC                                 BROKER 1
# Under-replicated partitions            0
# Request handler idle (1m)              …
# Produce p99                            … ms
playground connector metrics --connector filestream-sink
# 📈 Task metrics of 🌎onprem connector filestream-sink (sink, connector RUNNING)
# sent to DLQ           0
# ✅ Nothing stands out: no error, no skipped record, all tasks made progress
playground broker metrics --controller          # 🗳️ Controller metrics (KRaft controllers): Active controller yes
playground connector metrics --worker           # 📈 Connect worker metrics: Connectors 1
playground schema metrics                       # 📈 Schema Registry metrics: Leader yes, Server errors (5xx, total) 0
playground ksqldb metrics                       # 📈 ksqlDB metrics: Persistent queries 1, Queries in ERROR 0 (the lab creates a query)

# Step 3: the MBeans behind them
playground get-jmx-metrics -c broker            # 📚 JMX domains of container broker (no dump without a filter)
playground get-jmx-metrics -c broker --mbean "kafka.server:type=ReplicaManager,*" | grep "^#mbean"
playground get-jmx-metrics -c broker -d "kafka.server kafka.network" | grep "^#mbean" | grep UnderReplicatedPartitions
# #mbean = kafka.server:name=UnderReplicatedPartitions,type=ReplicaManager:
playground get-jmx-metrics -c controller -d kafka.controller | grep "^#mbean" | grep ActiveControllerCount
# #mbean = kafka.controller:name=ActiveControllerCount,type=KafkaController:

# Step 4: Prometheus and Grafana
curl -s localhost:9090/api/v1/targets | jq -r '.data.activeTargets[] | "\(.labels.job) \(.labels.instance) \(.health)"' | sort
# kafka-broker broker2:1234 down          <- not started: normal
# kafka-broker broker:1234 up
# kafka-controller controller:1234 up
# kafka-connect connect:1234 up
# schema-registry schema-registry:1234 up
curl -s localhost:9090/api/v1/query --data-urlencode 'query=kafka_controller_kafkacontroller_activecontrollercount{job=~"kafka-broker|kafka-controller"} > 0' \
  | jq -r '.data.result[] | "\(.metric.instance) \(.value[1])"'
# controller:1234 1                      <- the "Active Controllers" panel: in KRaft, the controller container
curl -s -u admin:password 'localhost:3000/api/search?type=dash-db' | jq -r '.[].title'
# … Kafka cluster, Kafka Connect cluster, Confluent Platform overview …
curl -s localhost:4040/api/apps | jq -r '.[].name'
# broker.itimer, kraft-controller.itimer, schema-registry.itimer, connect.itimer

# Step 5: Control Center and what its Prometheus received
open http://127.0.0.1:9021
playground container exec -c prometheus-c3-v2 --shell sh --command "curl -s http://localhost:9090/api/v1/label/__name__/values"
# … io_confluent_kafka_server_partition_under_replicated …
```

---

## 8. Recipes for support repros

| Customer symptom | Command |
| --- | --- |
| "produce latency went up, is the broker saturated?" | a load (`topic produce --nb-messages 1000000` or `connector benchmark`), then `broker metrics --topic <t>` during it: idle below 30% ⚠️ = threads saturated (`num.io.threads`, `num.network.threads`), request queue size, produce p99. `--enable-jmx-grafana` for the trend (Kafka cluster › Thread utilization) |
| "under-replicated partitions during a broker restart" | `--enable-multiple-brokers --enable-jmx-grafana`, `broker stop --broker 2`, watch Kafka cluster › Under Replicated Partitions and `broker metrics`; see the [brokers deep dive](/deep-dive-broker.md) |
| "which metric should I alert on?" | the table of section 6, then show the value moving: `broker metrics` before and during the failure |
| "Control Center doesn't show my brokers / metrics" | `--enable-control-center`, then `playground container exec -c prometheus-c3-v2 --shell sh --command "curl -s http://localhost:9090/api/v1/label/__name__/values"`: no `io_confluent_kafka_server_*` = the brokers don't send telemetry; `container logs -c control-center --errors` |
| "this Control Center version shows X" | `--enable-control-center --control-center-tag <version>` (Next Gen), `--enable-legacy-control-center --tag <CP < 8>` for the legacy one |
| "the Grafana dashboard is empty" | check http://127.0.0.1:9090/targets: the target of the container must be `up` (`down` is normal for containers that are not started); a client outside the connect worker is not scraped (see the Producers / Consumers gotcha) |
| "the consumer lag grows" | `consumer-group describe --group <g>` (now), `connector show-lag` for a sink, `kafka_consumer_consumer_fetch_manager_metrics_records_lag_max` in Prometheus for the trend of a sink, [offsets and lag](/deep-dive-offsets-and-lag.md) |
| "the broker uses all the CPU" | `--enable-jmx-grafana`, Pyroscope flame graph of `broker.itimer` at http://127.0.0.1:4040; `debug thread-dump -c broker` + `analyze thread-dump` for a snapshot |

---

## 9. Cheat sheet

```bash
playground broker metrics [--broker <id>] [--topic <t>] [--json]
playground connector metrics [--connector <c>] [--watch 10s] [--json]
playground broker metrics --controller [--json]
playground connector metrics --worker [--json]
playground schema metrics [--json]
playground ksqldb metrics [--json]
playground get-jmx-metrics -c <container> [-c <container2>] [--domain "kafka.server kafka.network" | --mbean "<domain>:type=<t>,*" | --all] [--open]
playground run -f <example> --enable-jmx-grafana          # ENABLE_JMX_GRAFANA=1
playground run -f <example> --enable-control-center       # ENABLE_CONTROL_CENTER=1, --control-center-tag <v>
playground run -f <example> --enable-legacy-control-center  # CP < 8
playground config open-grafana-in-browser automatically false
playground connector display-metrics-api | display-metrics-api-with-grafana   # fully managed connectors
```

- URLs: Grafana http://127.0.0.1:3000 (admin / password), Prometheus http://127.0.0.1:9090, Pyroscope
  http://127.0.0.1:4040, Alertmanager http://127.0.0.1:9093, kafka-lag-exporter http://127.0.0.1:9998, Control Center
  http://127.0.0.1:9021.
- JMX ports: broker 10000 (12000, 13000), schema-registry 10001, connect 10002, ksqldb-server 10003, controller 10005.
- On `cfk`, `get-jmx-metrics` works with the pods (JMX 7203, Jolokia 7777, Prometheus exporter 7778).
- Sources: [`environment/plaintext/prometheus/prometheus.yml`](https://github.com/vdesabou/kafka-docker-playground/blob/master/environment/plaintext/prometheus/prometheus.yml),
  [`jmx-exporter/`](https://github.com/vdesabou/kafka-docker-playground/tree/master/environment/plaintext/jmx-exporter),
  [`grafana/provisioning/dashboards/`](https://github.com/vdesabou/kafka-docker-playground/tree/master/environment/plaintext/grafana/provisioning/dashboards),
  [`control-center-v2-config/`](https://github.com/vdesabou/kafka-docker-playground/tree/master/environment/plaintext/control-center-v2-config),
  [`commands/broker/metrics.sh`](https://github.com/vdesabou/kafka-docker-playground/blob/master/scripts/cli/src/commands/broker/metrics.sh).

---

**Links**

- 🧪 Lab: [`other/deep-dive-labs/observability.sh`](https://github.com/vdesabou/kafka-docker-playground/blob/master/other/deep-dive-labs/observability.sh);
  example [`other/monitoring-demo`](https://github.com/vdesabou/kafka-docker-playground/tree/master/other/monitoring-demo)
- 🍪 Deep dives: [brokers and transactions](/deep-dive-broker.md), [`connector diagnose`](/deep-dive-connector-troubleshooting.md),
  [offsets and lag](/deep-dive-offsets-and-lag.md), [JVM diagnostics](/deep-dive-jvm-diagnostics.md),
  [benchmark a connector](/deep-dive-connector-benchmark.md)
- 📖 Confluent docs: [monitoring Kafka with JMX](https://docs.confluent.io/platform/current/kafka/monitoring.html),
  [Control Center](https://docs.confluent.io/control-center/current/overview.html)
- 🧠 CLI reference: [playground broker metrics](/playground%20broker%20metrics), [playground connector metrics](/playground%20connector%20metrics),
  [playground get-jmx-metrics](/playground%20get-jmx-metrics)
