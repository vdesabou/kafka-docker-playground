# 🌊 Streams, schemas and non-Java clients

For cases about **Schema Registry** (compatibility, subjects and ids, deletion, schema linking, data contracts,
CSFLE), **ksqlDB**, **Flink SQL** (local or Confluent Cloud), **Kafka Streams** and **non-Java clients** (.NET,
JavaScript, Python, Go, Rust, C/C++ librdkafka). Schema Registry comes with every environment, ksqlDB and Flink are one flag away.

## 🚀 5 commands to try

```bash
playground start-environment --environment plaintext       # broker, Schema Registry and Connect, no connector

playground schema check-compatibility --subject orders-value < new-order.avsc   # would the registry accept it? nothing registered
playground schema diff --subject orders-value --to @new-order.avsc              # the verdict of every compatibility rule at once
playground schema history --subject orders-value                                # who relaxed the rule, who deleted what, soft or permanent
playground schema describe --id 3                                               # the schema behind an id seen in a record
```

Every client example: `playground find-example --category client --limit 50`; schema examples: `playground find-example schema --category other`.

## ❓ Your question, the answer

| Question | Command or example |
| --- | --- |
| `Schema being registered is incompatible` | `schema set-compatibility` to the customer's rule, `schema register` their v1, then `schema check-compatibility` and `schema diff --to @<their v2>`: the verdict, its reasons and the field that breaks it |
| `Schema not found` / `Error retrieving Avro schema for id N` after a cleanup | `schema history -f <their _schemas dump>` shows the permanent delete and when; reproduce with `schema delete --subject <s> --permanent` (a soft delete doesn't reproduce it) |
| Which schema is this record using? | `topic consume -t <t> --last 1` for `ValueSchemaId:`, then `schema describe --id <id>` |
| The consumer reads the wrong subject | the subject name strategy of the producer: `schema list`, `topic consume --value-subject <s>` |
| Rebuild the customer's subjects locally, with their ids | `schema import -f <their /schemas dump, _schemas dump or export>`, `schema export` on the other side |
| A schema registered years ago is refused after an upgrade | `schema validate --cp-version <theirs> --cp-version <target> < schema.avsc` |
| Same schema in two registries or two contexts? Schema linking | `schema compare --from <source> --to <destination>`, `schema contexts`, `schema exporter`, example [multi-data-center/schema-linking](https://github.com/vdesabou/kafka-docker-playground/tree/master/multi-data-center/schema-linking) |
| Data contracts: `Rule failed: …`, records in the DLQ of a rule | `schema test-rules --record` with their records, `schema register --rule`, examples [schema-registry/data-contracts](https://github.com/vdesabou/kafka-docker-playground/tree/master/schema-registry/data-contracts), [other/data-contracts](https://github.com/vdesabou/kafka-docker-playground/tree/master/other/data-contracts) |
| CSFLE | [ccloud/connect-csfle-examples](https://github.com/vdesabou/kafka-docker-playground/tree/master/ccloud/connect-csfle-examples) |
| Avro, JSON Schema, Protobuf, references, several event types in a topic | `other/schema-format-*`, [other/schema-references](https://github.com/vdesabou/kafka-docker-playground/tree/master/other/schema-references), [schema-registry/multiple-event-types-in-topic](https://github.com/vdesabou/kafka-docker-playground/tree/master/schema-registry/multiple-event-types-in-topic) |
| Broker-side schema validation, recovery from a hard delete | [other/broker-schema-validation](https://github.com/vdesabou/kafka-docker-playground/tree/master/other/broker-schema-validation), [other/recover-from-schema-hard-deletion](https://github.com/vdesabou/kafka-docker-playground/tree/master/other/recover-from-schema-hard-deletion) |
| Schema Registry security | any secured `--environment`, examples [other/schema-registry-security-plugin](https://github.com/vdesabou/kafka-docker-playground/tree/master/other/schema-registry-security-plugin), [other/rbac-with-sr-basic-auth-acl](https://github.com/vdesabou/kafka-docker-playground/tree/master/other/rbac-with-sr-basic-auth-acl) |
| ksqlDB: joins, windows, tombstones, deserialization errors, schema evolution | `--enable-ksqldb` on any run, `playground ksqldb sql << 'EOF' … EOF`, `ksqldb list\|describe\|wait`, 27 examples in [ksqldb/](https://github.com/vdesabou/kafka-docker-playground/tree/master/ksqldb) |
| Flink SQL against Kafka | local: `--enable-flink`, `playground flink sql\|list-jobs\|cancel`, [flink/flink-sql-kafka](https://github.com/vdesabou/kafka-docker-playground/tree/master/flink/flink-sql-kafka); Confluent Cloud: the same commands with `--environment ccloud`, [ccloud/flink-sql-kafka](https://github.com/vdesabou/kafka-docker-playground/tree/master/ccloud/flink-sql-kafka) |
| Kafka Streams | the Streams app of [other/monitoring-demo](https://github.com/vdesabou/kafka-docker-playground/tree/master/other/monitoring-demo), the `Kafka streams RocksDB` Grafana dashboard (`--enable-jmx-grafana`), `broker transactions` for `exactly_once_v2` apps stuck on an open transaction |
| Non-Java clients: produce, consume, Avro with Schema Registry, with the Confluent client of the customer's language | one example per client, same CLI (`produce\|consume\|produce-avro\|consume-avro <topic> <config file>`): [other/client-c](https://github.com/vdesabou/kafka-docker-playground/tree/master/other/client-c), [other/client-dotnet](https://github.com/vdesabou/kafka-docker-playground/tree/master/other/client-dotnet), [other/client-go](https://github.com/vdesabou/kafka-docker-playground/tree/master/other/client-go), [other/client-javascript](https://github.com/vdesabou/kafka-docker-playground/tree/master/other/client-javascript), [other/client-python](https://github.com/vdesabou/kafka-docker-playground/tree/master/other/client-python), [other/client-rust](https://github.com/vdesabou/kafka-docker-playground/tree/master/other/client-rust), [other/client-kafkajs](https://github.com/vdesabou/kafka-docker-playground/tree/master/other/client-kafkajs); on Confluent Cloud: [ccloud/client-c](https://github.com/vdesabou/kafka-docker-playground/tree/master/ccloud/client-c), [ccloud/client-dotnet](https://github.com/vdesabou/kafka-docker-playground/tree/master/ccloud/client-dotnet), [ccloud/client-go](https://github.com/vdesabou/kafka-docker-playground/tree/master/ccloud/client-go), [ccloud/client-javascript](https://github.com/vdesabou/kafka-docker-playground/tree/master/ccloud/client-javascript), [ccloud/client-python](https://github.com/vdesabou/kafka-docker-playground/tree/master/ccloud/client-python), [ccloud/client-rust](https://github.com/vdesabou/kafka-docker-playground/tree/master/ccloud/client-rust), [ccloud/client-kafkajs](https://github.com/vdesabou/kafka-docker-playground/tree/master/ccloud/client-kafkajs); all of them: `playground find-example --category client` |
| Which version changed this? | `--tag` (Schema Registry and ksqlDB follow it), `--schema-registry-tag`, `--ksqldb-tag`, `playground cp-changelog --from <version> --component schema-registry` |

## 🍪 Deep dives

- [🔰 Schema Registry](/deep-dive-schema.md): subjects, ids, compatibility, deletion, schema linking, data contracts
- [📨 Produce test data](/deep-dive-topic-produce.md): Avro, JSON Schema and Protobuf records, keys, headers, load
- [📥 Read a topic](/deep-dive-topic-consume.md): deserializers, subjects, positioning, assertions
- [🐿️ Flink SQL](/deep-dive-flink.md): run statements, list and cancel jobs, local and Confluent Cloud
- [🧮 ksqlDB](/how-to-use?id=🚀-enabling-ksqldb): run statements, list, describe and wait for queries

## 🎬 Bite size sessions

- [🔰 Schema not found after a cleanup](/sessions?id=🔰-schema-not-found-after-a-cleanup)
- [📨 Produce realistic test data](/sessions?id=📨-produce-realistic-test-data)
- [📥 Read a topic](/sessions?id=📥-read-a-topic)

## 🧪 A support case in 3 commands

"Our producer gets `Schema being registered is incompatible`": register the customer's current version under their
rule, then ask the registry about the new one, without registering anything.

```bash
playground start-environment --environment plaintext

# the customer's rule and their current version (their files)
playground schema set-compatibility --subject orders-value --compatibility BACKWARD && playground schema register --subject orders-value < order-v1.avsc

# the verdict on their new version, and the field that breaks it
playground schema diff --subject orders-value --to @order-v2.avsc
```

Then add a default to the new field, check again with `schema check-compatibility`, and produce both versions with
`topic produce` to show the consumers keep working. Turn it into a reproduction model with `playground repro bootstrap`
(see [🛠 Reproduction models](/toolkit-reproduction-models.md)).
