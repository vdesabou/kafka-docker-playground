# 🖥️ Brokers, clients and observability

For cases about **Kafka brokers** (KRaft, replication, transactions, broker failures and upgrades), **Java clients**,
**Control Center** and **metrics**. No connector needed: every command below works on a bare environment, local or
on Confluent Cloud when it says so.

## 🚀 5 commands to try

```bash
# 3 brokers, crash one, rolling restart, an open transaction that blocks read_committed consumers: the whole tour
playground run -f "$PWD/other/broker-health-and-transactions/broker-health-and-transactions.sh"

playground broker health                                   # under-replicated / offline / under min ISR partitions, exits 1 when unhealthy
playground broker describe                                 # brokers, active controller, metadata.version and feature levels
playground broker transactions describe-producers --topic payments   # ⚠️ on the start offset of an open transaction
playground topic dump-log -t payments --partition 0        # what is really in the segment: batches, producers, transaction markers
```

Every broker and replication example: `playground find-example --category broker --limit 50`; clients: `--category client`.

## ❓ Your question, the answer

| Question | Command or example |
| --- | --- |
| Is the cluster healthy? Which partitions are under-replicated, offline, under min ISR? | `playground broker health` (`--wait-healthy --max-wait 300` in a script), `broker describe` |
| A broker goes down, comes back, a rolling upgrade | `--enable-multiple-brokers` on `playground run`, then `broker stop --broker 2` (`--kill` for a crash), `broker start --broker 2`, `broker rolling-restart` |
| `NotEnoughReplicasException` with `acks=all` | `topic create … --replication-factor 3 --config min.insync.replicas=3`, `broker stop --broker 3`, produce with `--producer-property acks=all` |
| The lag of a `read_committed` consumer never drains, an LSO is stuck | `broker transactions list\|describe\|describe-producers\|find-hanging\|abort`; create the situation with `topic produce --transactional-id <id> --transaction open` |
| What is in the log segment? | `playground topic dump-log` (batches, producers, transactions, open transactions) |
| A Java producer / consumer (`kafka-clients`, Avro with `KafkaAvroSerializer`) to start from | [other/client-java](https://github.com/vdesabou/kafka-docker-playground/tree/master/other/client-java), on Confluent Cloud [ccloud/client-java](https://github.com/vdesabou/kafka-docker-playground/tree/master/ccloud/client-java); the other languages: `playground find-example --category client` |
| An old client fails with `UnsupportedVersionException` | `playground broker describe --api-versions --broker 1` |
| Is the broker the bottleneck? | `playground broker metrics` (`--topic <t>`): request handler and network processor idle, request queue, produce p99 |
| Broker configs, dynamic configs, quotas | `playground broker config`, `playground quota` |
| Reassignment, preferred leader election | `playground topic reassign`, `topic elect-leader`, example [other/topic-reassign-and-leader-election](https://github.com/vdesabou/kafka-docker-playground/tree/master/other/topic-reassign-and-leader-election) |
| A producer gets `RecordTooLargeException`, a consumer skips records | `playground topic create\|alter\|describe` with the customer's configs, `topic produce` / `topic consume` with their client properties |
| Consumer groups: lag, members, offsets | `playground consumer-group describe\|reset-offsets` |
| Java producer / consumer with the customer's configs | [other/basic-producer-consumer](https://github.com/vdesabou/kafka-docker-playground/tree/master/other/basic-producer-consumer), `topic produce --producer-property …`, `topic consume --isolation-level\|--partition\|--offset\|--from-timestamp` |
| Latency, packet loss, a broker unreachable | `playground debug degrade-traffic\|block-traffic`, `debug tcp-dump` + `analyze tcp-dump`, `tcp-proxy` |
| A broker JVM is slow, leaks, pauses | `playground debug thread-dump\|heap-dump\|flight-recorder -c broker`, `analyze thread-dump\|gc-logs\|heap-dump\|flight-recorder` (also on the customer's files) |
| Customer log bundle | `playground analyze logs -f <bundle>` |
| Replication between clusters | [multi-data-center/](https://github.com/vdesabou/kafka-docker-playground/tree/master/multi-data-center) (Cluster Linking, Replicator, MirrorMaker 2), `mdc-*` environments |
| Control Center | `--enable-control-center` (Next Gen, http://127.0.0.1:9021), `--enable-legacy-control-center` for CP < 8, `--control-center-tag`, examples [other/control-center-ldap-auth](https://github.com/vdesabou/kafka-docker-playground/tree/master/other/control-center-ldap-auth), [other/control-center-readonly-mode](https://github.com/vdesabou/kafka-docker-playground/tree/master/other/control-center-readonly-mode) |
| Metrics and dashboards | `--enable-jmx-grafana`: Prometheus and Grafana (Kafka cluster, topics, quotas, clients… dashboards), see [Enabling JMX Grafana](/how-to-use?id=📊-enabling-jmx-grafana); example [other/monitoring-demo](https://github.com/vdesabou/kafka-docker-playground/tree/master/other/monitoring-demo) |
| Which CP version changed this? | `--tag` on any run, `playground update-version --tag` on the running environment, `playground cp-changelog --from <version> --grep <symptom>` |
| Run a patched image from engineering | the `CP_KAFKA_IMAGE` / `CP_KAFKA_TAG` variables, see [Overriding Confluent Platform Docker images and tags](/how-to-use?id=🐳-overriding-confluent-platform-docker-images-and-tags) |

## 🍪 Deep dives

- [🖥️ Brokers and transactions](/deep-dive-broker.md): health, failures, rolling restarts, stuck `read_committed` consumers
- [🗂️ Topic administration](/deep-dive-topic-administration.md), [📨 Produce test data](/deep-dive-topic-produce.md), [📥 Read a topic](/deep-dive-topic-consume.md)
- [🌍 Replication between clusters](/deep-dive-replication.md)
- [🐌 A slow or broken network](/deep-dive-network-traffic.md), [🏚 Break one TCP connection](/deep-dive-tcp-proxy.md)
- [🧵 JVM diagnostics](/deep-dive-jvm-diagnostics.md), [🐞 Debugging the JVM](/deep-dive-java-debugging.md)
- [🕹️ Running examples and changing versions](/deep-dive-run-and-versions.md)

## 🎬 Bite size sessions

- [🪛 A producer gets RecordTooLargeException](/sessions?id=🪛-a-producer-gets-recordtoolargeexception)
- [🐌 A slow or broken network, on purpose](/sessions?id=🐌-a-slow-or-broken-network-on-purpose)
- [🧵 Analyze thread dumps](/sessions?id=🧵-a-connector-looks-stuck-analyze-thread-dumps) and [♻️ GC logs](/sessions?id=♻️-long-gc-pauses-or-a-memory-leak-analyze-gc-logs) (the same analyzers work on broker dumps)
- [🎯 Is it fixed in a newer version?](/sessions?id=🎯-is-it-fixed-in-a-newer-version)

## 🧪 A support case in 3 commands

"The lag of our `read_committed` consumer never drains": a transaction stays open and holds the last stable offset.

```bash
playground run -f "$PWD/other/broker-health-and-transactions/broker-health-and-transactions.sh" --tag <customer CP version>

# what the customer's producer did: records in a transaction that never commits
playground topic produce -t orders --nb-messages 10 --value 'order-%g' --transactional-id orders-txn --transaction open --transaction-timeout 900000

# which producer blocks the consumers, and from which offset; find-hanging says whether its coordinator forgot it
playground broker transactions describe-producers --topic orders && playground broker transactions find-hanging --topic orders
```

Then `playground broker transactions abort --topic orders --partition <p> --start-offset <offset>` and
`topic consume -t orders --isolation-level read_committed` to show the fix. Turn it into a reproduction model with
`playground repro bootstrap` (see [🛠 Reproduction models](/toolkit-reproduction-models.md)).
