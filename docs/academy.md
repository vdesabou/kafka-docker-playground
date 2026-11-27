# 🧑‍🎓 Playground Academy

Below is a collection of real issues, each with a reproduction model that you run with the playground. The goal is to let you do the reproduction and the troubleshooting by yourself: this is the only way to learn!

Each exercise (⭐ beginner, ⭐⭐ intermediate, ⭐⭐⭐ advanced) is composed of:

* 🔥 A short description of the issue.
* 🤯 The details: versions, configuration, stack trace, and a link to the reproduction model.
* 📍 A series of steps. The solution of each step is hidden at the beginning of the next one.
* 🎓 Next steps to go further, or 🌟 the results.

The reproduction models live in the [`academy/`](https://github.com/vdesabou/kafka-docker-playground/tree/master/academy) folder. List them with:

```bash
playground find-example --category academy
```

> [!NOTE]
> The outputs shown on this page were recorded with Confluent Platform 8.4.1 (the default version, KRaft only), in November 2026. With another version, logs and outputs may differ slightly.

> [!TIP]
> When a connector fails, the first command to run is [playground connector diagnose](/playground%20connector%20diagnose): status, error digest with the root cause, progress and next steps, in one call. `playground run` already runs it when a connector of the example fails.

## 🗂️ Exercises

| Level | Exercise | What you learn | Main commands |
| --- | --- | --- | --- |
| ⭐ | [Avro Converter: Unknown magic byte](/academy?id=avro-converter-unknown-magic-byte) | a converter error, skip a record, dead letter queue | `connector diagnose`, `connector offsets alter`, `topic dlq inspect` |
| ⭐ | [InsertField SMT: DataException: Only Struct objects supported (sink connector)](/academy?id=insertfield-smt-dataexception-only-struct-objects-supported-sink-connector) | an SMT error, converters vs SMTs | `connector smt test`, `connector update` |
| ⭐ | [InsertField SMT: DataException: Only Struct objects supported (source connector)](/academy?id=insertfield-smt-dataexception-only-struct-objects-supported-source-connector) | SMTs on a source connector | `container logs --grep` |
| ⭐ | [InsertField SMT: adding topic, offset and partition not working](/academy?id=insertfield-smt-adding-topic-offset-and-partition-not-working) | find the failing SMT of a chain | `connector smt test`, `debug log-level` |
| ⭐ | [Broker: a broker never joins the cluster](/academy?id=broker-a-broker-never-joins-the-cluster) | a duplicate `node.id`, what the data folder remembers | `broker health`, `broker describe`, `container logs`, `container recreate --fresh-volumes` |
| ⭐ | [Broker: one broker is rejected by the controllers](/academy?id=broker-one-broker-is-rejected-by-the-controllers) | the cluster id and `meta.properties` | `broker health`, `container logs --errors`, `analyze logs` |
| ⭐ | [Broker: topic creation hangs, but produce works](/academy?id=broker-topic-creation-hangs-but-produce-works) | what needs the KRaft controllers, and what does not | `broker health`, `topic create`, `container restart` |
| ⭐ | [Producer: acks=all fails after a broker crash](/academy?id=producer-acksall-fails-after-a-broker-crash) | `acks=all`, `min.insync.replicas` and the replication factor | `broker health`, `broker stop` / `start`, `topic produce --producer-property acks=all`, `topic reassign` |
| ⭐ | [Producer: slow, without any error](/academy?id=producer-slow-without-any-error) | client quotas, a throttled client | `quota get`, `quota delete`, `topic produce`, `analyze logs` |
| ⭐⭐ | [StackOverflowError with S3 sink connector](/academy?id=stackoverflowerror-with-s3-sink-connector) | bootstrap a reproduction model from a customer config | `repro bootstrap`, `topic produce` |
| ⭐⭐ | [JDBC source: the updated rows never reach the topic](/academy?id=jdbc-source-the-updated-rows-never-reach-the-topic) | the modes of the JDBC source, source offsets | `connector offsets get`, `db sql`, `topic consume` |
| ⭐⭐ | [HTTP sink: tasks.max is 4, but only one task works](/academy?id=http-sink-tasksmax-is-4-but-only-one-task-works) | tasks and partitions, new partitions on a running connector, batching | `connector tasks`, `connector show-lag`, `topic add-partitions` |
| ⭐⭐ | [HTTP sink: the API answers 400, and errors.tolerance doesn't help](/academy?id=http-sink-the-api-answers-400-and-errorstolerance-doesnt-help) | what errors.tolerance covers, retries and error topics of the HTTP sink, replay | `tools http-server requests`, `topic dlq inspect`, `connector offsets reset` |
| ⭐⭐ | [Renamed sink connector writes every row again](/academy?id=renamed-sink-connector-writes-every-row-again) | sink offsets live in a consumer group named after the connector | `consumer-group describe`, `connector offsets alter`, `--initial-state STOPPED` |
| ⭐⭐ | [S3 sink: duplicated records in the bucket after a worker crash](/academy?id=s3-sink-duplicated-records-in-the-bucket-after-a-worker-crash) | when the S3 sink is exactly-once, and when it is not | `storage ls`, `storage cat --summary`, `connector reconcile` |
| ⭐⭐ | [Broker: some records are lost, always for the same partitions](/academy?id=broker-some-records-are-lost-always-for-the-same-partitions) | `listeners` vs `advertised.listeners`, replication | `broker describe`, `broker health`, `topic get-offsets`, `topic describe` |
| ⭐⭐ | [HTTP sink: the same records are sent again and again](/academy?id=http-sink-the-same-records-are-sent-again-and-again) | the poll loop of a sink task, `max.poll.interval.ms` | `connector diagnose`, `connector show-lag`, `tools http-server requests` |
| ⭐⭐⭐ | [JDBC sink RUNNING, but no data in the table](/academy?id=jdbc-sink-running-but-no-data-in-the-table) | a connector stuck without error: lag, thread dumps, database locks | `connector show-lag`, `analyze thread-dump`, `db sql` |
| ⭐⭐⭐ | [JDBC sink: duplicates in the table after a worker crash](/academy?id=jdbc-sink-duplicates-in-the-table-after-a-worker-crash) | at-least-once delivery, idempotent sinks | `connector reconcile`, `container kill` |
| ⭐⭐⭐ | [HTTP sink timeouts: is it the server or the network?](/academy?id=http-sink-timeouts-is-it-the-server-or-the-network) | a slow server or a slow network, timeouts and retries | `tools http-server requests`, `debug tcp-dump`, `debug degrade-traffic` |
| ⭐⭐⭐ | [Debezium PostgreSQL: the connector is RUNNING, the disk of the database fills up](/academy?id=debezium-postgresql-the-connector-is-running-the-disk-of-the-database-fills-up) | replication slots, heartbeats | `db cdc-check`, `connector offsets get`, `db sql` |
| ⭐⭐⭐ | [JDBC sink: an incompatible schema breaks the connector](/academy?id=jdbc-sink-an-incompatible-schema-breaks-the-connector) | compatibility rules, what happens after a bad version got in | `schema history`, `schema diff`, `schema check-compatibility` |
| ⭐⭐⭐ | [Which version of the HTTP sink brought its HTTP logs?](/academy?id=which-version-of-the-http-sink-brought-its-http-logs) | find the version where a behaviour changed | `repro assert`, `repro bisect` |

## ⭐ Beginner

### Avro Converter: Unknown magic byte

<!-- tabs:start -->
#### **🔥 Description**

Sink connector is getting "Unknown magic byte" deserialization error.

💡 What you'll learn:

* Understand a converter issue
* How to skip a record by altering the connector offsets, and what it costs
* Understand the impact of a dead letter queue (DLQ)

#### **🤯 Details**

Versions used:

* 🎯 CP: 8.4.1

* 🔗 FileStream sink: shipped with CP

> [!TIP] Make sure to be aware of default converters used at worker level, see [↔️ Default Connect converter used](/how-it-works?id=%e2%86%94%ef%b8%8f-default-connect-converter-used)

Reproduction model: [filestream-sink-repro-000002-deserialization-error.sh](https://github.com/vdesabou/kafka-docker-playground/blob/master/academy/connect-connect-filestream-sink/filestream-sink-repro-000002-deserialization-error.sh)

#### **📍 Step 1**

Run the example (or type `000002` and use the `fzf` completion of `-f`):

```bash
playground run -f academy/connect-connect-filestream-sink/filestream-sink-repro-000002-deserialization-error.sh
```

As you can see, the connector is failing: `playground run` prints the `connector diagnose` digest, and you can run it again with `playground connector diagnose`.

> [!NOTE]
> [playground connector offsets alter](/playground%20connector%20offsets%20alter), used in Step 3, needs CP 7.6 or later: keep the default version for this exercise.

❔Questions:

* Do you know why it is failing?
* Do you know how it could have been avoided?

#### **📍 Step 2**
<!-- select:start -->
<!-- select-menu-labels: 🙋 See solution for previous step? -->
#### --No--
#### --Yes--

> Do you know why it is failing?

💡 Explanations:

The connector is configured with AvroConverter for the value (default converters are documented [there](/how-it-works?id=%e2%86%94%ef%b8%8f-default-connect-converter-used)):

```json
"value.converter": "io.confluent.connect.avro.AvroConverter",
"value.converter.schema.registry.url": "http://schema-registry:8081"
```

The first 3 records are sent in Avro, as an Avro schema is given to [playground topic produce](/playground%20topic%20produce) (`kafka-avro-console-producer` is used under the hood, and the values are generated from the schema):

```bash
playground topic produce -t filestream --nb-messages 3 --verbose << 'EOF'
{"type":"record","name":"myrecord","fields":[{"name":"u_name","type":"string"},{"name":"u_price", "type": "float"}, {"name":"u_quantity", "type": "int"}]}
EOF
```

This is fine.

But the 4th record is sent without a schema, so plain JSON is sent (`kafka-console-producer` is used under the hood):

```bash
playground topic produce -t filestream --nb-messages 1 --verbose << 'EOF'
{"u_name": "poison pill", "u_price": 1.75, "u_quantity": 1}
EOF
```

This is not Avro, only a plain JSON string: that's what we call a *poison pill*. A 5th record is then sent in Avro again.

The Avro converter fails with `Unknown magic byte` because the 4th record does not start with the magic byte `0` followed by the 4-byte schema ID. The status of the connector (first part of `connector diagnose`) shows the chain of causes:

```log
filestream-sink                ✅ RUNNING  0:🛑 FAILED                   tasks: org.apache.kafka.connect.errors.ConnectException: Tolerance exceeded in error handler
Caused by: org.apache.kafka.connect.errors.DataException: Failed to deserialize data for topic filestream to Avro:
Caused by: org.apache.kafka.common.errors.SerializationException: Error deserializing schema ID
Caused by: java.lang.IllegalArgumentException: Unknown magic byte!
```

> Do you know how it could have been avoided?

One way to avoid this situation is to enable the Confluent feature [Broker-side Schema ID Validation](https://docs.confluent.io/platform/current/schema-registry/schema-validation.html).
If it is set up, the 4th record is rejected by the broker when it is produced.

<!-- select:end -->

* Skip the 4th record (the *poison pill*) by altering the connector offsets

> [!TIP] If you're a Confluent customer, search the Confluent support knowledge base for "How to skip messages in Kafka Connect or reset a connector to the earliest offset for sink connectors"

Here is how you can do it with the CLI:

```bash
# committed offset, log end offset and lag of the sink connector consumer group
playground consumer-group describe --group connect-<connector name>
# open the current offsets in your editor, then apply what you saved (the connector is stopped and resumed around the change)
playground connector offsets alter --connector <connector name>
```

> [!TIP] You can check offset and partition using `playground topic consume`: it skips the records it cannot deserialize and tells you about them

```bash
playground topic consume --topic filestream
13:10:50 ℹ️ ✨ Display content of topic filestream, it contains 5 messages
13:10:50 ℹ️ 🔮🙅 topic is not using any schema for key
13:10:50 ℹ️ 🔮🔰 topic is using avro for value
CreateTime:2026-11-25 13:10:23.837|Partition:0|Offset:0|Headers:NO_HEADERS|Key:null|Value:{"u_name":"Estel","u_price":0.4156215786933899,"u_quantity":1}|ValueSchemaId:1
CreateTime:2026-11-25 13:10:23.843|Partition:0|Offset:1|Headers:NO_HEADERS|Key:null|Value:{"u_name":"Eldon","u_price":0.1185266375541687,"u_quantity":2}|ValueSchemaId:1
CreateTime:2026-11-25 13:10:23.843|Partition:0|Offset:2|Headers:NO_HEADERS|Key:null|Value:{"u_name":"Valentina","u_price":0.2736537456512451,"u_quantity":3}|ValueSchemaId:1
CreateTime:2026-11-25 13:10:31.962|Partition:0|Offset:4|Headers:NO_HEADERS|Key:null|Value:{"u_name":"Stephanie","u_price":0.8598589897155762,"u_quantity":1}|ValueSchemaId:1
13:10:52 ❗ ⚠️ 1 record(s) of topic filestream could not be deserialized and were skipped, first error: org.apache.kafka.common.errors.SerializationException: Error deserializing schema ID (caused by: java.lang.IllegalArgumentException: Unknown magic byte!)
```

The poison pill is at `Partition:0|Offset:3`.

#### **📍 Step 3**
<!-- select:start -->
<!-- select-menu-labels: 🙋 See solution for previous step? -->
#### --No--
#### --Yes--

Check the consumer group of the connector:

```bash
playground consumer-group describe --group connect-filestream-sink
13:56:08 ℹ️ 🔬 Describing consumer group connect-filestream-sink

Consumer group 'connect-filestream-sink' has no active members.
```

There is no committed offset at all: the task fetched the 5 records in one batch, and the batch failed on the 4th record before anything was delivered. So even records 0 to 2 never reached the file.

Alter the offsets of the connector:

```bash
playground connector offsets alter --connector filestream-sink
```

It opens the current offsets in your editor (`{"offsets": []}` here). Set the offset of partition `0` of topic `filestream` to `4`, then save and close the file:

```json
{
  "offsets": [
    {
      "partition": {
        "kafka_topic": "filestream",
        "kafka_partition": 0
      },
      "offset": {
        "kafka_offset": 4
      }
    }
  ]
}
```

The connector is stopped before the change and resumed after it:

```log
{
  "message": "The offsets for this connector have been altered successfully"
}
```

The task is still FAILED: restart the connector now:

```bash
playground connector restart --connector filestream-sink
```

Verify the connector is now running:

```bash
playground connector status
```

Check the data that was processed:

```bash
playground container exec -c connect --command "cat /tmp/output.json"
Struct{u_name=Kendrick,u_price=0.8256663,u_quantity=1}
```

Only the record at offset 4 is in the file (the values are random, yours differ): skipping to offset 4 also skipped records 0 to 2, which were never processed. FileStream is a very basic connector, but the lesson holds for any sink: moving the offset skips every record before it.

<!-- select:end -->
👉 Now add a DLQ and re-run the example

To add a DLQ, add this to the connector config:

```json
"errors.tolerance": "all",
"errors.deadletterqueue.topic.name": "dlq",
"errors.deadletterqueue.topic.replication.factor": "1",
"errors.deadletterqueue.context.headers.enable": "true",
"errors.log.enable": "true",
"errors.log.include.messages": "true",
```

> [!TIP] Edit the `create-or-update` block of the script, then run the example again with `playground re-run`

See the difference in behavior.

> [!TIP] [playground topic dlq inspect](/playground%20topic%20dlq%20inspect) reads a dead letter queue and groups its records by error, with the root cause and the original offsets

#### **📍 Step 4**
<!-- select:start -->
<!-- select-menu-labels: 🙋 See solution for previous step? -->
#### --No--
#### --Yes--

The poison pill goes to the DLQ:

```bash
playground topic dlq inspect --topic dlq
12:57:20 ℹ️ 🩺 Inspecting dead letter queue dlq
12:57:22 ℹ️ 📊 1 records in 1 group(s), most frequent first

🔢 1 record(s) of connector filestream-sink, stage VALUE_CONVERTER (io.confluent.connect.avro.AvroConverter)
  ❌ org.apache.kafka.connect.errors.DataException: Failed to deserialize data for topic filestream to Avro:
  🌱 root cause: java.lang.IllegalArgumentException: Unknown magic byte!
  📍 original records: topic filestream partition 0 offsets 3..3 (1)
  📬 dlq partition 0 offsets 0..0
  🔎 sample value: {"u_name": "poison pill", "u_price": 1.75, "u_quantity": 1}

12:57:22 ℹ️ 🎓 replay them once the cause is fixed: playground topic dlq replay --topic dlq
```

The connector is RUNNING:

```bash
playground connector status
12:57:19 ℹ️ 🧩 Displaying status for 🌎onprem connector filestream-sink
Name                           Status       Tasks                          Stack Trace
-------------------------------------------------------------------------------------------------------------
filestream-sink                ✅ RUNNING  0:🟢 RUNNING                 -
-------------------------------------------------------------------------------------------------------------
```

And this time, the 4 valid records are all in the file:

```bash
playground container exec -c connect --command "cat /tmp/output.json"
Struct{u_name=Bryana,u_price=0.5364906,u_quantity=1}
Struct{u_name=Petra,u_price=0.94601417,u_quantity=2}
Struct{u_name=Luther,u_price=0.24273926,u_quantity=3}
Struct{u_name=Kendrick,u_price=0.8256663,u_quantity=1}
```

Compare with Step 3: altering the offsets lost 3 valid records, the DLQ lost none.

<!-- select:end -->
🥁 So...did you learn about converter issues (Unknown magic byte)?

#### **🎓 Next Steps**

* Read [Kafka Connect Deep Dive – Error Handling and Dead Letter Queues](https://www.confluent.io/en-gb/blog/kafka-connect-deep-dive-error-handling-dead-letter-queues/) and play with different config parameters, and the [🍪 connector diagnose and the dead letter queue](/deep-dive-connector-troubleshooting.md) deep dive.
* Update the example to enable [Broker-side Schema ID Validation](https://docs.confluent.io/platform/current/schema-registry/schema-validation.html). It needs two settings:

  1. the Schema Registry URL on the broker, in the compose override of the model (`docker-compose.plaintext.repro-000002-deserialization-error.yml`):

     ```yml
       broker:
         environment:
           KAFKA_CONFLUENT_SCHEMA_REGISTRY_URL: "http://schema-registry:8081"
     ```

     then [playground container recreate](/playground%20container%20recreate) to apply it and restart the broker;

  2. the validation on the topic, before producing:

     ```bash
     playground topic create --topic filestream --config confluent.value.schema.validation=true
     ```

  The 4th record is then rejected when it is produced.

* `Unknown magic byte` is the Avro error. You can also test with JSON Schema and Protobuf to see the differences in stack traces and error messages.

To produce JSON Schema data, just use [playground topic produce](/playground%20topic%20produce) with a JSON schema (use a new topic!) and make sure to change the connector config with:

```json
"value.converter": "io.confluent.connect.json.JsonSchemaConverter",
"value.converter.schema.registry.url": "http://schema-registry:8081",
```

To produce Protobuf data, just use [playground topic produce](/playground%20topic%20produce) with a Protobuf schema (use a new topic!) and make sure to change the connector config with:

```json
"value.converter": "io.confluent.connect.protobuf.ProtobufConverter",
"value.converter.schema.registry.url": "http://schema-registry:8081",
```

<!-- tabs:end -->



### InsertField SMT: DataException: Only Struct objects supported (sink connector)

<!-- tabs:start -->
#### **🔥 Description**

Sink connector is getting "Only Struct objects supported for [field insertion], found: java.lang.String" SMT error when using [InsertField](https://docs.confluent.io/platform/current/connect/transforms/insertfield.html) SMT.

```bash
org.apache.kafka.connect.errors.DataException: Only Struct objects supported for [field insertion], found: java.lang.String
```

💡 What you'll learn:

* Understand an SMT issue
* Test an SMT chain without a connector
* Understand the impact of a DLQ on an SMT error

#### **🤯 Details**

Versions used:

* 🎯 CP: 8.4.1

* 🔗 FileStream sink: shipped with CP

> [!TIP] Make sure to be aware of default converters used at worker level, see [↔️ Default Connect converter used](/how-it-works?id=%e2%86%94%ef%b8%8f-default-connect-converter-used)

Reproduction model: [filestream-sink-repro-000003-insertfield-smt-dataexception-only-struct-objects-supported.sh](https://github.com/vdesabou/kafka-docker-playground/blob/master/academy/connect-connect-filestream-sink/filestream-sink-repro-000003-insertfield-smt-dataexception-only-struct-objects-supported.sh)

Status of the connector:

```log
filestream-sink                ✅ RUNNING  0:🛑 FAILED                   tasks: org.apache.kafka.connect.errors.ConnectException: Tolerance exceeded in error handler
Caused by: org.apache.kafka.connect.errors.DataException: Only Struct objects supported for [field insertion], found: java.lang.String
```

#### **📍 Step 1**

Run the example (or type `000003` and use the `fzf` completion of `-f`):

```bash
playground run -f academy/connect-connect-filestream-sink/filestream-sink-repro-000003-insertfield-smt-dataexception-only-struct-objects-supported.sh
```

As you can see, the connector is failing (`playground connector diagnose`).

❔Questions:

* Do you know why it is failing?
* Do you know how it could have been avoided?

#### **📍 Step 2**
<!-- select:start -->
<!-- select-menu-labels: 🙋 See solution for previous step? -->
#### --No--
#### --Yes--

> Do you know why it is failing?

💡 Explanations:

The connector is configured with StringConverter for the value:

```json
"value.converter": "org.apache.kafka.connect.storage.StringConverter",
```

The record is sent as plain JSON, as [playground topic produce](/playground%20topic%20produce) is used without a schema (`kafka-console-producer` is used under the hood):

```bash
playground topic produce -t filestream --nb-messages 1 --verbose << 'EOF'
{"customer_name":"Ed", "complaint_type":"Dirty car", "trip_cost": 29.10, "new_customer": false, "number_of_rides": 22}
EOF
```

The InsertField SMT requires a `STRUCT`, but StringConverter creates a `STRING`, hence the issue.

[playground connector smt test](/playground%20connector%20smt%20test) shows it without touching the connector: it runs the chain of the connector on a record of the topic, through its converters:

```bash
playground connector smt test --connector filestream-sink --from-topic filestream --offset 0
🧪 1 transform(s) on a sink record, Kafka 8.4.1-ce (worker confluentinc/cp-server-connect:8.4.1)

step 0  input
        topic     filestream  partition 0  offset 0  timestamp 2026-11-25T11:58:32.291Z
        key       null   (STRING?)
        value     "{\"customer_name\":\"Ed\", \"complaint_type\":\"Dirty car\", \"trip_cost\": 29.10, \"new_customer\": false, \"number_of_rides\": 22}"
        schema    STRING?

step 1  InsertField$Value "InsertField"  (static.value=Kafka Connect framework, static.field=MessageSource)
        from      Kafka 8.4.1-ce (worker)
        ❌ org.apache.kafka.connect.errors.DataException: Only Struct objects supported for [field insertion], found: java.lang.String

❌ the chain stopped at step 1 (--verbose or --json for the stack trace)
```

> Do you know how it could have been avoided?

Use JsonConverter instead, with `schemas.enable=false` (the data in the topic is plain JSON): the value becomes a map that InsertField can update. Try it with `smt test` first, with the converters and the chain in a file (`--config @<file>`):

```bash
cat > /tmp/chain.json << 'EOF'
{
  "value.converter": "org.apache.kafka.connect.json.JsonConverter",
  "value.converter.schemas.enable": "false",
  "transforms": "InsertField",
  "transforms.InsertField.type": "org.apache.kafka.connect.transforms.InsertField$Value",
  "transforms.InsertField.static.field": "MessageSource",
  "transforms.InsertField.static.value": "Kafka Connect framework"
}
EOF
playground connector smt test --config @/tmp/chain.json --from-topic filestream --offset 0
```

```log
step 1  InsertField$Value "InsertField"  (static.field=MessageSource, static.value=Kafka Connect framework)
        from      Kafka 8.4.1-ce (worker)
        value     {"trip_cost":29.1,"MessageSource":"Kafka Connect framework","complaint_type":"Dirty car","customer_name":"Ed","new_customer":false,"number_of_rides":22}

✅ result: topic filestream, key null
```

<!-- select:end -->

👉 Before fixing it, add a DLQ and re-run the example

To add a DLQ, add this to the connector config:

```json
"errors.tolerance": "all",
"errors.deadletterqueue.topic.name": "dlq",
"errors.deadletterqueue.topic.replication.factor": "1",
"errors.deadletterqueue.context.headers.enable": "true",
"errors.log.enable": "true",
"errors.log.include.messages": "true",
```

> [!TIP] Edit the `create-or-update` block of the script, then run the example again with `playground re-run`

See the difference in behavior.

#### **📍 Step 3**
<!-- select:start -->
<!-- select-menu-labels: 🙋 See solution for previous step? -->
#### --No--
#### --Yes--

The record goes to the DLQ, at stage `TRANSFORMATION`:

```bash
playground topic dlq inspect --topic dlq
13:08:58 ℹ️ 🩺 Inspecting dead letter queue dlq
13:09:00 ℹ️ 📊 1 records in 1 group(s), most frequent first

🔢 1 record(s) of connector filestream-sink, stage TRANSFORMATION (org.apache.kafka.connect.runtime.TransformationStage)
  ❌ org.apache.kafka.connect.errors.DataException: Only Struct objects supported for [field insertion], found: java.lang.String
  📍 original records: topic filestream partition 0 offsets 0..0 (1)
  📬 dlq partition 0 offsets 0..0
  🔎 sample value: {"customer_name":"Ed", "complaint_type":"Dirty car", "trip_cost": 29.10, "new_customer": false, "number_of_rides": 22}
```

And the connector is RUNNING:

```bash
playground connector status
13:08:57 ℹ️ 🧩 Displaying status for 🌎onprem connector filestream-sink
Name                           Status       Tasks                          Stack Trace
-------------------------------------------------------------------------------------------------------------
filestream-sink                ✅ RUNNING  0:🟢 RUNNING                 -
-------------------------------------------------------------------------------------------------------------
```

But every record now goes to the DLQ: the DLQ keeps the connector running, it does not fix a configuration error.

<!-- select:end -->
👉 Fix the issue with the right converter, then test InsertField with other [properties](https://docs.confluent.io/platform/current/connect/transforms/insertfield.html#properties):

* topic
* offset
* partition
* timestamp

> [!TIP] [playground connector update](/playground%20connector%20update) opens the config of the running connector in your editor and applies it when you save; `playground connector smt test` tries a chain in seconds before that

#### **📍 Step 4**
<!-- select:start -->
<!-- select-menu-labels: 🙋 See solution for previous step? -->
#### --No--
#### --Yes--

Replace:

```json
"value.converter": "org.apache.kafka.connect.storage.StringConverter",
```

with:

```json
"value.converter": "org.apache.kafka.connect.json.JsonConverter",
"value.converter.schemas.enable": "false",
```

The DLQ run of Step 3 committed the offset of the record, so a connector updated now would not process it again: edit the `create-or-update` block of the script and run the example again with `playground re-run`. The full config (`<< 'EOF'`, quoted, so that `$Value` is not expanded by the shell):

```bash
playground connector create-or-update --connector filestream-sink << 'EOF'
{
     "tasks.max": "1",
     "connector.class": "org.apache.kafka.connect.file.FileStreamSinkConnector",
     "topics": "filestream",
     "file": "/tmp/output.json",
     "key.converter": "org.apache.kafka.connect.storage.StringConverter",
     "value.converter": "org.apache.kafka.connect.json.JsonConverter",
     "value.converter.schemas.enable": "false",
     "transforms": "InsertField",
     "transforms.InsertField.type": "org.apache.kafka.connect.transforms.InsertField$Value",
     "transforms.InsertField.static.field": "MessageSource",
     "transforms.InsertField.static.value": "Kafka Connect framework"
}
EOF
```

> [!NOTE]
> The scripts of the playground use an unquoted `<< EOF`, so that `$AWS_REGION` and other variables are replaced: that is why they write `InsertField\$Value`.

Check the data that was processed:

```bash
playground container exec -c connect --command "cat /tmp/output.json"
{trip_cost=29.1, MessageSource=Kafka Connect framework, complaint_type=Dirty car, customer_name=Ed, new_customer=false, number_of_rides=22}
```

The InsertField SMT worked this time, and the field `MessageSource=Kafka Connect framework` was added.

To insert the topic, offset, partition and timestamp, change the chain of the running connector with [playground connector update](/playground%20connector%20update) (keep JsonConverter!):

```json
"transforms": "InsertTopic,InsertOffset,InsertPartition,InsertTimestamp",
"transforms.InsertOffset.offset.field": "__kafka_offset",
"transforms.InsertOffset.type": "org.apache.kafka.connect.transforms.InsertField$Value",
"transforms.InsertPartition.partition.field": "__kafka_partition",
"transforms.InsertPartition.type": "org.apache.kafka.connect.transforms.InsertField$Value",
"transforms.InsertTimestamp.timestamp.field": "__kafka_ts",
"transforms.InsertTimestamp.type": "org.apache.kafka.connect.transforms.InsertField$Value",
"transforms.InsertTopic.topic.field": "__kafka_topic",
"transforms.InsertTopic.type": "org.apache.kafka.connect.transforms.InsertField$Value",
```

Send one more record:

```bash
playground topic produce -t filestream --nb-messages 1 --verbose << 'EOF'
{"customer_name":"Ed", "complaint_type":"Dirty car", "trip_cost": 29.10, "new_customer": false, "number_of_rides": 22}
EOF
```

Check the output file:

```bash
playground container exec -c connect --command "tail -1 /tmp/output.json"
{__kafka_topic=filestream, __kafka_partition=0, complaint_type=Dirty car, new_customer=false, __kafka_offset=1, __kafka_ts=1795608000610, trip_cost=29.1, customer_name=Ed, number_of_rides=22}
```

<!-- select:end -->
Change the format of the `__kafka_ts` field to make it human readable: instead of a Unix timestamp, use the format `yyyy-MM-dd HH:mm:ss.SSS`

> [!TIP] Use the [TimestampConverter](https://docs.confluent.io/platform/current/connect/transforms/timestampconverter.html#) SMT to do this conversion
> Be careful with the order of the SMTs when you add TimestampConverter!

#### **📍 Step 5**
<!-- select:start -->
<!-- select-menu-labels: 🙋 See solution for previous step? -->
#### --No--
#### --Yes--

Add `TimestampConverter` (you can use any name) at the end of the existing list (or at least after `InsertTimestamp`):

```json
"transforms": "InsertTopic,InsertOffset,InsertPartition,InsertTimestamp,TimestampConverter",
```

And then add:

```json
"transforms.TimestampConverter.type": "org.apache.kafka.connect.transforms.TimestampConverter$Value",
"transforms.TimestampConverter.format": "yyyy-MM-dd HH:mm:ss.SSS",
"transforms.TimestampConverter.target.type": "string",
"transforms.TimestampConverter.field": "__kafka_ts",
```

It converts the field `__kafka_ts` to a string with the format `yyyy-MM-dd HH:mm:ss.SSS`.

Send one more record, then check the output file:

```bash
playground container exec -c connect --command "tail -1 /tmp/output.json"
{__kafka_topic=filestream, __kafka_partition=0, complaint_type=Dirty car, new_customer=false, __kafka_offset=2, __kafka_ts=2026-11-25 12:00:21.255, trip_cost=29.1, customer_name=Ed, number_of_rides=22}
```

As you can see, the date and time are now human readable:

```json
__kafka_ts=2026-11-25 12:00:21.255
```

<!-- select:end -->
🥁 So...did you learn about SMT issues?

#### **🎓 Next Steps**

* Read [🎄 Twelve Days of SMT 🎄 - Day 1: InsertField](https://rmoff.net/2020/12/08/twelve-days-of-smt-day-1-insertfield-timestamp/)
* Read the [🍪 Test a transform chain on a record](/deep-dive-connector-smt-test.md) deep dive, and try other SMTs with `playground connector smt test`

<!-- tabs:end -->

### InsertField SMT: DataException: Only Struct objects supported (source connector)

<!-- tabs:start -->
#### **🔥 Description**

Source connector is getting "Only Struct objects supported for [field insertion], found: java.lang.String" SMT error when using [InsertField](https://docs.confluent.io/platform/current/connect/transforms/insertfield.html) SMT.

```bash
org.apache.kafka.connect.errors.DataException: Only Struct objects supported for [field insertion], found: java.lang.String
```

💡 What you'll learn:

* Understand the difference between source and sink connectors when dealing with an SMT issue.

#### **🤯 Details**

Versions used:

* 🎯 CP: 8.4.1

* 🔗 FileStream source: shipped with CP

> [!TIP] Make sure to be aware of default converters used at worker level, see [↔️ Default Connect converter used](/how-it-works?id=%e2%86%94%ef%b8%8f-default-connect-converter-used)

Reproduction model: [filestream-source-repro-000004-insertfield-smt-dataexception-only-struct-objects-supported.sh](https://github.com/vdesabou/kafka-docker-playground/blob/master/academy/connect-connect-filestream-source/filestream-source-repro-000004-insertfield-smt-dataexception-only-struct-objects-supported.sh)

Status of the connector:

```log
filestream-source              ✅ RUNNING  0:🛑 FAILED                   tasks: org.apache.kafka.connect.errors.ConnectException: Tolerance exceeded in error handler
Caused by: org.apache.kafka.connect.errors.DataException: Only Struct objects supported for [field insertion], found: java.lang.String
```

#### **📍 Step 1**

Run the example (or type `000004` and use the `fzf` completion of `-f`):

```bash
playground run -f academy/connect-connect-filestream-source/filestream-source-repro-000004-insertfield-smt-dataexception-only-struct-objects-supported.sh
```

As you can see, the connector is failing (`playground connector diagnose`).

❔Questions:

* Do you know why it is failing?
* Do you know how it could have been avoided?

#### **📍 Step 2**
<!-- select:start -->
<!-- select-menu-labels: 🙋 See solution for previous step? -->
#### --No--
#### --Yes--

> Do you know why it is failing?

💡 Explanations:

The connector is configured with JsonConverter for the value, which was the way to fix the problem in the sink example:

```json
"value.converter": "org.apache.kafka.connect.json.JsonConverter",
"value.converter.schemas.enable": "false",
```

The connector is still failing...

The InsertField SMT requires a `STRUCT`, but here the logic of the FileStream connector creates the record with a schema that is just a `STRING`, not a `STRUCT`. The connector has `errors.log.enable` and `errors.log.include.messages`, so the failing record is logged:

```bash
playground container logs -c connect --grep "Executing stage 'TRANSFORMATION'" --no-follow
```

```log
ERROR [filestream-source|task-0] Error encountered in task filestream-source-0. Executing stage 'TRANSFORMATION' with class 'org.apache.kafka.connect.runtime.TransformationStage', where source record is = SourceRecord{sourcePartition={filename=/tmp/kafka-connect/examples/file.json}, sourceOffset={position=232}} ConnectRecord{topic='filestream', kafkaPartition=null, key=null, keySchema=null, value={"id":1,"first_name":"Florance","last_name":"Probet",...}, valueSchema=Schema{STRING}, ...}
org.apache.kafka.connect.errors.DataException: Only Struct objects supported for [field insertion], found: java.lang.String
```

Note `valueSchema=Schema{STRING}`.

> Do you know how it could have been avoided?

You can't avoid it with this connector: it only creates records with a STRING schema.

As you can see below, for a source connector, the SMT is applied after the connector logic, so nothing can be done: the record does not meet the requirements of the InsertField SMT.

![SMT](./images/SMT.jpg)

Please also note that the converter is called after the SMTs, so for a source connector it plays no role here (as opposed to sink connectors).

<!-- select:end -->
🥁 So...did you learn about SMT issues and the difference between source and sink connectors?

#### **🎓 Next Steps**

* Run an example with a connector that creates records with a STRUCT, for example the JDBC source, then use InsertField and make sure it works as expected (that is the next exercise).

<!-- tabs:end -->

### InsertField SMT: adding topic, offset and partition not working

<!-- tabs:start -->
#### **🔥 Description**

When using [InsertField](https://docs.confluent.io/platform/current/connect/transforms/insertfield.html) SMT to add topic, offset and partition with a source connector, it does not work as expected.

💡 What you'll learn:

* Understand the difference between source and sink connectors when dealing with an SMT issue.
* Find which SMT of a chain fails.

#### **🤯 Details**

Versions used:

* 🎯 CP: 8.4.1

* 🔗 JDBC source (MySQL): 10.9.10

> [!TIP] Make sure to be aware of default converters used at worker level, see [↔️ Default Connect converter used](/how-it-works?id=%e2%86%94%ef%b8%8f-default-connect-converter-used)

Reproduction model: [mysql-repro-000005-insertfield-smt:-adding-topic-offset-and-partition-not-working.sh](https://github.com/vdesabou/kafka-docker-playground/blob/master/academy/connect-connect-jdbc-mysql-source/mysql-repro-000005-insertfield-smt:-adding-topic-offset-and-partition-not-working.sh)

Status of the connector:

```log
mysql-source                   ✅ RUNNING  0:🛑 FAILED                   tasks: org.apache.kafka.connect.errors.ConnectException: Tolerance exceeded in error handler
Caused by: org.apache.kafka.connect.errors.DataException: Only SinkRecord supported for [field insertion], found: org.apache.kafka.connect.source.SourceRecord
```

#### **📍 Step 1**

Run the example (or type `000005` and use the `fzf` completion of `-f`):

```bash
playground run -f "academy/connect-connect-jdbc-mysql-source/mysql-repro-000005-insertfield-smt:-adding-topic-offset-and-partition-not-working.sh"
```

As you can see, the connector is failing (`playground connector diagnose`).

❔Questions:

* Do you know why it is failing?

#### **📍 Step 2**
<!-- select:start -->
<!-- select-menu-labels: 🙋 See solution for previous step? -->
#### --No--
#### --Yes--

> Do you know why it is failing?

💡 Explanations:

The connector is configured with the same SMTs as the sink connector example [there](/academy?id=insertfield-smt-dataexception-only-struct-objects-supported-sink-connector):

```json
"transforms": "InsertTopic,InsertOffset,InsertPartition,InsertTimestamp,TimestampConverter",
"transforms.InsertOffset.offset.field": "__kafka_offset",
"transforms.InsertOffset.type": "org.apache.kafka.connect.transforms.InsertField$Value",
"transforms.InsertPartition.partition.field": "__kafka_partition",
"transforms.InsertPartition.type": "org.apache.kafka.connect.transforms.InsertField$Value",
"transforms.InsertTimestamp.timestamp.field": "__kafka_ts",
"transforms.InsertTimestamp.type": "org.apache.kafka.connect.transforms.InsertField$Value",
"transforms.InsertTopic.topic.field": "__kafka_topic",
"transforms.InsertTopic.type": "org.apache.kafka.connect.transforms.InsertField$Value",
"transforms.TimestampConverter.type": "org.apache.kafka.connect.transforms.TimestampConverter$Value",
"transforms.TimestampConverter.format": "yyyy-MM-dd HH:mm:ss.SSS",
"transforms.TimestampConverter.target.type": "string",
"transforms.TimestampConverter.field": "__kafka_ts"
```

The connector is failing with `Only SinkRecord supported for [field insertion], found: org.apache.kafka.connect.source.SourceRecord`, but 4 SMTs of the chain are InsertField: which one fails?

The fastest way: [playground connector smt test](/playground%20connector%20smt%20test) runs the chain of the connector step by step, on a source record (it uses the type of `--connector`):

```bash
playground connector smt test --connector mysql-source --record '{"topic":"mysql-team","value":{"id":102,"name":"another"}}'
🧪 2 transform(s) on a source record, Kafka 8.4.1-ce (worker confluentinc/cp-server-connect:8.4.1)

step 0  input
        topic     mysql-team  partition 0  timestamp 2026-11-25T12:03:19.465Z
        key       null   (schemaless)
        value     {"name":"another","id":102}
        schema    schemaless

step 1  InsertField$Value "InsertTopic"  (topic.field=__kafka_topic)
        from      Kafka 8.4.1-ce (worker)
        value     {"name":"another","__kafka_topic":"mysql-team","id":102}

step 2  InsertField$Value "InsertOffset"  (offset.field=__kafka_offset)
        from      Kafka 8.4.1-ce (worker)
        ❌ org.apache.kafka.connect.errors.DataException: Only SinkRecord supported for [field insertion], found: org.apache.kafka.connect.source.SourceRecord

❌ the chain stopped at step 2 (--verbose or --json for the stack trace)
```

The other way, in the logs of the running connector: set TRACE on `org.apache.kafka.connect.runtime.TransformationChain`, which logs each record before each SMT (the model already does it):

```bash
playground debug log-level set --package "org.apache.kafka.connect.runtime.TransformationChain" --level TRACE
```

[playground connector log-level](/playground%20connector%20log-level) `--level TRACE` sets it too (with the logger of the connector), and so does `--level` of [playground connector create-or-update](/playground%20connector%20create-or-update):

```bash
playground connector create-or-update --connector mysql-source --level TRACE
```

We then see in the logs:

```log
TRACE [mysql-source|task-0] Applying transformation org.apache.kafka.connect.transforms.InsertField$Value to SourceRecord{...} ConnectRecord{topic='mysql-team', kafkaPartition=null, key=null, keySchema=null, value=Struct{id=1,name=kafka,email=kafka@apache.org,last_modified=2026-11-25 12:02:45.0}, valueSchema=Schema{team:STRUCT}, timestamp=null, ...}
TRACE [mysql-source|task-0] Applying transformation org.apache.kafka.connect.transforms.InsertField$Value to SourceRecord{...} ConnectRecord{topic='mysql-team', kafkaPartition=null, key=null, keySchema=null, value=Struct{id=1,name=kafka,email=kafka@apache.org,last_modified=2026-11-25 12:02:45.0,__kafka_topic=mysql-team}, valueSchema=Schema{team:STRUCT}, timestamp=null, ...}
```

The second SMT received the record with `__kafka_topic` already set, then the task failed: it fails at the 2nd SMT in the list, which is `InsertOffset`.

<!-- select:end -->

Remove the `InsertOffset` SMT and see if that fixes the problem

#### **📍 Step 3**
<!-- select:start -->
<!-- select-menu-labels: 🙋 See solution for previous step? -->
#### --No--
#### --Yes--

After removing `InsertOffset`:

```json
"transforms": "InsertTopic,InsertPartition,InsertTimestamp,TimestampConverter",
"transforms.InsertPartition.partition.field": "__kafka_partition",
"transforms.InsertPartition.type": "org.apache.kafka.connect.transforms.InsertField$Value",
"transforms.InsertTimestamp.timestamp.field": "__kafka_ts",
"transforms.InsertTimestamp.type": "org.apache.kafka.connect.transforms.InsertField$Value",
"transforms.InsertTopic.topic.field": "__kafka_topic",
"transforms.InsertTopic.type": "org.apache.kafka.connect.transforms.InsertField$Value",
"transforms.TimestampConverter.type": "org.apache.kafka.connect.transforms.TimestampConverter$Value",
"transforms.TimestampConverter.format": "yyyy-MM-dd HH:mm:ss.SSS",
"transforms.TimestampConverter.target.type": "string",
"transforms.TimestampConverter.field": "__kafka_ts"
```

The connector is no longer failing.

<!-- select:end -->

Check the content of the topic with `playground topic consume --topic mysql-team`

Does that work as you would expect?

#### **📍 Step 4**
<!-- select:start -->
<!-- select-menu-labels: 🙋 See solution for previous step? -->
#### --No--
#### --Yes--

> Does that work as you would expect?

The value of the records is:

```json
{
  "id": 101,
  "name": "another",
  "email": "another@apache.org",
  "last_modified": 1795608165000,
  "__kafka_topic": {
    "string": "mysql-team"
  },
  "__kafka_partition": null,
  "__kafka_ts": null
}
```

`__kafka_topic` is set, but not `__kafka_partition` and `__kafka_ts`.

As you can see below, for a source connector, the SMT is applied after the connector logic and before the record is sent to the Kafka topic: the partition and the timestamp of the record are not known yet, so `null` values are expected.

![SMT](./images/SMT.jpg)

N.B: the `offset` property fails with `Only SinkRecord supported for [field insertion], found: org.apache.kafka.connect.source.SourceRecord`, which makes sense. The same check could have been added for `partition` and `timestamp`, but it is not the case.

<!-- select:end -->

🥁 So...did you learn why InsertField does not set some fields with source connectors?

<!-- tabs:end -->


### Broker: a broker never joins the cluster

<!-- tabs:start -->
#### **🔥 Description**

A customer adds a third broker by copying the configuration of the second one. It starts, logs nothing at ERROR for a
minute, then exits and is restarted by its service manager, again and again.

💡 What you'll learn:

* Read a broker that does not start: its log, `playground broker health` and `playground broker describe`
* Why `node.id` must be unique, and what the controllers do with a duplicate
* Why fixing the configuration is not enough: the data folder remembers the node id

#### **🤯 Details**

Versions used:

* 🎯 CP: 8.4.1 (KRaft: CP 8 or later)

* 🖥️ 3 brokers (ids 1, 2 and 3), 1 controller (id 4)

Reproduction model: [broker-repro-000017-broker-never-joins-duplicate-node-id.sh](https://github.com/vdesabou/kafka-docker-playground/blob/master/academy/environment-plaintext/broker-repro-000017-broker-never-joins-duplicate-node-id.sh)

#### **📍 Step 1**

Run the example (or type `000017` and use the `fzf` completion of `-f`):

```bash
playground run -f academy/environment-plaintext/broker-repro-000017-broker-never-joins-duplicate-node-id.sh
```

The example ends with `playground broker health`:

```bash
18:23:43 ℹ️ 🩺 Health of the cluster
18:23:43 ℹ️ 🖥️ registered brokers: 1,2
18:23:43 🔥 ❌ containers broker2 and broker3 have the same node id 2: only one of them is registered, the other retries then exits (DUPLICATE_BROKER_REGISTRATION or /brokers/ids/2 already exists in its log: playground container logs -c <container> --errors)
18:23:43 ℹ️ ✅ no under-replicated partition
18:23:43 ℹ️ ✅ no under min.insync.replicas partition
18:23:43 ℹ️ ✅ no unavailable (no leader) partition
18:23:43 ℹ️ 🗳️ KRaft quorum: leader is node 4
NODE  STATUS    LOG_END_OFFSET  LAG  LAST_CAUGHT_UP
4     Leader    235             0    0s ago
2     Observer  235             0    0s ago
1     Observer  235             0    0s ago
2     Observer  235             0    0s ago
18:23:43 🔥 ❌ cluster is not healthy: brokers with the same node id: 2
```

❔Questions:

* Which container is not part of the cluster, and what does its log say?
* Why is node `2` listed twice in the KRaft quorum?

#### **📍 Step 2**
<!-- select:start -->
<!-- select-menu-labels: 🙋 See solution for previous step? -->
#### --No--
#### --Yes--

> Which container is not part of the cluster, and what does its log say?

[playground broker describe](/playground%20broker%20describe) shows that one registered broker 2 is behind two containers:

```bash
playground broker describe
18:24:15 ℹ️ 🖥️ Brokers (CP 8.4.1)
ID  ENDPOINT      RACK  FENCED  CONTAINER
1   broker:9092   null  false   broker
2   broker2:9092  null  false   broker2,broker3 ⚠️ same node id
18:24:16 ℹ️ 🗳️ KRaft
Cluster id:            MkU3OEVBNTcwNTJENDM2Qk
Active controller:     4 (epoch 1)
Voters (controllers):  4
Observers (brokers):   1,2,2
```

The compose override of the model sets the node id of `broker3` to `2`, copied from `broker2`:

```yml
  broker3:
    # the new broker is added to the running cluster: it starts 30 seconds after the others
    command: bash -c "sleep 30 && exec /etc/confluent/docker/run"
    environment:
      # 💥 copied from broker2 and not changed
      KAFKA_NODE_ID: 2
      KAFKA_BROKER_ID: 2
```

Started at the same time, either `broker2` or `broker3` would be the one left out: the first one to register wins.

The full log of `broker3` (`playground container logs -c broker3 --no-follow`) has the reason, at **INFO** level, every 2 seconds:

```log
[2026-11-26 17:21:55,751] INFO [BrokerLifecycleManager id=2] Unable to register broker 2 because the controller returned error DUPLICATE_BROKER_REGISTRATION (org.apache.kafka.server.BrokerLifecycleManager)
[2026-11-26 17:21:57,760] INFO [BrokerLifecycleManager id=2] Unable to register broker 2 because the controller returned error DUPLICATE_BROKER_REGISTRATION (org.apache.kafka.server.BrokerLifecycleManager)
```

Being INFO, it is not in `playground container logs -c broker3 --errors`, which only shows what happens 60 seconds later
(`initial.broker.registration.timeout.ms`), when the broker gives up:

```log
[2026-11-26 17:22:55,544] ERROR [BrokerLifecycleManager id=2] Shutting down because we were unable to register with the controller quorum. (org.apache.kafka.server.BrokerLifecycleManager)
[2026-11-26 17:22:55,554] ERROR [BrokerServer id=2] Fatal error during broker startup. Prepare to shutdown (kafka.server.BrokerServer)
    java.lang.RuntimeException: Received a fatal error while waiting for broker metadata to catch up
```

[playground analyze logs](/playground%20analyze%20logs) on that log names the known cause, and tells you to look at the INFO lines just before:

```log
[CRITICAL] 📝 Broker could not register with the KRaft controllers
```

> Why is node `2` listed twice in the KRaft quorum?

Both processes with node id 2 fetch the metadata log from the controller, as observers: the controller sees two
directories (`DirectoryId`) for the same node id, but registers only the first broker that asked.

<!-- select:end -->

* Fix the node id of `broker3` in the compose override of the model (`docker-compose.plaintext.repro-000017-broker-never-joins-duplicate-node-id.yml`), then apply it with [playground container recreate](/playground%20container%20recreate). Is `broker3` part of the cluster now?

#### **📍 Step 3**
<!-- select:start -->
<!-- select-menu-labels: 🙋 See solution for previous step? -->
#### --No--
#### --Yes--

With `KAFKA_NODE_ID: 3` and `KAFKA_BROKER_ID: 3`, `playground container recreate` starts a new `broker3` container,
and it still does not join. Its log:

```log
Exception in thread "main" java.lang.RuntimeException: Stored node id 2 doesn't match previous node id 3 in /var/lib/kafka/data/meta.properties. If you moved your data, make sure your configured node id matches. If you intend to create a new node, you should remove all data in your data directories.
```

The first start wrote the node id in `meta.properties`, in the data folder (`log.dirs`). A recreated container keeps
its volumes, so the data folder is still the one of "node 2". On a real cluster this is what protects you from
starting a broker on the disk of another one.

The data folder of the new node must be emptied: [playground container recreate](/playground%20container%20recreate) `--fresh-volumes broker3` removes the container and its anonymous volumes first, and the image formats the empty folder again:

```bash
playground container recreate --fresh-volumes broker3
18:27:54 ℹ️ 🧽 removing container broker3 and its anonymous volumes (/etc/kafka/secrets /var/lib/kafka/data): it starts with empty data folders
18:27:54 ℹ️ 💫 Recreate container(s)
playground broker health --wait-healthy
18:28:13 ℹ️ ✅ all brokers are registered: 1,2,3
18:28:13 ℹ️ ✅ cluster is healthy
```

<!-- select:end -->
🥁 So...did you learn why every node needs its own `node.id`, and its own data folder?

#### **🎓 Next Steps**

* In ZooKeeper mode (CP 7.x), the same mistake fails at once: `Error while creating ephemeral at /brokers/ids/2, node already exists`.
* Try the [🍪 brokers and transactions](/deep-dive-broker.md) deep dive: `broker health`, `broker stop` / `start`, `rolling-restart`.

<!-- tabs:end -->

### Broker: one broker is rejected by the controllers

<!-- tabs:start -->
#### **🔥 Description**

A broker runs, but never shows up in the cluster. Its log is flooded with `INCONSISTENT_CLUSTER_ID` errors, several per second.

💡 What you'll learn:

* What the cluster id is, where it is stored, and who checks it
* How a node ends up with another cluster id
* How to bring it back without touching the other nodes

#### **🤯 Details**

Versions used:

* 🎯 CP: 8.4.1 (KRaft: CP 8 or later)

* 🖥️ 3 brokers (ids 1, 2 and 3), 1 controller (id 4)

Reproduction model: [broker-repro-000018-broker-rejected-inconsistent-cluster-id.sh](https://github.com/vdesabou/kafka-docker-playground/blob/master/academy/environment-plaintext/broker-repro-000018-broker-rejected-inconsistent-cluster-id.sh)

#### **📍 Step 1**

Run the example:

```bash
playground run -f academy/environment-plaintext/broker-repro-000018-broker-rejected-inconsistent-cluster-id.sh
```

```bash
18:29:00 ℹ️ 🩺 Health of the cluster
18:29:00 ℹ️ 🖥️ registered brokers: 1,2
18:29:00 🔥 ❌ broker 3 (container broker3) is not registered: still starting? (playground container logs -c broker3 --errors)
18:29:00 ℹ️ 🗳️ KRaft quorum: leader is node 4
NODE  STATUS    LOG_END_OFFSET  LAG  LAST_CAUGHT_UP
4     Leader    44              0    0s ago
2     Observer  44              0    0s ago
1     Observer  44              0    0s ago
18:29:00 🔥 ❌ cluster is not healthy: brokers down: 3
```

❔Questions:

* Why is broker 3 not even an observer of the quorum?
* Where does each node get its cluster id from?

#### **📍 Step 2**
<!-- select:start -->
<!-- select-menu-labels: 🙋 See solution for previous step? -->
#### --No--
#### --Yes--

> Why is broker 3 not even an observer of the quorum?

```bash
playground container logs -c broker3 --errors
```

```log
[2026-11-26 17:29:09,687] ERROR [RaftManager id=3] Unexpected error INCONSISTENT_CLUSTER_ID in FETCH response: InboundResponse(correlationId=1037, data=FetchResponseData(throttleTimeMs=0, errorCode=104, sessionId=0, responses=[], …
```

Every fetch of the metadata log is refused by the controller: the request carries a cluster id that is not the one of
the controller. [playground analyze logs](/playground%20analyze%20logs) on that log: `[CRITICAL] 🆔 Cluster id mismatch ×1034`.

> Where does each node get its cluster id from?

From its data folder: `kafka-storage format -t <cluster id>` writes it in `meta.properties` before the first start
(the Confluent images run it with the `CLUSTER_ID` environment variable). All the nodes must be formatted with the
same id. The compose override of the model formatted `broker3` with its own:

```yml
  broker3:
    environment:
      # 💥 formatted with its own cluster id (kafka-storage random-uuid run again for this node)
      CLUSTER_ID: 'q1Sh-9_ISia_zwGINzRvyQ'
```

The usual way to get there on a real cluster: running `kafka-storage random-uuid` once per node instead of once per cluster.

<!-- select:end -->

* Put back the cluster id of the other nodes (`MkU3OEVBNTcwNTJENDM2Qk`, see `playground broker describe`) in the override, and apply it.

#### **📍 Step 3**
<!-- select:start -->
<!-- select-menu-labels: 🙋 See solution for previous step? -->
#### --No--
#### --Yes--

After `playground container recreate`, `broker3` exits at once:

```log
Exception in thread "main" java.lang.RuntimeException: Invalid cluster.id in: /var/lib/kafka/data/meta.properties. Expected MkU3OEVBNTcwNTJENDM2Qk, but read q1Sh-9_ISia_zwGINzRvyQ
```

As in the previous exercise, the data folder remembers: it was formatted with the wrong id. This node holds no data
yet, so it can start from an empty folder:

```bash
playground container recreate --fresh-volumes broker3
playground broker health --wait-healthy
18:31:33 ℹ️ ✅ cluster is healthy
```

> [!WARNING]
> On a production cluster, never "fix" a cluster id by formatting a node that holds data: find out which side is
> right first. The same message in ZooKeeper mode (`Invalid cluster.id … meta.properties`) usually means ZooKeeper was
> rebuilt or wiped while the brokers kept their data.

<!-- select:end -->
🥁 So...did you learn where the cluster id lives?

#### **🎓 Next Steps**

* Compare `cluster.id` in the `meta.properties` of each node: `playground container exec -c broker2 --command "cat /var/lib/kafka/data/meta.properties"`.

<!-- tabs:end -->

### Broker: topic creation hangs, but produce works

<!-- tabs:start -->
#### **🔥 Description**

The application team cannot create a topic: `kafka-topics --create` hangs for a minute and times out. Yet the
existing applications produce and consume without any error.

💡 What you'll learn:

* What the KRaft controllers do, and what still works without them
* Why a quorum of 3 controllers survives one failure, not two

#### **🤯 Details**

Versions used:

* 🎯 CP: 8.4.1 (KRaft: CP 8 or later)

* 🖥️ 3 brokers (ids 1, 2 and 3), 3 controllers (ids 4, 5 and 6)

Reproduction model: [broker-repro-000020-topic-creation-hangs-produce-works.sh](https://github.com/vdesabou/kafka-docker-playground/blob/master/academy/environment-plaintext/broker-repro-000020-topic-creation-hangs-produce-works.sh)

#### **📍 Step 1**

Run the example:

```bash
playground run -f academy/environment-plaintext/broker-repro-000020-topic-creation-hangs-produce-works.sh
```

The 5 payments are written:

```bash
18:43:41 ℹ️ 📍 Earliest and latest offsets per partition of topic payments
PARTITION  EARLIEST        LATEST          RECORDS
0          0               0               0
1          0               0               0
2          0               5               5
TOTAL                                      5
```

But the new topic is not created, a minute later:

```bash
18:44:46 ℹ️ 🆕 Creating topic refunds
Error while executing topic command : Call(callName=createTopics, deadlineMs=1795715147372, tries=1, nextAllowedTryMs=1795715147515) timed out at 1795715147408 after 1 attempt(s)
Caused by: org.apache.kafka.common.errors.DisconnectException: Cancelled createTopics request with correlation id 3 due to node 2 being disconnected
```

❔Questions:

* What is different between producing to `payments` and creating `refunds`?
* What does `playground broker health` say?

#### **📍 Step 2**
<!-- select:start -->
<!-- select-menu-labels: 🙋 See solution for previous step? -->
#### --No--
#### --Yes--

> What does `playground broker health` say?

```bash
playground broker health
18:47:50 ℹ️ 🩺 Health of the cluster
18:47:50 ℹ️ 🖥️ registered brokers: 1,2,3
18:47:50 🔥 ❌ KRaft quorum lost: 1 of 3 controllers running (controller2, controller3 stopped): no majority, so no active controller
18:47:50 🔥    metadata changes wait and time out (topic creation, leader election, a broker that restarts cannot register), produce and consume keep working on the current leaders
```

> What is different between producing to `payments` and creating `refunds`?

Producing only needs the leaders of the partitions, which the brokers already know: the brokers serve the data on
their own. Creating a topic is a **metadata change**: it is written to the metadata log by the active controller, and
the controllers elect one only with a majority of the voters (2 of 3). With one controller left, there is no active
controller, so every metadata change waits and gives up: topic creation, but also a new leader when a broker stops,
or a broker that restarts and needs to register. The cluster looks fine until one of those happens.

<!-- select:end -->

* Bring the controllers back, and create the topic again.

#### **📍 Step 3**
<!-- select:start -->
<!-- select-menu-labels: 🙋 See solution for previous step? -->
#### --No--
#### --Yes--

```bash
playground container restart -c controller2 -c controller3
playground broker health --wait-healthy
18:48:17 ℹ️ 🗳️ KRaft quorum: leader is node 4
NODE  STATUS    LOG_END_OFFSET  LAG  LAST_CAUGHT_UP
4     Leader    258             0    0s ago
5     Follower  258             0    0s ago
6     Follower  258             0    0s ago
3     Observer  258             0    0s ago
1     Observer  258             0    0s ago
2     Observer  258             0    0s ago
18:48:17 ℹ️ ✅ cluster is healthy
playground topic create --topic refunds --nb-partitions 3 --replication-factor 3
Created topic refunds.
```

<!-- select:end -->
🥁 So...did you learn what needs the controllers, and what does not?

#### **🎓 Next Steps**

* Stop only one controller: is the cluster still able to create a topic? Stop the active one (`Leader` in the KRaft quorum table): how long does the election take?
* The same lesson holds for a ZooKeeper ensemble (CP 7.x): without a majority of its nodes, produce keeps working and topic creation fails.

<!-- tabs:end -->


### Producer: acks=all fails after a broker crash

<!-- tabs:start -->
#### **🔥 Description**

During the night, one of the three brokers crashed. Since then, the payment service fails to send some payments with
`NotEnoughReplicasException`, but not all of them. The other topics are fine.

💡 What you'll learn:

* What `acks=all` and `min.insync.replicas` promise together
* Why a replication factor equal to `min.insync.replicas` tolerates no broker failure
* Why only some partitions fail

#### **🤯 Details**

Versions used:

* 🎯 CP: 8.4.1 (KRaft: CP 8 or later)

* 🖥️ 3 brokers (ids 1, 2 and 3)

Reproduction model: [broker-repro-000021-acks-all-not-enough-replicas.sh](https://github.com/vdesabou/kafka-docker-playground/blob/master/academy/environment-plaintext/broker-repro-000021-acks-all-not-enough-replicas.sh)

#### **📍 Step 1**

Run the example:

```bash
playground run -f academy/environment-plaintext/broker-repro-000021-acks-all-not-enough-replicas.sh
```

The producer retries, then gives up for 5 of the 9 records:

```log
[2026-11-26 18:19:15,555] WARN [Producer clientId=console-producer] Got error produce response with correlation id 17 on topic-partition payments-0, retrying (2 attempts left). Error: NOT_ENOUGH_REPLICAS (org.apache.kafka.clients.producer.internals.Sender)
[2026-11-26 18:19:16,305] ERROR Error when sending message to topic payments with key: 9 bytes, value: 14 bytes with error: (org.apache.kafka.clients.producer.internals.ErrorLoggingCallback)
org.apache.kafka.common.errors.NotEnoughReplicasException: Messages are rejected since there are fewer in-sync replicas than required.
19:36:00 🔥 ❌ 5 record(s) could not be sent to topic payments: org.apache.kafka.common.errors.NotEnoughReplicasException: Messages are rejected since there are fewer in-sync replicas than required.
```

```bash
19:19:22 ℹ️ 📍 Earliest and latest offsets per partition of topic payments
PARTITION  EARLIEST        LATEST          RECORDS
0          0               0               0
1          0               4               4
2          0               0               0
TOTAL                                      4
```

The output also has `java.net.UnknownHostException: broker3` warnings: the producer still tries to reconnect to the
broker that crashed. They are not why the records failed.

❔Questions:

* Why do partitions 0 and 2 refuse the records, and not partition 1?
* How was the topic created?

#### **📍 Step 2**
<!-- select:start -->
<!-- select-menu-labels: 🙋 See solution for previous step? -->
#### --No--
#### --Yes--

```bash
playground broker health
19:20:12 🔥 ❌ broker 3 (container broker3) is not registered: it is stopped (playground broker start --broker 3)
19:20:12 🔥 ❌ 2 under min.insync.replicas partitions
TOPIC     PARTITION  LEADER  REPLICAS  ISR
payments  0          1       3,1       1
payments  2          2       2,3       2
```

> How was the topic created?

With 2 replicas and `min.insync.replicas=2`:

```bash
playground topic create --topic payments --nb-partitions 3 --replication-factor 2 --config min.insync.replicas=2
```

> Why do partitions 0 and 2 refuse the records, and not partition 1?

With `acks=all`, the leader writes a record only when at least `min.insync.replicas` replicas are in sync, so that it
is never on a single disk. Partitions 0 and 2 have a replica on broker 3: their ISR shrank to 1, below 2, so the leader
refuses the writes. Partition 1 lives on brokers 1 and 2 only. A replication factor equal to `min.insync.replicas`
means **no** broker can be down for `acks=all` producers: the usual rule is a replication factor of 3 with
`min.insync.replicas=2`, so one broker can fail (or restart, in a rolling upgrade).

<!-- select:end -->

* Bring broker 3 back, then send the payments again.

#### **📍 Step 3**
<!-- select:start -->
<!-- select-menu-labels: 🙋 See solution for previous step? -->
#### --No--
#### --Yes--

```bash
playground broker start --broker 3
19:36:15 ℹ️ ✅ broker 3 is registered, waiting for its replicas to be back in sync
19:36:21 ℹ️ ✅ cluster is healthy, broker 3 started in 11s
playground topic produce --topic payments --nb-messages 9 --key "account-%g" --forced-value '{"payment": %g}' --producer-property acks=all
19:46:37 ℹ️ 📤 produced 9 records to topic payments, took: 0min 2sec
```

For good, give the topic a third replica, so that the next crash of one broker does not stop the payments ([playground topic reassign](/playground%20topic%20reassign), every partition on brokers 1, 2 and 3):

```bash
playground topic reassign --topic payments --replicas 1,2,3
```

<!-- select:end -->
🥁 So...did you learn what acks=all and min.insync.replicas promise?

#### **🎓 Next Steps**

* Produce with `--producer-property acks=1` while broker 3 is down: the records are accepted. What can be lost?
* The [🍪 brokers and transactions](/deep-dive-broker.md) deep dive has the `NotEnoughReplicasException` recipe.

<!-- tabs:end -->

### Producer: slow, without any error

<!-- tabs:start -->
#### **🔥 Description**

The orders service used to send its batch of 3000 orders in a couple of seconds. Now it takes almost a minute, with no
error and nothing in the broker logs.

💡 What you'll learn:

* What a client quota is, and how a throttled client behaves
* Where to see that a client is throttled

#### **🤯 Details**

Versions used:

* 🎯 CP: 8.4.1

Reproduction model: [broker-repro-000022-slow-producer-no-error-quota.sh](https://github.com/vdesabou/kafka-docker-playground/blob/master/academy/environment-plaintext/broker-repro-000022-slow-producer-no-error-quota.sh)

#### **📍 Step 1**

Run the example:

```bash
playground run -f academy/environment-plaintext/broker-repro-000022-slow-producer-no-error-quota.sh
```

```bash
19:21:13 ℹ️ 📤 producing 3000 records to topic orders
[2026-11-26 18:21:14,350] WARN [Producer clientId=orders-service] Connection to node 1 is throttled for 931 ms until timestamp 1795717275281 (org.apache.kafka.clients.NetworkClient)
[2026-11-26 18:21:15,288] WARN [Producer clientId=orders-service] Connection to node 1 is throttled for 935 ms until timestamp 1795717276222 (org.apache.kafka.clients.NetworkClient)
…
19:22:02 ℹ️ 📤 produced 3000 records to topic orders, took: 0min 49sec
```

❔Questions:

* Who is throttling the producer, and why?
* How do you find the setting?

#### **📍 Step 2**
<!-- select:start -->
<!-- select-menu-labels: 🙋 See solution for previous step? -->
#### --No--
#### --Yes--

> Who is throttling the producer, and why?

The broker: `Connection to node 1 is throttled` means the broker asked the client to wait before its next request,
because the client is over a **client quota**. Nothing fails, the client is only slowed down to the rate of the quota,
and the broker logs nothing about it. [playground topic produce](/playground%20topic%20produce) says it at the end:

```bash
19:24:02 ❗ 🚥 the brokers throttled the producer orders-service 24 time(s): it is over a client quota (playground quota get --client-id orders-service)
```

and [playground analyze logs](/playground%20analyze%20logs) on a client log: `[MEDIUM] 🚥 Throttled by a broker quota`.

> How do you find the setting?

```bash
playground quota get
19:23:09 ℹ️ 🔎 Displaying all client quotas
Quota configs for client-id 'orders-service' are producer_byte_rate=51200.0
```

50 KB/s for the client id `orders-service`: 3000 records of 1 KB take about a minute. Quotas can also be set on a
user, and as defaults for every user or client id (`--all-users`, `--all-client-ids`): check all of them.

<!-- select:end -->

* Remove the quota, then send the orders again.

#### **📍 Step 3**
<!-- select:start -->
<!-- select-menu-labels: 🙋 See solution for previous step? -->
#### --No--
#### --Yes--

```bash
playground quota delete --client-id orders-service --producer-byte-rate
playground topic produce --topic orders --nb-messages 3000 --record-size 1000 --forced-value '{"order": %g}' --producer-property client.id=orders-service
19:23:28 ℹ️ 📤 produced 3000 records to topic orders, took: 0min 1sec
```

<!-- select:end -->
🥁 So...did you learn how a throttled client looks?

#### **🎓 Next Steps**

* The same on a consumer: `playground quota set --client-id <id> --consumer-byte-rate 10240`, then read the topic. On a sink connector, `--connector <name>` targets the client ids of its tasks, and the lag grows (`playground connector show-lag`).
* `produce-throttle-time-avg` and `fetch-throttle-time-avg` are the client metrics that show it in a monitoring system.

<!-- tabs:end -->


## ⭐⭐ Intermediate

### StackOverflowError with S3 sink connector

<!-- tabs:start -->
#### **🔥 Description**

User is getting StackOverflowError with S3 sink connector. See stack trace in Details section.

💡 What you'll learn:

* Choose the closest example and [bootstrap a reproduction model](/toolkit-reproduction-models?id=%f0%9f%9b%a0-bootstrap-reproduction-model) from it.
* Adapt it to the customer data (schema) and configuration.
* Explain the root cause from the stack trace.

#### **🤯 Details**

> [!WARNING]
> The S3 sink writes to a real S3 bucket: you need an AWS account. Check it with [playground account aws check](/playground%20account%20aws%20check) (and set it up with `playground account aws setup`). No AWS account? Do the same exercise with the MinIO example, [connect-minio-s3-sink](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-minio-s3-sink), which runs the S3 sink against a local MinIO.

Versions used:

* 🎯 CP: 7.5.2 (the customer), 8.4.1 (this page)

* 🔗 S3 sink: 10.3.3 (the customer); still reproduced with 12.1.16 (parquet-avro 1.15.2) in November 2026

S3 sink config:

```json
{
  "aws.access.key.id": "xxx",
  "aws.secret.access.key": "xxx",
  "connector.class": "io.confluent.connect.s3.S3SinkConnector",
  "errors.log.enable": "true",
  "errors.tolerance": "all",
  "flush.size": "50000",
  "format.class": "io.confluent.connect.s3.format.parquet.ParquetFormat",
  "key.converter": "org.apache.kafka.connect.storage.StringConverter",
  "locale": "de_DE",
  "partitioner.class": "io.confluent.connect.storage.partitioner.DailyPartitioner",
  "rotate.interval.ms": "3600000",
  "s3.bucket.name": "xxx",
  "s3.region": "eu-west-1",
  "storage.class": "io.confluent.connect.s3.storage.S3Storage",
  "tasks.max": "1",
  "timestamp.extractor": "Record",
  "timezone": "UTC",
  "topics.dir": "xxx",
  "topics": "topic1",
  "value.converter.schema.registry.url": "xxx",
  "value.converter": "io.confluent.connect.avro.AvroConverter"
}
```

Avro schema of the topic `topic1` (value):

```json
{
    "type": "record",
    "namespace": "acme",
    "name": "Characteristic",
    "fields": [
        {
            "name": "physicalCharacteristic",
            "type": [
                "null",
                {
                    "type": "record",
                    "name": "PhysicalCharacteristic",
                    "fields": [
                        {
                            "name": "children",
                            "type": [
                                "null",
                                {
                                    "type": "array",
                                    "items": "PhysicalCharacteristic"
                                }
                            ],
                            "default": null
                        }
                    ]
                }
            ]
        }
    ]
}
```

User is getting in logs:

```log
[2022-12-12 16:44:06,186] ERROR [s3-sink|task-0] WorkerSinkTask{id=s3-sink-0} Task threw an uncaught and unrecoverable exception. Task is being killed and will not recover until manually restarted (org.apache.kafka.connect.runtime.WorkerTask:208)
org.apache.kafka.connect.errors.ConnectException: Exiting WorkerSinkTask due to unrecoverable exception.
	at org.apache.kafka.connect.runtime.WorkerSinkTask.deliverMessages(WorkerSinkTask.java:618)
	at org.apache.kafka.connect.runtime.WorkerSinkTask.poll(WorkerSinkTask.java:334)
	at org.apache.kafka.connect.runtime.WorkerSinkTask.iteration(WorkerSinkTask.java:235)
	at org.apache.kafka.connect.runtime.WorkerSinkTask.execute(WorkerSinkTask.java:204)
	at org.apache.kafka.connect.runtime.WorkerTask.doRun(WorkerTask.java:201)
	at org.apache.kafka.connect.runtime.WorkerTask.run(WorkerTask.java:256)
	at java.base/java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:515)
	at java.base/java.util.concurrent.FutureTask.run(FutureTask.java:264)
	at java.base/java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1128)
	at java.base/java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:628)
	at java.base/java.lang.Thread.run(Thread.java:829)
Caused by: java.lang.StackOverflowError
	at org.apache.parquet.avro.AvroSchemaConverter.convertFields(AvroSchemaConverter.java:130)
	at org.apache.parquet.avro.AvroSchemaConverter.convertField(AvroSchemaConverter.java:163)
	at org.apache.parquet.avro.AvroSchemaConverter.convertField(AvroSchemaConverter.java:169)
	at org.apache.parquet.avro.AvroSchemaConverter.convertUnion(AvroSchemaConverter.java:226)
	at org.apache.parquet.avro.AvroSchemaConverter.convertField(AvroSchemaConverter.java:182)
	at org.apache.parquet.avro.AvroSchemaConverter.convertField(AvroSchemaConverter.java:141)
```

#### **📍 Step 1**

*  🎯 Choose the best example to use as a basis: search the **[👾 Examples](/examples.md)** page, or `playground find-example "s3 sink"`.

* 🛠 [Bootstrap](/toolkit-reproduction-models?id=%f0%9f%9b%a0-bootstrap-reproduction-model) your reproduction model!

> [!TIP]
> Do not forget to [🪄 Specify versions](/how-to-use?id=%f0%9f%aa%84-specify-versions) for CP and the connector before running the test!

#### **📍 Step 2**
<!-- select:start -->
<!-- select-menu-labels: 🙋 See solution for previous step? -->
#### --No--
#### --Yes--

🛠 The reproduction model was bootstrapped like this (use the `fzf` completion of `--file` to select `s3-sink.sh`):

```bash
playground repro bootstrap --file s3-sink<tab> --description "000001 StackOverflowError with S3 sink connector"
```

Then run the generated reproduction model with the required versions:

```bash
playground run -f s3-sink-repro-000001<tab> --tag 7.5.2 --connector-tag 10.3.3
```

💡 Explanations:

* [s3-sink.sh](https://github.com/vdesabou/kafka-docker-playground/blob/master/connect/connect-aws-s3-sink/s3-sink.sh) is the closest example.
* The problem seems related to the input data, so using [playground topic produce](/playground%20topic%20produce) with the Avro schema of the customer seems the right thing to do.

<!-- select:end -->

* 👉 Use [playground topic produce](/playground%20topic%20produce) to produce data

#### **📍 Step 3**
<!-- select:start -->
<!-- select-menu-labels: 🙋 See solution for previous step? -->
#### --No--
#### --Yes--

⌨️ Here are the steps to follow:

Update the `playground topic produce` command of the example to use the Avro schema of the customer:

```bash
playground topic produce -t customer_avro --nb-messages 1 --verbose << 'EOF'
{
    "type": "record",
    "namespace": "acme",
    "name": "Characteristic",
    "fields": [
        {
            "name": "physicalCharacteristic",
            "type": [
                "null",
                {
                    "type": "record",
                    "name": "PhysicalCharacteristic",
                    "fields": [
                        {
                            "name": "children",
                            "type": [
                                "null",
                                {
                                    "type": "array",
                                    "items": "PhysicalCharacteristic"
                                }
                            ],
                            "default": null
                        }
                    ]
                }
            ]
        }
    ]
}
EOF
```

<!-- select:end -->
👉 Adapt the example to the user details and run it!

#### **📍 Step 4**
<!-- select:start -->
<!-- select-menu-labels: 🙋 See solution for previous step? -->
#### --No--
#### --Yes--

* The only relevant connector configuration for this use case is the Parquet format. The base example uses the Avro format, so `format.class` was replaced to use Parquet instead:

```json
"format.class": "io.confluent.connect.s3.format.parquet.ParquetFormat"
```

* Full connector config (unquoted `<< EOF`: the shell replaces `$AWS_REGION` and the other variables):

```bash
playground connector create-or-update --connector s3-sink << EOF
{
    "connector.class": "io.confluent.connect.s3.S3SinkConnector",
    "key.converter": "org.apache.kafka.connect.storage.StringConverter",
    "value.converter": "io.confluent.connect.avro.AvroConverter",
    "value.converter.schema.registry.url": "http://schema-registry:8081",
    "tasks.max": "1",
    "topics": "customer_avro",
    "s3.region": "$AWS_REGION",
    "s3.bucket.name": "$AWS_BUCKET_NAME",
    "topics.dir": "$TAG",
    "s3.part.size": 52428801,
    "flush.size": "3",
    "aws.access.key.id" : "$AWS_ACCESS_KEY_ID",
    "aws.secret.access.key": "$AWS_SECRET_ACCESS_KEY",
    "storage.class": "io.confluent.connect.s3.storage.S3Storage",
    "format.class": "io.confluent.connect.s3.format.parquet.ParquetFormat",
    "schema.compatibility": "NONE"
}
EOF
```

<!-- select:end -->
🥁 So...did you reproduce it? And why does it fail?

#### **🌟 Results**

* Check the connector status:

```bash
playground connector status
```

```log
s3-sink                        ✅ RUNNING  0:🛑 FAILED                   tasks: org.apache.kafka.connect.errors.ConnectException: Exiting WorkerSinkTask due to unrecoverable exception.
Caused by: java.lang.StackOverflowError
	at org.apache.parquet.avro.AvroSchemaConverter.convertField(AvroSchemaConverter.java:225)
	at org.apache.parquet.avro.AvroSchemaConverter.convertField(AvroSchemaConverter.java:167)
	at org.apache.parquet.avro.AvroSchemaConverter.convertField(AvroSchemaConverter.java:288)
	at org.apache.parquet.avro.AvroSchemaConverter.convertFields(AvroSchemaConverter.java:161)
	at org.apache.parquet.avro.AvroSchemaConverter.convertField(AvroSchemaConverter.java:197)
	at org.apache.parquet.avro.AvroSchemaConverter.convertField(AvroSchemaConverter.java:203)
	at org.apache.parquet.avro.AvroSchemaConverter.convertUnion(AvroSchemaConverter.java:269)
	at org.apache.parquet.avro.AvroSchemaConverter.convertField(AvroSchemaConverter.java:225)
```

👍 It failed as expected (here with CP 8.4.1 and S3 sink 12.1.16: the issue is still there).

You can also wait for the `StackOverflowError` in the logs:

```bash
playground container logs -c connect --wait-for-log "StackOverflowError"
13:06:38 ℹ️ ⌛ Waiting up to 600 seconds for message StackOverflowError to be present in connect container logs...
java.lang.StackOverflowError
Caused by: java.lang.StackOverflowError
```

💡 Root cause:

* The Avro schema is **recursive**: `PhysicalCharacteristic.children` is an array of `PhysicalCharacteristic`.
* To write Parquet, the S3 sink converts the Avro schema to a Parquet schema with `AvroSchemaConverter` of `parquet-avro`. It converts each field, and each field of a record field: `convertField → convertFields → convertField → convertUnion → convertField…`, the loop you see in the stack trace.
* A Parquet schema cannot be recursive, so the conversion never ends, until the stack overflows.

What to tell the customer: Parquet cannot store this schema. Either use another `format.class` (`AvroFormat` or `JsonFormat`), or change the schema so that it is not recursive (for example a fixed number of levels).

* The full reproduction model is available [here](https://github.com/vdesabou/kafka-docker-playground/blob/master/academy/connect-connect-aws-s3-sink/s3-sink-repro-000001-stackoverflowerror-with-s3-sink-connector.sh).

<!-- tabs:end -->


### JDBC source: the updated rows never reach the topic

<!-- tabs:start -->
#### **🔥 Description**

A JDBC source connector copies the `CUSTOMERS` table of a MySQL database to Kafka. New customers show up in the topic within a second, but when the status of a customer changes in the database, the topic never gets the change.

💡 What you'll learn:

* The modes of the JDBC source connector, and what each one can see.
* Read the offset of a source connector: what it remembers from one query to the next.
* What happens to that offset when you change the mode of a running connector.

#### **🤯 Details**

Versions used:

* 🎯 CP: 8.4.1

* 🔗 JDBC source (MySQL): 10.9.10

The table: `update_ts` is set by MySQL on every update.

```sql
CREATE TABLE CUSTOMERS (
  id          INT NOT NULL AUTO_INCREMENT PRIMARY KEY,
  first_name  VARCHAR(50),
  last_name   VARCHAR(50),
  club_status VARCHAR(20),
  update_ts   TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3)
);
```

Connector config:

```json
{
  "connector.class": "io.confluent.connect.jdbc.JdbcSourceConnector",
  "connection.url": "jdbc:mysql://mysql:3306/mydb?user=user&password=password&useSSL=false&allowPublicKeyRetrieval=true",
  "table.whitelist": "CUSTOMERS",
  "mode": "incrementing",
  "incrementing.column.name": "id",
  "poll.interval.ms": "1000",
  "topic.prefix": "mysql-",
  "value.converter": "io.confluent.connect.avro.AvroConverter",
  "value.converter.schema.registry.url": "http://schema-registry:8081"
}
```

Reproduction model: [mysql-repro-000012-jdbc-source-misses-updates.sh](https://github.com/vdesabou/kafka-docker-playground/blob/master/academy/connect-connect-jdbc-mysql-source/mysql-repro-000012-jdbc-source-misses-updates.sh)

> [!NOTE]
> Do not read the model before the exercise: it contains the answer.

#### **📍 Step 1**

Run the example (or type `000012` and use the `fzf` completion of `-f`):

```bash
playground run -f academy/connect-connect-jdbc-mysql-source/mysql-repro-000012-jdbc-source-misses-updates.sh
```

The table starts with 3 customers. Then Rica is promoted to `gold`, and a new customer, Hashim, signs up. The topic:

```log
10:27:10 ℹ️ ✨ Display content of topic mysql-CUSTOMERS, it contains 4 messages
CreateTime:2026-11-26 10:26:50.888|Partition:0|Offset:0|Headers:NO_HEADERS|Key:null|Value:{"id":1,"first_name":{"string":"Rica"},"last_name":{"string":"Blaisdell"},"club_status":{"string":"bronze"},"update_ts":1795685201819}|ValueSchemaId:1
CreateTime:2026-11-26 10:26:50.889|Partition:0|Offset:1|Headers:NO_HEADERS|Key:null|Value:{"id":2,"first_name":{"string":"Ruthie"},"last_name":{"string":"Brockherst"},"club_status":{"string":"platinum"},"update_ts":1795685201821}|ValueSchemaId:1
CreateTime:2026-11-26 10:26:50.889|Partition:0|Offset:2|Headers:NO_HEADERS|Key:null|Value:{"id":3,"first_name":{"string":"Mariejeanne"},"last_name":{"string":"Cocci"},"club_status":{"string":"bronze"},"update_ts":1795685201822}|ValueSchemaId:1
CreateTime:2026-11-26 10:27:00.891|Partition:0|Offset:3|Headers:NO_HEADERS|Key:null|Value:{"id":4,"first_name":{"string":"Hashim"},"last_name":{"string":"Rumke"},"club_status":{"string":"silver"},"update_ts":1795685216450}|ValueSchemaId:1
```

Hashim is there. Rica is still `bronze`, while the database says:

```bash
playground db sql --database mydb << 'EOF'
SELECT id, first_name, club_status, update_ts FROM CUSTOMERS WHERE id = 1;
EOF
```

```log
+----+-------------+-------------+-------------------------+
| id | first_name  | club_status | update_ts               |
+----+-------------+-------------+-------------------------+
|  1 | Rica        | gold        | 2026-11-26 09:26:56.448 |
+----+-------------+-------------+-------------------------+
```

The connector is RUNNING, with no error.

❔Questions:

* What does the connector remember from one query to the next?
* Why does it see a new row, and not an updated one?

#### **📍 Step 2**
<!-- select:start -->
<!-- select-menu-labels: 🙋 See solution for previous step? -->
#### --No--
#### --Yes--

> What does the connector remember from one query to the next?

Its offset, with [playground connector offsets get](/playground%20connector%20offsets%20get):

```bash
playground connector offsets get --connector mysql-source
```

```json
{
  "offsets": [
    {
      "partition": {
        "protocol": "1",
        "table": "mydb.CUSTOMERS"
      },
      "offset": {
        "incrementing": 4
      }
    }
  ]
}
```

> [!TIP]
> A source connector commits its offsets every 60 seconds (`offset.flush.interval.ms`): right after the start, `offsets get` can still return `"offsets": []`.

> Why does it see a new row, and not an updated one?

In `incrementing` mode, the only thing the connector keeps is the highest `id` it has sent, and each query asks for the rows above it: `WHERE id > 4`. A new row gets a new `id`. An `UPDATE` keeps the `id` of the row: the connector never sees it. Deleted rows are never seen either, in any mode.

| `mode` | sees new rows | sees updated rows | needs |
| --- | --- | --- | --- |
| `bulk` | yes (the whole table at every poll) | yes (the whole table at every poll) | nothing |
| `incrementing` | yes | **no** | a column that always grows |
| `timestamp` | yes | yes | a column updated on each change; rows with the same timestamp can be missed |
| `timestamp+incrementing` | yes | yes | both: the most reliable mode |

<!-- select:end -->

👉 Switch the connector to `timestamp+incrementing` with `timestamp.column.name` set to `update_ts`: update it in place, with the same name. Then look at the topic again.

#### **📍 Step 3**
<!-- select:start -->
<!-- select-menu-labels: 🙋 See solution for previous step? -->
#### --No--
#### --Yes--

```bash
playground connector create-or-update --connector mysql-source << EOF
{
     "connector.class":"io.confluent.connect.jdbc.JdbcSourceConnector",
     "tasks.max":"1",
     "connection.url":"jdbc:mysql://mysql:3306/mydb?user=user&password=password&useSSL=false&allowPublicKeyRetrieval=true",
     "table.whitelist":"CUSTOMERS",
     "mode":"timestamp+incrementing",
     "timestamp.column.name":"update_ts",
     "incrementing.column.name":"id",
     "poll.interval.ms":"1000",
     "topic.prefix":"mysql-",
     "value.converter":"io.confluent.connect.avro.AvroConverter",
     "value.converter.schema.registry.url":"http://schema-registry:8081"
}
EOF
```

Rica's `gold` is in the topic now... and so are Ruthie, Mariejeanne and Hashim, a second time:

```log
10:28:32 ℹ️ ✨ Display content of topic mysql-CUSTOMERS, it contains 8 messages
...
CreateTime:2026-11-26 10:28:21.011|Partition:0|Offset:4|Headers:NO_HEADERS|Key:null|Value:{"id":2,"first_name":{"string":"Ruthie"},"last_name":{"string":"Brockherst"},"club_status":{"string":"platinum"},"update_ts":1795685201821}|ValueSchemaId:1
CreateTime:2026-11-26 10:28:21.012|Partition:0|Offset:5|Headers:NO_HEADERS|Key:null|Value:{"id":3,"first_name":{"string":"Mariejeanne"},"last_name":{"string":"Cocci"},"club_status":{"string":"bronze"},"update_ts":1795685201822}|ValueSchemaId:1
CreateTime:2026-11-26 10:28:21.012|Partition:0|Offset:6|Headers:NO_HEADERS|Key:null|Value:{"id":1,"first_name":{"string":"Rica"},"last_name":{"string":"Blaisdell"},"club_status":{"string":"gold"},"update_ts":1795685216448}|ValueSchemaId:1
CreateTime:2026-11-26 10:28:21.012|Partition:0|Offset:7|Headers:NO_HEADERS|Key:null|Value:{"id":4,"first_name":{"string":"Hashim"},"last_name":{"string":"Rumke"},"club_status":{"string":"silver"},"update_ts":1795685216450}|ValueSchemaId:1
```

The connector kept its offset (same name), but `{"incrementing": 4}` has no timestamp: the new mode starts from the beginning of time and sends the whole table again, in `update_ts` order. From now on, the offset has both:

```json
      "offset": {
        "timestamp_nanos": 773000000,
        "incrementing": 3,
        "timestamp": 1795685324773
      }
```

and an update arrives within a second:

```bash
playground db sql --database mydb << 'EOF'
UPDATE CUSTOMERS SET club_status = 'platinum' WHERE id = 3;
EOF
```

```log
CreateTime:2026-11-26 10:28:46.027|Partition:0|Offset:8|Headers:NO_HEADERS|Key:null|Value:{"id":3,"first_name":{"string":"Mariejeanne"},"last_name":{"string":"Cocci"},"club_status":{"string":"platinum"},"update_ts":1795685324773}|ValueSchemaId:1
```

<!-- select:end -->

🥁 So...is a duplicate a problem? Only if the consumers can't tell that two records are the same customer: give the records a key.

#### **🎓 Next Steps**

* Read the [🍪 Offsets and lag](/deep-dive-offsets-and-lag.md) deep dive.
* Give the records the `id` as key, with the `ValueToKey` and `ExtractField$Key` SMTs: a sink in upsert mode (or a compacted topic) then overwrites a customer instead of adding a row. Test the chain with [playground connector smt test](/playground%20connector%20smt%20test).
* Deletes: no JDBC source mode sees a deleted row. Capturing them is the job of a CDC connector reading the binlog: compare with the Debezium MySQL example (`playground find-example --category connect debezium mysql`).

<!-- tabs:end -->

### HTTP sink: tasks.max is 4, but only one task works

<!-- tabs:start -->
#### **🔥 Description**

An HTTP sink connector falls behind: its lag keeps growing. The team set `tasks.max` to `4` so that 4 requests go to the API in parallel, and the 4 tasks are RUNNING. Yet the API receives one request at a time.

💡 What you'll learn:

* How the tasks of a sink connector share the partitions of its topics.
* Why a running connector (and producer) does not see new partitions right away.
* The second lever: how many records a task sends per request.

#### **🤯 Details**

Versions used:

* 🎯 CP: 8.4.1

* 🔗 HTTP sink: 1.7.15

The API takes 500 ms to answer each request. The shop sends 6 orders per second, with the order id as key.

Connector config:

```json
{
  "connector.class": "io.confluent.connect.http.HttpSinkConnector",
  "topics": "orders",
  "tasks.max": "4",
  "http.api.url": "http://httpserver:9006",
  "request.body.format": "json",
  "batch.max.size": "1",
  "key.converter": "org.apache.kafka.connect.storage.StringConverter",
  "value.converter": "org.apache.kafka.connect.json.JsonConverter",
  "value.converter.schemas.enable": "false"
}
```

Reproduction model: [http-sink-repro-000013-tasks-max-one-task-works.sh](https://github.com/vdesabou/kafka-docker-playground/blob/master/academy/connect-connect-http-sink/http-sink-repro-000013-tasks-max-one-task-works.sh)

> [!NOTE]
> Do not read the model before the exercise: it contains the answer.

#### **📍 Step 1**

Run the example (or type `000013` and use the `fzf` completion of `-f`):

```bash
playground run -f academy/connect-connect-http-sink/http-sink-repro-000013-tasks-max-one-task-works.sh
```

The orders keep flowing in the background (for 30 minutes). After a minute:

```log
10:43:59 ℹ️ 🐢 consumer lag for 🌎onprem connector http-sink is 326
topic: orders     partition: 0   current-offset: 140        end-offset: 466        lag: 326        [🔹🔹🔹🔹🔹🔹🔹💠💠💠💠💠💠💠💠💠💠💠💠💠]  31%
```

Run [playground connector show-lag](/playground%20connector%20show-lag) again: the lag grows.

❔Questions:

* What do the 4 tasks do?
* How many records per second can the connector send to the API?

#### **📍 Step 2**
<!-- select:start -->
<!-- select-menu-labels: 🙋 See solution for previous step? -->
#### --No--
#### --Yes--

> What do the 4 tasks do?

[playground connector tasks](/playground%20connector%20tasks) shows what each task reads:

```bash
playground connector tasks --connector http-sink
```

```log
10:44:22 ℹ️ 🧵 Tasks of 🌎onprem connector http-sink (sink, connector RUNNING, on connect:8083, tasks.max=4, 4 task(s))
Task   State            Worker                   Partitions
-------------------------------------------------------------------------------------------------------------
0      🟢 RUNNING     connect:8083             orders-0
1      🟢 RUNNING     connect:8083             - (no partition assigned)
2      🟢 RUNNING     connect:8083             - (no partition assigned)
3      🟢 RUNNING     connect:8083             - (no partition assigned)
-------------------------------------------------------------------------------------------------------------
10:44:23 ℹ️ 💤 3 task(s) without partition: tasks.max is higher than the number of partitions of the topics, or the consumer group is rebalancing
```

The topic has a single partition:

```bash
playground topic describe --topic orders
```

```log
Topic: orders	TopicId: R4hg1mXoRxK01tl4LIhB4g	PartitionCount: 1	ReplicationFactor: 1	Configs: min.insync.replicas=1
```

Each task is a consumer of the group `connect-http-sink`, and a partition is read by one consumer of the group only. With 1 partition, 1 task works and 3 wait.

> How many records per second can the connector send to the API?

One request at a time, one record per request (`batch.max.size` is `1`), 500 ms per request: 2 records per second, for 6 produced.

> [!TIP]
> [playground connector lint](/playground%20connector%20lint) finds it from the config, before anyone looks at the lag. On a running environment, it reads the partitions of the topics of a sink:
>
> ```bash
> playground connector lint --connector http-sink
> ```
>
> ```log
> 🧪 http-sink (io.confluent.connect.http.HttpSinkConnector, sink)
> 🟡 LOW    tasks.max = 4
>           why: 4 tasks for 1 partition(s): 3 task(s) stay idle
>           fix: set tasks.max=1 or add partitions (playground topic add-partitions)
> ❌ 1 warning(s), 0 note(s)
> ```
>
> Run it on every config a customer sends (stdin works too: CFK, Strimzi, terraform, `.properties`): it also checks the dead letter queue, the replication factors, the client overrides, the converters and the secrets in clear text.

<!-- select:end -->

👉 Give the topic 4 partitions, with [playground topic add-partitions](/playground%20topic%20add-partitions), then check the tasks again (several times).

#### **📍 Step 3**
<!-- select:start -->
<!-- select-menu-labels: 🙋 See solution for previous step? -->
#### --No--
#### --Yes--

```bash
playground topic add-partitions --topic orders --nb-partitions 4
```

```log
10:44:28 ℹ️ ➕ Adding partitions to topic orders: 1 → 4
10:44:30 ℹ️ ✅ topic orders has 4 partitions
10:44:30 ℹ️ ⚠️ records with a key: hash(key) % 4 now decides their partition, new records of a key can land in another partition than the older ones
```

Surprise: nothing changes for minutes. A running client (the consumers of the tasks, and the producer) learns about new partitions when it refreshes its metadata, every `metadata.max.age.ms` (5 minutes by default). Then the group rebalances, and the rebalance waits for task 0 to come back from its current `put()`: up to 500 records (`max.poll.records`) at 500 ms each. Here, the 4 tasks had a partition 6 minutes later:

```log
Task   State            Worker                   Partitions
-------------------------------------------------------------------------------------------------------------
0      🟢 RUNNING     connect:8083             orders-0
1      🟢 RUNNING     connect:8083             orders-1
2      🟢 RUNNING     connect:8083             orders-2
3      🟢 RUNNING     connect:8083             orders-3
-------------------------------------------------------------------------------------------------------------
10:50:53 ℹ️ 🐢 consumer lag for 🌎onprem connector http-sink is not available (no offset committed yet)
topic: orders     partition: 0   current-offset: 952        end-offset: 2106       lag: 1154       [🔹🔹🔹🔹🔹🔹🔹🔹🔹🔹💠💠💠💠💠💠💠💠💠💠]  46%
topic: orders     partition: 1   current-offset: -          end-offset: 272        lag: -          []   0%
topic: orders     partition: 2   current-offset: -          end-offset: 279        lag: -          []   0%
topic: orders     partition: 3   current-offset: -          end-offset: 292        lag: -          []   0%
```

The new orders are spread over the 4 partitions (the key decides), but the records already in partition 0 stay there: the backlog of 1154 records is still for task 0 alone, at 2 records per second.

<!-- select:end -->

👉 Find the setting that lets a single task send more than 2 records per second, and use it.

#### **📍 Step 4**
<!-- select:start -->
<!-- select-menu-labels: 🙋 See solution for previous step? -->
#### --No--
#### --Yes--

`batch.max.size`: the number of records sent in one request. With `50`, one request of 500 ms carries up to 50 records. Update the connector (same config, `"batch.max.size": "50"`):

```log
10:51:06 ℹ️ 🔍 changes compared to the running config:
   ~ batch.max.size: 1 → 50
10:51:15 ℹ️ ✅ 🌎onprem connector http-sink is RUNNING (4 task(s)) after 5 seconds
```

The update restarts the tasks (another rebalance, the same wait for task 0). 4 minutes later, the backlog is gone:

```log
10:55:23 ℹ️ 🐢 consumer lag for 🌎onprem connector http-sink is 54
topic: orders     partition: 0   current-offset: 2507       end-offset: 2517       lag: 10         [🔹🔹🔹🔹🔹🔹🔹🔹🔹🔹🔹🔹🔹🔹🔹🔹🔹🔹🔹🔹] 100%
topic: orders     partition: 1   current-offset: 680        end-offset: 694        lag: 14         [🔹🔹🔹🔹🔹🔹🔹🔹🔹🔹🔹🔹🔹🔹🔹🔹🔹🔹🔹🔹]  98%
topic: orders     partition: 2   current-offset: 640        end-offset: 653        lag: 13         [🔹🔹🔹🔹🔹🔹🔹🔹🔹🔹🔹🔹🔹🔹🔹🔹🔹🔹🔹🔹]  99%
topic: orders     partition: 3   current-offset: 689        end-offset: 706        lag: 17         [🔹🔹🔹🔹🔹🔹🔹🔹🔹🔹🔹🔹🔹🔹🔹🔹🔹🔹🔹🔹]  98%
```

> [!TIP]
> The lag is computed from the committed offsets, committed every 60 seconds: between two commits it looks higher than it is.

<!-- select:end -->
🥁 So...more tasks, or bigger requests? Both, but `tasks.max` above the number of partitions buys nothing.

#### **🎓 Next Steps**

* Stop the background producer: `playground topic produce --topic orders --stop`.
* Read the [🍪 Offsets and lag](/deep-dive-offsets-and-lag.md) deep dive.
* Adding partitions to a topic with keys changes the partition of a key: a consumer no longer sees all the records of a key in order. Create the topic with enough partitions from the start.
* Check that the API accepts a batch: with `request.body.format` `json`, the body is a JSON array of up to `batch.max.size` records (see it with `playground tools http-server requests`).

<!-- tabs:end -->

### HTTP sink: the API answers 400, and errors.tolerance doesn't help

<!-- tabs:start -->
#### **🔥 Description**

The API that receives the records of an HTTP sink connector added a validation rule, and now answers `400 Bad Request`. The connector was configured with `errors.tolerance` `all` and a dead letter queue, "so that a bad record can never stop it". The task FAILED anyway, and the dead letter queue is empty.

💡 What you'll learn:

* What `errors.tolerance` and the dead letter queue cover, and what they don't.
* How the HTTP sink handles an error response: retries, `behavior.on.error`, the error reporter topic.
* Send failed records again once the API is fixed.

#### **🤯 Details**

Versions used:

* 🎯 CP: 8.4.1

* 🔗 HTTP sink: 1.7.15

Connector config:

```json
{
  "connector.class": "io.confluent.connect.http.HttpSinkConnector",
  "topics": "http-messages",
  "http.api.url": "http://httpserver:9006",
  "request.body.format": "json",
  "reporter.bootstrap.servers": "broker:9092",
  "reporter.error.topic.name": "error-responses",
  "reporter.result.topic.name": "success-responses",
  "max.retries": "3",
  "retry.backoff.ms": "1000",
  "errors.tolerance": "all",
  "errors.deadletterqueue.topic.name": "dlq",
  "errors.deadletterqueue.context.headers.enable": "true"
}
```

Reproduction model: [http-sink-repro-000014-http-sink-400-and-dlq.sh](https://github.com/vdesabou/kafka-docker-playground/blob/master/academy/connect-connect-http-sink/http-sink-repro-000014-http-sink-400-and-dlq.sh)

> [!NOTE]
> Do not read the model before the exercise: it contains the answer.

#### **📍 Step 1**

Run the example (or type `000014` and use the `fzf` completion of `-f`):

```bash
playground run -f academy/connect-connect-http-sink/http-sink-repro-000014-http-sink-400-and-dlq.sh
```

```log
http-sink                      ✅ RUNNING  0:🛑 FAILED                   tasks: org.apache.kafka.connect.errors.ConnectException: Exiting WorkerSinkTask due to unrecoverable exception.
...
Caused by: org.apache.kafka.connect.errors.ConnectException: Error while processing HTTP request with Url : http://httpserver:9006, Status code : 400, Reason Phrase : Bad Request,
	at io.confluent.connect.http.writer.HttpWriterImpl.handleException(HttpWriterImpl.java:502)
	at io.confluent.connect.http.writer.HttpWriterImpl.sendBatch(HttpWriterImpl.java:383)
	at io.confluent.connect.http.writer.HttpWriterImpl.write(HttpWriterImpl.java:190)
	at io.confluent.connect.http.HttpSinkTask.put(HttpSinkTask.java:62)
```

❔Questions:

* How many requests did the API receive?
* Where did the failed record go, and where is the answer of the API?
* Why did `errors.tolerance` not keep the task alive?

#### **📍 Step 2**
<!-- select:start -->
<!-- select-menu-labels: 🙋 See solution for previous step? -->
#### --No--
#### --Yes--

> How many requests did the API receive?

[playground tools http-server requests](/playground%20tools%20http-server%20requests) lists what the test server received:

```bash
playground tools http-server requests
```

```log
10:58:07 ℹ️ 🌐 answers: 400 after 0 ms, body {"error":"email: must be a company address"}
10:58:07 ℹ️ 📥 4 request(s) received since the start or the last reset (4 kept)
#1 10:57:10 POST / → 400  application/json, 82 bytes
   [{"name":"Gage.Christiansen11","id":1,"email":"Eloise_Kerluke-Blick@example.net"}]
#2 10:57:10 POST / → 400  application/json, 82 bytes
   [{"name":"Gage.Christiansen11","id":1,"email":"Eloise_Kerluke-Blick@example.net"}]
#3 10:57:11 POST / → 400  application/json, 82 bytes
   [{"name":"Gage.Christiansen11","id":1,"email":"Eloise_Kerluke-Blick@example.net"}]
#4 10:57:11 POST / → 400  application/json, 82 bytes
   [{"name":"Gage.Christiansen11","id":1,"email":"Eloise_Kerluke-Blick@example.net"}]
```

The same first record, 4 times: the request and its 3 retries (`max.retries`). By default the HTTP sink retries every status code from 400 up (`retry.on.status.codes` is `400-`), even though a `400` answers the same each time. After the last retry, `behavior.on.error` (default `fail`) fails the task. Records 2 and 3 were never sent.

> Where did the failed record go, and where is the answer of the API?

Not in the dead letter queue:

```bash
playground topic dlq inspect --topic dlq
```

```log
10:58:08 ℹ️ ✅ dead letter queue dlq is empty
```

The HTTP sink writes the failures to its own error reporter topic, `reporter.error.topic.name`, with the answer of the API and the position of the record in the headers:

```bash
playground topic consume --topic error-responses
```

```log
CreateTime:2026-11-26 10:57:11.852|Partition:0|Offset:0|Headers:input_record_offset:0,input_record_timestamp:1795687025610,input_record_partition:0,input_record_topic:http-messages,error_message:null,exception:null,response_content:{"error":"email: must be a company address"},status_code:400,...
```

> Why did `errors.tolerance` not keep the task alive?

`errors.tolerance` and the dead letter queue cover the steps that Connect runs for the connector: the converter and the SMTs (the [Avro Converter exercise](/academy?id=avro-converter-unknown-magic-byte) uses them). The HTTP call happens inside the connector, in `put()`: its errors are handled by the settings of the connector.

<!-- select:end -->

👉 Change the config so that a `400` is not retried, the connector keeps running, and every refused record is kept.

#### **📍 Step 3**
<!-- select:start -->
<!-- select-menu-labels: 🙋 See solution for previous step? -->
#### --No--
#### --Yes--

Two settings of the HTTP sink, added to the config:

```json
     "retry.on.status.codes": "429,500-",
     "behavior.on.error": "log"
```

* `retry.on.status.codes`: retry what can succeed later (`429 Too Many Requests`, the `5xx` of a server in trouble), not a `400`.
* `behavior.on.error` `log`: write the failure to `error-responses` and go on with the next records (`ignore` would go on without keeping anything).

Update the connector and restart it (its task is FAILED):

```log
10:58:50 ℹ️ 🔍 changes compared to the running config:
   + behavior.on.error: log
   + retry.on.status.codes: 429,500-
...
http-sink                      ✅ RUNNING  0:🟢 RUNNING                 -
```

One request per record, and one error record per refused record (`input_record_offset` 0, 1, 2):

```log
10:59:25 ℹ️ 📥 3 request(s) received since the start or the last reset (3 kept)
#1 10:58:54 POST / → 400  application/json, 82 bytes
   [{"name":"Gage.Christiansen11","id":1,"email":"Eloise_Kerluke-Blick@example.net"}]
#2 10:58:54 POST / → 400  application/json, 75 bytes
   [{"name":"Madeline.DuBuque61","id":2,"email":"Lilliana_Kulas@example.net"}]
#3 10:58:54 POST / → 400  application/json, 64 bytes
   [{"name":"Kiana.Rolfson","id":3,"email":"Wilmer71@example.net"}]
```

```log
10:59:30 ℹ️ ✨ Display content of topic error-responses, it contains 4 messages
CreateTime:2026-11-26 10:57:11.852|Partition:0|Offset:0|Headers:input_record_offset:0,...
CreateTime:2026-11-26 10:58:54.052|Partition:0|Offset:1|Headers:input_record_offset:0,...,response_content:{"error":"email: must be a company address"},status_code:400,...
CreateTime:2026-11-26 10:58:54.055|Partition:0|Offset:2|Headers:input_record_offset:1,...,response_content:{"error":"email: must be a company address"},status_code:400,...
CreateTime:2026-11-26 10:58:54.057|Partition:0|Offset:3|Headers:input_record_offset:2,...,response_content:{"error":"email: must be a company address"},status_code:400,...
```

<!-- select:end -->

👉 The API team rolls the rule back (`playground tools http-server set-response --status-code 200`). Send the 3 records again.

#### **📍 Step 4**
<!-- select:start -->
<!-- select-menu-labels: 🙋 See solution for previous step? -->
#### --No--
#### --Yes--

The 3 records were all refused, and they are all the records of the topic: rewind the connector to the start of the topic with [playground connector offsets reset](/playground%20connector%20offsets%20reset) (it stops the connector, deletes its offsets, and resumes it):

```bash
playground tools http-server set-response --status-code 200
playground connector offsets reset --connector http-sink
```

```log
11:00:28 ℹ️ 📥 3 request(s) received since the start or the last reset (3 kept)
#1 11:00:12 POST / → 200  application/json, 82 bytes
   [{"name":"Gage.Christiansen11","id":1,"email":"Eloise_Kerluke-Blick@example.net"}]
#2 11:00:12 POST / → 200  application/json, 75 bytes
   [{"name":"Madeline.DuBuque61","id":2,"email":"Lilliana_Kulas@example.net"}]
#3 11:00:12 POST / → 200  application/json, 64 bytes
   [{"name":"Kiana.Rolfson","id":3,"email":"Wilmer71@example.net"}]
```

```log
11:00:33 ℹ️ ✨ Display content of topic success-responses, it contains 3 messages
```

> [!WARNING]
> A reset sends the **whole** topic again. When only some records failed, use the `input_record_partition` / `input_record_offset` headers of `error-responses`: set the offset of the connector there with [playground connector offsets alter](/playground%20connector%20offsets%20alter), or send the records of `error-responses` again with a producer of your own.

<!-- select:end -->
🥁 So...is a 400 a connector problem? No: the data or the API changed. The connector just has to keep going, and keep what was refused.

#### **🎓 Next Steps**

* `report.errors.as` `http_response` writes the plain answer of the API as the value of the error records.
* Compare with the [Avro Converter exercise](/academy?id=avro-converter-unknown-magic-byte): an error of the converter goes to the dead letter queue, and `playground topic dlq replay` sends it again.
* Read the [🍪 Connector troubleshooting](/deep-dive-connector-troubleshooting.md) deep dive.

<!-- tabs:end -->

### Renamed sink connector writes every row again

<!-- tabs:start -->
#### **🔥 Description**

A team renames its connectors to follow a new naming convention: the JDBC sink `sink-1` becomes `postgres-orders-sink`. Kafka Connect has no rename, so they deleted `sink-1` and created `postgres-orders-sink` with the same config. Right after, every order is twice in the table.

💡 What you'll learn:

* Where a sink connector keeps its offsets, and why they are tied to its name.
* Create a connector that starts where another one stopped.

#### **🤯 Details**

Versions used:

* 🎯 CP: 8.4.1

* 🔗 JDBC sink (PostgreSQL): 10.9.10

Connector config (both names):

```json
{
  "connector.class": "io.confluent.connect.jdbc.JdbcSinkConnector",
  "connection.url": "jdbc:postgresql://postgres/postgres?user=myuser&password=mypassword&ssl=false",
  "topics": "orders",
  "auto.create": "true"
}
```

Reproduction model: [postgres-sink-repro-000015-renamed-connector-rereads-topic.sh](https://github.com/vdesabou/kafka-docker-playground/blob/master/academy/connect-connect-jdbc-postgresql-sink/postgres-sink-repro-000015-renamed-connector-rereads-topic.sh)

> [!NOTE]
> Do not read the model before the exercise: it contains the answer.

#### **📍 Step 1**

Run the example (or type `000015` and use the `fzf` completion of `-f`):

```bash
playground run -f academy/connect-connect-jdbc-postgresql-sink/postgres-sink-repro-000015-renamed-connector-rereads-topic.sh
```

`sink-1` writes 10 orders, then the "rename":

```log
11:01:35 ℹ️ ❌ 🌎onprem connector sink-1 has been deleted successfully
11:01:36 ℹ️ ✅ 🌎onprem connector postgres-orders-sink was successfully created
```

```log
 nb_rows | nb_orders
---------+-----------
      20 |        10
(1 row)
```

❔Questions:

* Where were the offsets of `sink-1`, and where are they now?
* Why did `postgres-orders-sink` start from the beginning of the topic?

#### **📍 Step 2**
<!-- select:start -->
<!-- select-menu-labels: 🙋 See solution for previous step? -->
#### --No--
#### --Yes--

> Where were the offsets of `sink-1`, and where are they now?

A sink connector is a consumer group, named `connect-<connector name>`:

```bash
playground consumer-group list
```

```log
11:02:22 ℹ️ 👥 Listing consumer groups
connect-sink-1
connect-postgres-orders-sink
```

The offsets of `sink-1` are still there, with nobody to use them:

```bash
playground consumer-group describe --group connect-sink-1
```

```log
Consumer group 'connect-sink-1' has no active members.

GROUP           TOPIC           PARTITION  CURRENT-OFFSET  LOG-END-OFFSET  LAG             CONSUMER-ID     HOST            CLIENT-ID
connect-sink-1  orders          0          10              10              0               -               -               -
```

> Why did `postgres-orders-sink` start from the beginning of the topic?

A new name is a new group, with no committed offset. A sink consumer then starts from the earliest record (`auto.offset.reset` is `earliest` for the sink connectors), and the JDBC sink inserts (`insert.mode` `insert`, no primary key): each order once more.

The opposite is also true: [playground connector delete](/playground%20connector%20delete) keeps the offsets, and a connector created again **with the same name** resumes where it stopped.

<!-- select:end -->

👉 Rename it the right way, to `orders-sink`: create it without starting it (`--initial-state STOPPED`), give it the offsets of the old one with [playground connector offsets alter](/playground%20connector%20offsets%20alter), then start it.

#### **📍 Step 3**
<!-- select:start -->
<!-- select-menu-labels: 🙋 See solution for previous step? -->
#### --No--
#### --Yes--

```bash
playground connector delete --connector postgres-orders-sink
playground connector create-or-update --connector orders-sink --initial-state STOPPED << EOF
{
  "connector.class": "io.confluent.connect.jdbc.JdbcSinkConnector",
  "tasks.max": "1",
  "connection.url": "jdbc:postgresql://postgres/postgres?user=myuser&password=mypassword&ssl=false",
  "topics": "orders",
  "auto.create": "true"
}
EOF
```

```log
11:06:03 ℹ️ ⛏️ Altering offsets for 🌎onprem connector orders-sink
11:06:03 ❗ ⚠️ connector orders-sink has no offset yet: write each entry in full, for example
   sink:   {"offsets": [{"partition": {"kafka_topic": "orders", "kafka_partition": 0}, "offset": {"kafka_offset": 10}}]}
```

The new connector has no offset: write the offset of `connect-sink-1` (`10`) in the file that opens, save and close it:

```json
{"offsets": [{"partition": {"kafka_topic": "orders", "kafka_partition": 0}, "offset": {"kafka_offset": 10}}]}
```

```log
{
  "message": "The Connect framework-managed offsets for this connector have been altered successfully. However, if this connector manages offsets externally, they will need to be manually altered in the system that the connector uses."
}
11:06:04 ℹ️ 🛑 connector orders-sink was STOPPED before the change: left STOPPED (playground connector resume --connector orders-sink to start it)
```

Then start it, and send 5 new orders:

```bash
playground connector resume --connector orders-sink
```

```log
orders-sink                    ✅ RUNNING  0:🟢 RUNNING                 -
```

```bash
playground db sql << 'EOF'
SELECT count(*) AS nb_rows FROM orders;
EOF
```

```log
 nb_rows
---------
      25
(1 row)
```

20 + 5: the new connector went on from offset 10. The 10 duplicates of the first "rename" are still in the table: delete them with SQL, and drop the groups that nobody uses any more with [playground consumer-group delete](/playground%20consumer-group%20delete).

<!-- select:end -->
🥁 So...what's in a name? The offsets.

#### **🎓 Next Steps**

* Read the [🍪 Offsets and lag](/deep-dive-offsets-and-lag.md) deep dive.
* Keep the group instead: `"consumer.override.group.id": "connect-sink-1"` in the config of the new connector (the worker must allow it: `connector.client.config.override.policy` `All`, the setting of the playground).
* Make the sink idempotent: `insert.mode` `upsert` with `pk.mode` `record_value` and `pk.fields` `id` turns a replay into updates of the same rows. Compare with the [duplicates after a worker crash](/academy?id=jdbc-sink-duplicates-in-the-table-after-a-worker-crash) exercise.
* A source connector has the same issue: its offsets are stored under its name in the `connect-offsets` topic.

<!-- tabs:end -->

### S3 sink: duplicated records in the bucket after a worker crash

<!-- tabs:start -->
#### **🔥 Description**

The data team counts the orders of the day in their S3 bucket (Athena on the Avro files): 18 orders, but the shop sent 9. The S3 sink connector is RUNNING, there is no error in the logs. The only event of the day: a connect worker crashed (OOM kill) and was restarted.

"The S3 sink is exactly-once, isn't it?"

💡 What you'll learn:

* Read what a sink wrote in a bucket, without the `aws` command line or downloading files by hand.
* Find the records written twice, and compare a bucket with its topic.
* When the S3 sink is exactly-once, and the setting that breaks it.

#### **🤯 Details**

Versions used:

* 🎯 CP: 8.4.1

* 🔗 S3 sink: latest

The bucket is in MinIO (an S3 compatible store), so no AWS account is needed. The customer writes one folder per hour of processing time; the exercise uses one folder per 10 seconds, so that it does not take hours.

Connector config:

```json
{
  "connector.class": "io.confluent.connect.s3.S3SinkConnector",
  "topics": "orders",
  "s3.bucket.name": "mybucket",
  "store.url": "http://minio:9000",
  "flush.size": "3",
  "storage.class": "io.confluent.connect.s3.storage.S3Storage",
  "format.class": "io.confluent.connect.s3.format.avro.AvroFormat",
  "partitioner.class": "io.confluent.connect.storage.partitioner.TimeBasedPartitioner",
  "partition.duration.ms": "10000",
  "path.format": "'date'=YYYY-MM-dd/'time'=HH-mm-ss",
  "locale": "en-US",
  "timezone": "UTC",
  "timestamp.extractor": "Wallclock"
}
```

Reproduction model: [s3-sink-repro-000016-s3-sink-duplicates-after-worker-crash.sh](https://github.com/vdesabou/kafka-docker-playground/blob/master/academy/connect-connect-minio-s3-sink/s3-sink-repro-000016-s3-sink-duplicates-after-worker-crash.sh)

> [!NOTE]
> Do not read the model before the exercise: it contains the answer.

#### **📍 Step 1**

Run the example (or type `000016` and use the `fzf` completion of `-f`):

```bash
playground run -f academy/connect-connect-minio-s3-sink/s3-sink-repro-000016-s3-sink-duplicates-after-worker-crash.sh
```

It sends 9 orders, waits for the first files, kills the connect worker and restarts it. At the end, the connector is RUNNING and the bucket holds 6 objects.

❔Questions:

* What is in the bucket? Which orders are there twice?
* Why does the sink write them again after the restart?

#### **📍 Step 2**
<!-- select:start -->
<!-- select-menu-labels: 🙋 See solution for previous step? -->
#### --No--
#### --Yes--

> What is in the bucket? Which orders are there twice?

[playground storage ls](/playground%20storage%20ls) lists the objects the connector wrote (the bucket, the folder and the credentials come from its config):

```bash
playground storage ls --connector minio-sink
```

```log
14:45:12 ℹ️ 🪣 s3://mybucket/topics (connector minio-sink), credentials of the connector
object                                                               size  modified
orders/date=2026-11-26/time=14-44-10/orders+0+0000000000.avro       284 B  2026-11-26 14:44:19
orders/date=2026-11-26/time=14-45-00/orders+0+0000000000.avro       284 B  2026-11-26 14:45:07
orders/date=2026-11-26/time=14-44-10/orders+0+0000000003.avro       284 B  2026-11-26 14:44:19
orders/date=2026-11-26/time=14-45-00/orders+0+0000000003.avro       284 B  2026-11-26 14:45:07
orders/date=2026-11-26/time=14-44-10/orders+0+0000000006.avro       284 B  2026-11-26 14:44:19
orders/date=2026-11-26/time=14-45-00/orders+0+0000000006.avro       284 B  2026-11-26 14:45:07

topic-partition                            objects     size first off.   last start  last modified
orders-0                                         6   1.7 KB          0            6  2026-11-26 14:45:07

🪣 6 object(s), 1.7 KB
```

The same object names (`orders+0+0000000000.avro`: topic, partition, first offset) are in two folders, 50 seconds apart. [playground storage cat](/playground%20storage%20cat) reads the records of the objects; `--summary` only prints the offsets each topic-partition covers:

```bash
playground storage cat --connector minio-sink --summary --max-objects 0
```

```log
14:45:13 ℹ️ 🪣 s3://mybucket/topics (connector minio-sink), credentials of the connector
14:45:14 ℹ️ 📄 reading 6 object(s)
topic-partition                           objects   records                offsets  continuity
orders-0                                        6        18                  0 → 8  🔁 3 overlap(s)
   🔁 orders-0: offsets 0-2 are in two objects (date=2026-11-26/time=14-44-10/orders+0+0000000000.avro and date=2026-11-26/time=14-45-00/orders+0+0000000000.avro): duplicates
   🔁 orders-0: offsets 3-5 are in two objects (date=2026-11-26/time=14-44-10/orders+0+0000000003.avro and date=2026-11-26/time=14-45-00/orders+0+0000000003.avro): duplicates
   🔁 orders-0: offsets 6-8 are in two objects (date=2026-11-26/time=14-44-10/orders+0+0000000006.avro and date=2026-11-26/time=14-45-00/orders+0+0000000006.avro): duplicates
📦 18 record(s) in 6 object(s)
```

Every order is there twice. [playground connector reconcile](/playground%20connector%20reconcile) compares the bucket with the topic, record by record:

```bash
playground connector reconcile --connector minio-sink
```

```log
14:45:21 ℹ️ 🪣 Reading every object of topic orders written by connector minio-sink (playground storage cat)
14:45:28 ℹ️ 🎓 an object is written every flush.size=3 records (or rotate.interval.ms): up to 2 record(s) per partition after the last object are still in the task, not lost
14:45:28 ℹ️ 📥 Reading every record of topic orders
14:45:38 ℹ️ 🧮 Comparing (sink connector minio-sink, deletes applied: false)
🔎 Sink connector: is every record of the topic orders in the objects in s3://mybucket/topics?

   📥 topic orders                         9 record(s)
   🪣 objects in s3://mybucket/topics      18 record(s)
   🔑 no key: records and rows compared as multisets of (id, product, quantity)

❌ Duplicated: 9
   record id="1", product="product1", quantity="1": 2 times in the bucket
   record id="2", product="product2", quantity="2": 2 times in the bucket
   record id="3", product="product3", quantity="3": 2 times in the bucket
   record id="4", product="product4", quantity="4": 2 times in the bucket
   record id="5", product="product5", quantity="5": 2 times in the bucket
   record id="6", product="product6", quantity="6": 2 times in the bucket
   record id="7", product="product7", quantity="7": 2 times in the bucket
   record id="8", product="product8", quantity="8": 2 times in the bucket
   record id="9", product="product9", quantity="9": 2 times in the bucket

✅ 9 matching

❌ duplicated: the same record is there several times
```

> Why does the sink write them again after the restart?

The worker died after uploading the 3 files, but before committing the offsets of the task (every `offset.flush.interval.ms`, 60 seconds by default). After the restart, the task reads the 9 orders again from the last committed offset: at-least-once, like any sink (see [JDBC sink: duplicates in the table after a worker crash](/academy?id=jdbc-sink-duplicates-in-the-table-after-a-worker-crash)).

The S3 sink is still exactly-once when it writes a record again to the **same object**: same folder, same name, the new upload replaces the old one. Here, the folder comes from `timestamp.extractor=Wallclock`, the time at which the task processes the record: 50 seconds later, it is another folder, and the records are written next to the first copy.

<!-- select:end -->

👉 Find the `timestamp.extractor` that puts a record in the same folder every time it is written, then run the same crash with it.

#### **📍 Step 3**
<!-- select:start -->
<!-- select-menu-labels: 🙋 See solution for previous step? -->
#### --No--
#### --Yes--

`Record` (the timestamp of the Kafka record) or `RecordField` (a field of the value, with `timestamp.field`): the same record always lands in the same folder. Delete the connector and create `minio-sink-fixed`, with `"timestamp.extractor": "Record"` and `"topics.dir": "topics-fixed"` (a clean folder), then crash the worker again:

```bash
playground connector delete --connector minio-sink
# create-or-update with the same config, "timestamp.extractor": "Record", "topics.dir": "topics-fixed"
playground storage wait-for-objects --connector minio-sink-fixed --min-expected-objects 3
playground container kill --container connect
playground container restart --container connect
```

Once the task has read the orders again (about a minute: the session of the killed worker times out first), the bucket still has 3 objects, rewritten in place:

```bash
playground storage cat --connector minio-sink-fixed --summary --max-objects 0
```

```log
14:47:24 ℹ️ 🪣 s3://mybucket/topics-fixed (connector minio-sink-fixed), credentials of the connector
14:47:24 ℹ️ 📄 reading 3 object(s)
topic-partition                           objects   records                offsets  continuity
orders-0                                        3         9                  0 → 8  ✅ contiguous
📦 9 record(s) in 3 object(s)
```

```bash
playground connector reconcile --connector minio-sink-fixed
```

```log
14:47:29 ℹ️ 🪣 Reading every object of topic orders written by connector minio-sink-fixed (playground storage cat)
14:47:34 ℹ️ 🎓 an object is written every flush.size=3 records (or rotate.interval.ms): up to 2 record(s) per partition after the last object are still in the task, not lost
14:47:34 ℹ️ 📥 Reading every record of topic orders
14:47:43 ℹ️ 🧮 Comparing (sink connector minio-sink-fixed, deletes applied: false)
🔎 Sink connector: is every record of the topic orders in the objects in s3://mybucket/topics-fixed?

   📥 topic orders                         9 record(s)
   🪣 objects in s3://mybucket/topics-fixed 9 record(s)
   🔑 no key: records and rows compared as multisets of (id, product, quantity)

✅ 9 matching

✅ complete: every record is on the other side, with the same values
```

<!-- select:end -->
🥁 So... the S3 sink is exactly-once only with a deterministic partitioner: `DefaultPartitioner`, `FieldPartitioner`, or `TimeBasedPartitioner` with `Record` / `RecordField`, and no `rotate.schedule.interval.ms` (also processing time).

#### **🎓 Next Steps**

* Read the "Exactly-once delivery" section of the [S3 sink documentation](https://docs.confluent.io/kafka-connectors/s3-sink/current/overview.html).
* `playground storage cat` decodes Avro, Parquet, JSON, CSV and gzip objects: `--records` prints only the records, one json per line, for `jq`. `--url s3://…`, `gs://…`, `az://…` read any bucket (GCS, Azure Blob, HDFS and SFTP too).
* Records written late (after their folder was closed) are another source of surprise with `Record`: see `timestamp.extractor` and `rotate.interval.ms` in the documentation.

<!-- tabs:end -->

### Broker: some records are lost, always for the same partitions

<!-- tabs:start -->
#### **🔥 Description**

After adding a third broker, a producer loses some records: `TimeoutException: Expiring N record(s)`, always for the
same partitions, while the others go through. Schema Registry sometimes does not start either.

💡 What you'll learn:

* The difference between `listeners` (where a broker listens) and `advertised.listeners` (where it tells clients and the other brokers to connect)
* Why the symptom looks random, and what it does to replication
* How the same mistake shows up on older clients and in ZooKeeper mode

#### **🤯 Details**

Versions used:

* 🎯 CP: 8.4.1 (KRaft: CP 8 or later)

* 🖥️ 3 brokers (ids 1, 2 and 3), 1 controller (id 4)

Reproduction model: [broker-repro-000019-not-leader-or-follower-copied-advertised-listeners.sh](https://github.com/vdesabou/kafka-docker-playground/blob/master/academy/environment-plaintext/broker-repro-000019-not-leader-or-follower-copied-advertised-listeners.sh)

#### **📍 Step 1**

Run the example:

```bash
playground run -f academy/environment-plaintext/broker-repro-000019-not-leader-or-follower-copied-advertised-listeners.sh
```

It creates a topic `orders` (6 partitions, 3 replicas) and sends 12 records, one per customer key, with the console
producer. Some of them fail after `delivery.timeout.ms` (20 seconds here):

```log
[2026-11-26 17:36:30,801] WARN [Producer clientId=console-producer] Received invalid metadata error in produce request on partition orders-1 due to org.apache.kafka.common.errors.NetworkException: Disconnected from node 1 Going to request metadata update now
[2026-11-26 17:36:50,590] ERROR Error when sending message to topic orders with key: 9 bytes, value: 7 bytes with error: (org.apache.kafka.clients.producer.internals.ErrorLoggingCallback)
org.apache.kafka.common.errors.TimeoutException: Expiring 1 record(s) for orders-0:20003 ms has passed since batch creation. The request has not been sent, or no server response has been received yet.
org.apache.kafka.common.errors.TimeoutException: Expiring 1 record(s) for orders-4:20003 ms has passed since batch creation. The request has not been sent, or no server response has been received yet.
```

```bash
18:40:02 ℹ️ 📍 Earliest and latest offsets per partition of topic orders
PARTITION  EARLIEST        LATEST          RECORDS
1          0               3               3
2          0               3               3
3          0               1               1
5          0               3               3
TOTAL                                      10
18:42:05 ❗ ⚠️ no offsets for partition(s) 0 (leader 3), 4 (leader 3): their leader did not answer, so they are not counted in TOTAL (playground broker health)
```

The partitions that fail change from one run to the other: compare with `playground topic describe --topic orders`.

❔Questions:

* What do the failing partitions have in common?
* What does `playground broker describe` say about the brokers?

#### **📍 Step 2**
<!-- select:start -->
<!-- select-menu-labels: 🙋 See solution for previous step? -->
#### --No--
#### --Yes--

> What do the failing partitions have in common?

Their leader is broker 3, and their ISR shrank to the leader alone:

```bash
	Topic: orders	Partition: 0	Leader: 3	Replicas: 3,1,2	Isr: 3
	Topic: orders	Partition: 1	Leader: 1	Replicas: 1,2,3	Isr: 1,2,3
	Topic: orders	Partition: 4	Leader: 3	Replicas: 3,1,2	Isr: 3
```

> What does `playground broker describe` say about the brokers?

```bash
playground broker describe
18:35:05 ℹ️ 🖥️ Brokers (CP 8.4.1)
ID  ENDPOINT      RACK  FENCED  CONTAINER
1   broker:9092   null  false   broker
2   broker2:9092  null  false   broker2 ⚠️ same endpoint as another broker
3   broker2:9092  null  false   broker3 ⚠️ same endpoint as another broker
```

and `playground broker health`:

```bash
18:35:46 🔥 ❌ brokers 2, 3 advertise the same endpoint broker2:9092: advertised.listeners copied from another broker? Clients and followers of one of them are sent to the other (requests time out, NOT_LEADER_OR_FOLLOWER, under-replicated partitions)
18:35:46 🔥 ❌ 36 under-replicated partitions
```

`broker3` listens on its own port, but its `advertised.listeners` was copied from `broker2`:

```yml
  broker3:
    environment:
      # 💥 copied from broker2: broker3 listens on its own port, but tells clients to connect to broker2
      KAFKA_ADVERTISED_LISTENERS: BROKER://broker2:9092,HOST://localhost:29392
```

A client asks any broker for the metadata, and learns that broker 3 is at `broker2:9092`. Every request for a partition
led by broker 3 goes to broker 2. The other partitions work, which is why it looks random. On CP 8.4 clients, the broker
detects the mix-up and asks the client to bootstrap again (`Rebootstrap requested by server due to cluster metadata
mismatch for cluster … and node 3`, at INFO in the client log), in a loop until `delivery.timeout.ms`. Older clients get
`NOT_LEADER_OR_FOLLOWER` for those partitions instead.

`BROKER` is also the inter-broker listener: the followers of the partitions led by broker 3 are sent to broker 2 too,
so they drop out of the ISR. When one of them is `_schemas-0` (Schema Registry) or a partition of `connect-offsets`,
those components are stuck as well, which is why it depends on the run.

<!-- select:end -->

* Fix `advertised.listeners` of `broker3` in the compose override, apply it, then check `broker health` and `topic get-offsets`.

#### **📍 Step 3**
<!-- select:start -->
<!-- select-menu-labels: 🙋 See solution for previous step? -->
#### --No--
#### --Yes--

With `KAFKA_ADVERTISED_LISTENERS: BROKER://broker3:9092,HOST://localhost:29392`, a plain
[playground container recreate](/playground%20container%20recreate) is enough: nothing about the listeners is stored in the data folder.

```bash
playground container recreate
playground broker health --wait-healthy
18:42:29 ℹ️ ⏳ cluster not healthy yet (brokers down: 3, 158 under-replicated partitions, 36 under min ISR, 36 unavailable), waiting... (6s/180s)
18:42:40 ℹ️ ✅ all brokers are registered: 1,2,3
18:42:40 ℹ️ ✅ no under-replicated partition
18:42:40 ℹ️ ✅ cluster is healthy
```

Every partition answers again: `playground topic get-offsets --topic orders` lists the 6 partitions, without a warning.

<!-- select:end -->
🥁 So...did you learn the difference between `listeners` and `advertised.listeners`?

#### **🎓 Next Steps**

* In ZooKeeper mode (CP 7.x), the same mistake stops the broker at startup: `Configured end points broker2:9092 in advertised listeners are already registered by broker 2`. KRaft accepts it, which makes it much harder to spot.
* `kafka-broker-api-versions --bootstrap-server broker:9092 | grep '(id:'` shows the same thing as `broker describe`: two ids behind one address.

<!-- tabs:end -->


### HTTP sink: the same records are sent again and again

<!-- tabs:start -->
#### **🔥 Description**

Since the API behind an HTTP sink got slower, it receives every record several times. The connector is RUNNING, its
task too, and the lag never goes down.

💡 What you'll learn:

* The poll loop of a sink task, and what `max.poll.interval.ms` protects
* Why a task kicked out of its group stays RUNNING, and delivers the same records again
* What to tune: `max.poll.records`, the batch, or `max.poll.interval.ms`

#### **🤯 Details**

Versions used:

* 🎯 CP: 8.4.1

* 🔗 HTTP sink: latest

Reproduction model: [http-sink-repro-000023-records-sent-again-max-poll-interval.sh](https://github.com/vdesabou/kafka-docker-playground/blob/master/academy/connect-connect-http-sink/http-sink-repro-000023-records-sent-again-max-poll-interval.sh)

#### **📍 Step 1**

Run the example:

```bash
playground run -f academy/connect-connect-http-sink/http-sink-repro-000023-records-sent-again-max-poll-interval.sh
```

The API answers in 2 seconds, the connector sends one record per request (`batch.max.size=1`), and 30 records were
produced. Two minutes later:

```bash
http-sink                      ✅ RUNNING  0:🟢 RUNNING                 -
19:30:39 ℹ️ 🐢 consumer lag for 🌎onprem connector http-sink is not available (no offset committed yet)
topic: http-messages partition: 0   current-offset: -          end-offset: 30         lag: -          []   0%
```

And the API received the record `{"order": 7}` once a minute:

```bash
playground tools http-server requests --grep '"order": 7}'
19:33:34 ℹ️ 📥 153 request(s) received since the start or the last reset (153 kept), 5 matching
#7 19:28:39 POST / → 200  text/plain; charset=UTF-8, 12 bytes
#37 19:29:39 POST / → 200  text/plain; charset=UTF-8, 12 bytes
#67 19:30:39 POST / → 200  text/plain; charset=UTF-8, 12 bytes
#97 19:31:40 POST / → 200  text/plain; charset=UTF-8, 12 bytes
#127 19:32:40 POST / → 200  text/plain; charset=UTF-8, 12 bytes
```

❔Questions:

* Why are no offsets committed, although every request succeeds?
* What does `playground connector diagnose` say?

#### **📍 Step 2**
<!-- select:start -->
<!-- select-menu-labels: 🙋 See solution for previous step? -->
#### --No--
#### --Yes--

> What does `playground connector diagnose` say?

```bash
playground connector diagnose --connector http-sink
🔴 ERROR x2 (first seen line 5897, last seen line 5934)
[2026-11-26 18:29:25,589] ERROR [http-sink|task-0] WorkerSinkTask{id=http-sink-0} Commit of offsets threw an unexpected exception for sequence number 1: {http-messages-0=OffsetAndMetadata{offset=30, …
    org.apache.kafka.clients.consumer.CommitFailedException: Offset commit cannot be completed since the consumer is not part of an active group for auto partition assignment; it is likely that the consumer was kicked out of the group.

19:32:13 ❗ 🐢 consumer group connect-http-sink of 🌎onprem connector http-sink has no active member and no committed offset: its task is not in the group right now (starting, rebalancing, or kicked out after max.poll.interval.ms: CommitFailedException in the worker log)

19:33:18 ℹ️ 👉 4/4 next steps
   🐢 a task was kicked out of its consumer group (CommitFailedException): more than max.poll.interval.ms (20000) between two polls, so its offsets are not committed and the records are delivered again. Lower consumer.override.max.poll.records or make each batch faster, or raise consumer.override.max.poll.interval.ms
```

> Why are no offsets committed, although every request succeeds?

A sink task runs a loop: `poll()` returns up to `max.poll.records` records (500 by default), the task sends them all,
then polls again and commits the offsets of what it delivered. If two polls are more than `max.poll.interval.ms`
apart, the consumer considers the task stuck and leaves the group. Here, 30 records × 2 seconds is 60 seconds between
two polls, and the customer lowered `max.poll.interval.ms` to 20 seconds ("to detect stuck tasks faster"):

```json
"batch.max.size": "1",
"consumer.override.max.poll.interval.ms": "20000"
```

The commit then fails (`CommitFailedException`), the task joins the group again, gets the partition back from the last
committed offset (none), and sends the same 30 records again, forever. The task never fails: it stays RUNNING.

<!-- select:end -->

* Change the configuration so that the records are sent once, and check the lag.

#### **📍 Step 3**
<!-- select:start -->
<!-- select-menu-labels: 🙋 See solution for previous step? -->
#### --No--
#### --Yes--

Remove `consumer.override.max.poll.interval.ms` (back to 300000 ms, 5 minutes) with
[playground connector create-or-update](/playground%20connector%20create-or-update), then:

```bash
playground connector show-lag --connector http-sink --max-wait 180
19:35:07 ℹ️ 🏁 consumer lag for 🌎onprem connector http-sink is 0 ! took: 1min 7sec
topic: http-messages partition: 0   current-offset: 30         end-offset: 30         lag: 0          [🔹🔹🔹🔹🔹🔹🔹🔹🔹🔹🔹🔹🔹🔹🔹🔹🔹🔹🔹🔹] 100% 🏁
```

The other ways out, often better: a smaller `consumer.override.max.poll.records` (fewer records per poll), or a
bigger `batch.max.size` (fewer requests for the same records). A slow API with 500 records per poll can exceed even
5 minutes.

<!-- select:end -->
🥁 So...did you learn what max.poll.interval.ms protects?

#### **🎓 Next Steps**

* Keep `max.poll.interval.ms` at 20 seconds and set `consumer.override.max.poll.records` to 5: is it enough?
* Read the [🍪 offsets and lag](/deep-dive-offsets-and-lag.md) deep dive: where a sink connector keeps its offsets, and how to read them.

<!-- tabs:end -->


## ⭐⭐⭐ Advanced

### JDBC sink RUNNING, but no data in the table

<!-- tabs:start -->
#### **🔥 Description**

A JDBC sink connector is RUNNING, its task is RUNNING, there is no error in the logs... but no data arrives in the PostgreSQL table.

💡 What you'll learn:

* Troubleshoot a connector that is RUNNING but does nothing: no error to read, so you have to choose the right tools.
* Follow the lag, take and analyze thread dumps, and look at the sessions and locks of the database.
* Turn a silent wait into a visible error.

#### **🤯 Details**

Versions used:

* 🎯 CP: 8.4.1

* 🔗 JDBC sink (PostgreSQL): 10.9.10

Connector config:

```json
{
  "connector.class": "io.confluent.connect.jdbc.JdbcSinkConnector",
  "tasks.max": "1",
  "connection.url": "jdbc:postgresql://postgres/postgres?user=myuser&password=mypassword&ssl=false",
  "topics": "orders",
  "auto.create": "true"
}
```

Reproduction model: [postgres-sink-repro-000006-sink-running-but-no-data.sh](https://github.com/vdesabou/kafka-docker-playground/blob/master/academy/connect-connect-jdbc-postgresql-sink/postgres-sink-repro-000006-sink-running-but-no-data.sh)

> [!NOTE]
> Do not read the model before the exercise: it contains the answer.

#### **📍 Step 1**

Run the example (or type `000006` and use the `fzf` completion of `-f`):

```bash
playground run -f academy/connect-connect-jdbc-postgresql-sink/postgres-sink-repro-000006-sink-running-but-no-data.sh
```

10 records are produced to topic `orders`, and the connector is RUNNING:

```log
postgres-sink                  ✅ RUNNING  0:🟢 RUNNING                 -
```

But the table is empty:

```log
 count
-------
     0
(1 row)
```

❔Questions:

* Is the connector doing anything?
* What is the first command you run?

> [!TIP]
> Be quick: after 5 minutes (`max.poll.interval.ms`), the consumer of the task leaves its group and the picture changes. `playground re-run` starts over.

#### **📍 Step 2**
<!-- select:start -->
<!-- select-menu-labels: 🙋 See solution for previous step? -->
#### --No--
#### --Yes--

[playground connector diagnose](/playground%20connector%20diagnose) finds no error, and no progress:

```bash
playground connector diagnose --connector postgres-sink
```

```log
13:48:53 ℹ️ 🔥 2/4 errors: digest of connect ERROR/FATAL records since 1h (whole worker, not only this connector)
✅ no ERROR/FATAL record found in 4344 lines

13:48:53 ℹ️ 🐢 3/4 progress: consumer lag of sink postgres-sink
13:48:56 ❗ 🐢 consumer lag for 🌎onprem connector postgres-sink is not available (no offset committed yet), check the connector status if this persists
topic: orders     partition: 0   current-offset: -          end-offset: 10         lag: -          []   0%

13:49:00 ℹ️ 👉 4/4 next steps
   🐌 RUNNING but no progress? run this command again, then take a thread dump if lag or offsets do not move
```

Run [playground connector show-lag](/playground%20connector%20show-lag) `--once` a few times: the connector has not committed a single offset, and nothing moves.

```bash
playground connector show-lag --connector postgres-sink --once
13:49:03 ℹ️ 🐢 consumer lag for 🌎onprem connector postgres-sink is not available (no offset committed yet)
topic: orders     partition: 0   current-offset: -          end-offset: 10         lag: -          []   0%
```

A task that is RUNNING, with no error and no progress, is waiting for something. What is its thread doing?

<!-- select:end -->

👉 Take thread dumps of the `connect` worker and analyze them: what is the task thread of `postgres-sink` doing?

> [!TIP]
> One dump says what a thread does at that moment; 3 dumps a few seconds apart say whether it is stuck. [playground analyze thread-dump](/playground%20analyze%20thread-dump) `--container connect` takes 3 and analyzes them.

#### **📍 Step 3**
<!-- select:start -->
<!-- select-menu-labels: 🙋 See solution for previous step? -->
#### --No--
#### --Yes--

```bash
playground analyze thread-dump --container connect
```

```log
── Findings ──────────────────────────────────────────────────────────────────
  [HIGH] Connect task thread "task-thread-postgres-sink-0" is RUNNABLE on the same frames in all 3 dumps (11.2s apart), in org.postgresql.core.VisibleBufferedInputStream.readMore(VisibleBufferedInputStream.java:192), using no CPU. It is inside io.confluent.connect.jdbc.sink.JdbcSinkTask.put, in a socket read: the sink waits for its external system (a lock, a slow query, a dead connection on the other side), look there.

── Kafka Connect ─────────────────────────────────────────────────────────────
  task    postgres-sink                  #0   RUNNABLE      STUCK  org.postgresql.core.VisibleBufferedInputStream.readMore(VisibleBuffere
```

The stack of the task thread, in the dump:

```log
"task-thread-postgres-sink-0" #235 [433] prio=5 os_prio=0 cpu=170.40ms elapsed=68.32s tid=0x0000fffe800ec360 nid=433 runnable  [0x0000fffe6ab70000]
   java.lang.Thread.State: RUNNABLE
	at sun.nio.ch.Net.poll(java.base@25.0.5/Native Method)
	...
	at org.postgresql.core.VisibleBufferedInputStream.readMore(VisibleBufferedInputStream.java:192)
	...
	at org.postgresql.core.v3.QueryExecutorImpl.execute(QueryExecutorImpl.java:674)
	at org.postgresql.jdbc.PgStatement.executeBatch(PgStatement.java:924)
	at org.postgresql.jdbc.PgPreparedStatement.executeBatch(PgPreparedStatement.java:1778)
	at io.confluent.connect.jdbc.sink.BufferedRecords.executeUpdates(BufferedRecords.java:199)
	at io.confluent.connect.jdbc.sink.BufferedRecords.flush(BufferedRecords.java:189)
	at io.confluent.connect.jdbc.sink.JdbcDbWriter.write(JdbcDbWriter.java:86)
	at io.confluent.connect.jdbc.sink.JdbcSinkTask.put(JdbcSinkTask.java:87)
	at org.apache.kafka.connect.runtime.WorkerSinkTask.deliverMessages(WorkerSinkTask.java:708)
```

Read it from the bottom: the worker delivers the records to `JdbcSinkTask.put()`, which sends the batch of INSERTs (`executeBatch`), and the driver waits for the answer of PostgreSQL in a socket read. The task is not idle: it is waiting for the database, and the database does not answer.

> [!NOTE]
> An idle sink task waits in `KafkaConsumer.poll()` for new records. A sink task in a socket read inside `put()` is waiting for its external system.

<!-- select:end -->

👉 Find out why PostgreSQL does not answer the INSERT.

> [!TIP]
> [playground db sql](/playground%20db%20sql) runs SQL in the database of the example. PostgreSQL shows its sessions in `pg_stat_activity`, and `pg_blocking_pids(pid)` tells which sessions block one.

#### **📍 Step 4**
<!-- select:start -->
<!-- select-menu-labels: 🙋 See solution for previous step? -->
#### --No--
#### --Yes--

The sessions of the database:

```bash
playground db sql << 'EOF'
SELECT pid, application_name, state, wait_event_type, wait_event, pg_blocking_pids(pid) AS blocked_by, now() - xact_start AS xact_age, left(query, 60) AS query
FROM pg_stat_activity
WHERE datname = 'postgres' AND pid <> pg_backend_pid()
ORDER BY xact_start;
EOF
```

```log
 pid |    application_name    |        state        | wait_event_type | wait_event | blocked_by |    xact_age     |                            query
-----+------------------------+---------------------+-----------------+------------+------------+-----------------+--------------------------------------------------------------
  81 | nightly-batch          | idle in transaction | Client          | ClientRead | {}         | 00:04:57.121641 | LOCK TABLE orders IN SHARE MODE;
  85 | PostgreSQL JDBC Driver | active              | Lock            | relation   | {81}       | 00:04:40.432392 | INSERT INTO "postgres"."public"."orders" ("id","product","qu
```

* The INSERT of the connector (`PostgreSQL JDBC Driver`) waits for a lock (`wait_event_type` `Lock`), blocked by session `81`.
* Session `81`, `nightly-batch`, is `idle in transaction`: it started a transaction 5 minutes ago, locked the table, and is doing nothing. Its transaction stays open until it commits, rolls back, or is ended.

The locks on the table confirm it:

```bash
playground db sql << 'EOF'
SELECT l.pid, a.application_name, l.mode, l.granted, c.relname
FROM pg_locks l JOIN pg_class c ON c.oid = l.relation JOIN pg_stat_activity a ON a.pid = l.pid
WHERE c.relname = 'orders';
EOF
```

```log
 pid |    application_name    |       mode       | granted | relname
-----+------------------------+------------------+---------+---------
  81 | nightly-batch          | ShareLock        | t       | orders
  85 | PostgreSQL JDBC Driver | RowExclusiveLock | f       | orders
```

A `SHARE` lock lets `SELECT` run (that is why `count(*)` answered 0), but blocks every `INSERT`, `UPDATE` and `DELETE` until its transaction ends.

<!-- select:end -->

👉 Unblock the connector, and check that the data arrives.

#### **📍 Step 5**
<!-- select:start -->
<!-- select-menu-labels: 🙋 See solution for previous step? -->
#### --No--
#### --Yes--

In real life, find who owns the `nightly-batch` session and have it commit or roll back. Here, end it:

```bash
playground db sql << 'EOF'
SELECT pid, pg_terminate_backend(pid) FROM pg_stat_activity WHERE application_name = 'nightly-batch';
EOF
```

The INSERT gets its lock right away, and the connector catches up:

```bash
playground connector show-lag --connector postgres-sink --once
13:53:28 ℹ️ 🐢 consumer lag for 🌎onprem connector postgres-sink is 0
topic: orders     partition: 0   current-offset: 10         end-offset: 10         lag: 0          [🔹🔹🔹🔹🔹🔹🔹🔹🔹🔹🔹🔹🔹🔹🔹🔹🔹🔹🔹🔹] 100% 🏁
```

```bash
playground db sql << 'EOF'
SELECT count(*) FROM orders;
EOF
```

```log
 count
-------
    10
(1 row)
```

No error at any time: from the outside, the connector was just "slow".

<!-- select:end -->

👉 How could the connector have reported the problem instead of waiting silently?

#### **📍 Step 6**
<!-- select:start -->
<!-- select-menu-labels: 🙋 See solution for previous step? -->
#### --No--
#### --Yes--

Bound the wait on the database side: a `lock_timeout` on the sessions of the connector. With the PostgreSQL driver, set it in the connection URL (`options=-c lock_timeout=10s`, URL-encoded), and keep the retries of the connector short:

```json
"connection.url": "jdbc:postgresql://postgres/postgres?user=myuser&password=mypassword&ssl=false&options=-c%20lock_timeout%3D10s",
"max.retries": "2",
"retry.backoff.ms": "5000"
```

Start a `nightly-batch` session again, produce one record, and the task now fails with an explicit error after its retries:

```log
postgres-sink                  ✅ RUNNING  0:🛑 FAILED                   tasks: org.apache.kafka.connect.errors.ConnectException: Exiting WorkerSinkTask due to unrecoverable exception.
Caused by: org.apache.kafka.connect.errors.ConnectException: java.sql.SQLException: Exception chain:
java.sql.BatchUpdateException: Batch entry 0 INSERT INTO "postgres"."public"."orders" ("id","product","quantity","price") VALUES (('1000'::int4),('after the fix'),('1'::int4),('1.0'::real)) was aborted: ERROR: canceling statement due to lock timeout
org.postgresql.util.PSQLException: ERROR: canceling statement due to lock timeout
```

A FAILED task is visible to monitoring and to `connector status`; a task waiting forever is not. The same setting can be set on the database user (`ALTER ROLE myuser SET lock_timeout = '10s'`), which also covers the sessions opened by other tools.

<!-- select:end -->
🥁 So...could you find why a RUNNING connector did nothing?

#### **🎓 Next Steps**

* Read the [🍪 JVM diagnostics](/deep-dive-jvm-diagnostics.md) deep dive (thread dumps, flight recordings) and the [🍪 offsets and lag](/deep-dive-offsets-and-lag.md) one.
* Try the same with a slow query instead of a lock: `ALTER ROLE myuser SET statement_timeout = '10s'` bounds it the same way.
* What to ask a customer in this situation: 3 thread dumps of the worker a few seconds apart, `show-lag` (or the consumer group offsets) over a few minutes, and the sessions of the database (`pg_stat_activity` with `pg_blocking_pids`) while the connector is stuck.
* Try `playground analyze thread-dump --sample stuck_sink_put`: the 3 dumps of this exercise.

<!-- tabs:end -->

### JDBC sink: duplicates in the table after a worker crash

<!-- tabs:start -->
#### **🔥 Description**

The topic has 10 orders, but after a crash of the Connect worker the table has 20 rows. Is the connector buggy?

💡 What you'll learn:

* Find lost and duplicated records between a topic and a table, without counting rows by hand.
* Understand when a sink commits its offsets, and why Kafka Connect delivers *at least once*.
* Make a sink idempotent, so that a redelivery does no harm.

#### **🤯 Details**

Versions used:

* 🎯 CP: 8.4.1

* 🔗 JDBC sink (PostgreSQL): 10.9.10

Connector config (the defaults of the JDBC sink: `insert.mode` `insert`, `pk.mode` `none`):

```json
{
  "connector.class": "io.confluent.connect.jdbc.JdbcSinkConnector",
  "tasks.max": "1",
  "connection.url": "jdbc:postgresql://postgres/postgres?user=myuser&password=mypassword&ssl=false",
  "topics": "orders",
  "auto.create": "true"
}
```

Reproduction model: [postgres-sink-repro-000007-duplicates-after-worker-crash.sh](https://github.com/vdesabou/kafka-docker-playground/blob/master/academy/connect-connect-jdbc-postgresql-sink/postgres-sink-repro-000007-duplicates-after-worker-crash.sh)

#### **📍 Step 1**

Run the example (or type `000007` and use the `fzf` completion of `-f`):

```bash
playground run -f academy/connect-connect-jdbc-postgresql-sink/postgres-sink-repro-000007-duplicates-after-worker-crash.sh
```

The connector writes the 10 orders, then the worker is killed (like an OOM kill, or a lost node) and restarted. The connector is RUNNING, but:

```log
 count
-------
    20
(1 row)
```

❔Questions:

* Which rows are duplicated, and is anything lost?
* Why did the crash create them?

#### **📍 Step 2**
<!-- select:start -->
<!-- select-menu-labels: 🙋 See solution for previous step? -->
#### --No--
#### --Yes--

> Which rows are duplicated, and is anything lost?

[playground connector reconcile](/playground%20connector%20reconcile) reads the topic and the table of the connector, and compares them record by record:

```bash
playground connector reconcile --connector postgres-sink
```

```log
🔎 Sink connector: is every record of the topic orders in the table orders?

   📥 topic orders                         10 record(s)
   🛢️  table orders                         20 row(s)
   🔑 no key: records and rows compared as multisets of (id, price, product, quantity)

❌ Duplicated: 10
   record id="1", price="0.77929", product="Brianne", quantity="2": 2 times in the table
   record id="11", price="0.503262", product="Renee", quantity="12": 2 times in the table
   ...

✅ 10 matching

❌ duplicated: the same record is there several times
```

Nothing is lost: every record of the topic is in the table, twice.

> Why did the crash create them?

A sink task commits the offsets of what it wrote every `offset.flush.interval.ms` (60 seconds by default, a setting of the worker), not after each write. The worker was killed a few seconds after writing the 10 rows, before its first commit:

```bash
playground container logs -c connect --grep "offset.flush.interval.ms" --no-follow
	offset.flush.interval.ms = 60000
```

When the worker came back, the task found no committed offset (`Found no committed offset for partition orders-0` in the logs) and read the topic from the beginning: the same 10 records were written a second time. Kafka Connect delivers *at least once*: after a crash, the records since the last commit are delivered again, and the sink must cope with it.

> [!NOTE]
> A graceful stop (`playground connector restart`, a rolling restart of the workers) commits the offsets first: only a crash redelivers. The task also waits for the member of the dead worker to leave its consumer group (`session.timeout.ms`, 45 seconds by default) before it starts again.

<!-- select:end -->

👉 Change the connector so that a crash no longer creates duplicates, then check it with the same crash.

> [!TIP]
> With `insert.mode` `insert`, every record is a new `INSERT`. Look at the other modes of the [JDBC sink](https://docs.confluent.io/kafka-connectors/jdbc/current/sink-connector/sink_config_options.html), and at `pk.mode` / `pk.fields`.

#### **📍 Step 3**
<!-- select:start -->
<!-- select-menu-labels: 🙋 See solution for previous step? -->
#### --No--
#### --Yes--

Make the writes idempotent: an upsert on a primary key writes the same row again instead of adding one. The records have an `id` field:

```json
"insert.mode": "upsert",
"pk.mode": "record_value",
"pk.fields": "id"
```

To check it in the same environment, create a second connector on a new table, then crash the worker again:

```bash
playground connector create-or-update --connector postgres-sink-upsert << 'EOF'
{
  "connector.class": "io.confluent.connect.jdbc.JdbcSinkConnector",
  "tasks.max": "1",
  "connection.url": "jdbc:postgresql://postgres/postgres?user=myuser&password=mypassword&ssl=false",
  "topics": "orders",
  "table.name.format": "orders_upsert",
  "auto.create": "true",
  "insert.mode": "upsert",
  "pk.mode": "record_value",
  "pk.fields": "id"
}
EOF
playground db wait-for-rows --table orders_upsert --min-expected-rows 10
playground container kill --container connect
playground container restart --container connect
```

About a minute later, the task has read the 10 records again (`Found no committed offset` again), but:

```bash
playground connector reconcile --connector postgres-sink-upsert
```

```log
🔎 Sink connector: is every record of the topic orders in the table orders_upsert?

   📥 topic orders                         10 record(s), 10 key(s)
   🛢️  table orders_upsert                  10 row(s), 10 key(s)
   🔑 key: id (pk.fields, pk.mode record_value)

✅ 10 matching

✅ complete: every record is on the other side, with the same values
```

The redelivery happened, and did no harm.

<!-- select:end -->
🥁 So...is the connector buggy?

#### **🎓 Next Steps**

* Read the [🍪 offsets and lag](/deep-dive-offsets-and-lag.md) deep dive.
* `pk.mode` `kafka` (topic, partition, offset as the key) also makes the writes idempotent, for records without a natural key.
* What to tell a customer with duplicates after a crash: it is the expected *at least once* delivery; make the sink idempotent (upsert on a key) or deduplicate downstream. Lowering `offset.flush.interval.ms` reduces the window, it does not close it.

<!-- tabs:end -->

### HTTP sink timeouts: is it the server or the network?

<!-- tabs:start -->
#### **🔥 Description**

An HTTP sink connector fails with `java.net.SocketTimeoutException: Read timed out`. The team that owns the API says its server answers in a few milliseconds.

💡 What you'll learn:

* Tell a slow server from a slow network, with a network capture.
* Understand what a timeout and a retry do to an HTTP API.
* Use the HTTP server of the examples to see what the API received.

#### **🤯 Details**

Versions used:

* 🎯 CP: 8.4.1

* 🔗 HTTP sink: 1.7.15

The connector config of the customer: the API usually answers in a few milliseconds, so 1 second looked like plenty.

```json
"http.api.url": "http://httpserver:9006",
"http.request.timeout.ms": "1000",
"max.retries": "2",
"retry.backoff.ms": "1000"
```

Reproduction model: [http-sink-repro-000008-http-sink-timeouts-slow-network.sh](https://github.com/vdesabou/kafka-docker-playground/blob/master/academy/connect-connect-http-sink/http-sink-repro-000008-http-sink-timeouts-slow-network.sh)

> [!NOTE]
> Do not read the model before the exercise: it contains the answer.

#### **📍 Step 1**

Run the example (or type `000008` and use the `fzf` completion of `-f`):

```bash
playground run -f academy/connect-connect-http-sink/http-sink-repro-000008-http-sink-timeouts-slow-network.sh
```

The task fails after its retries:

```log
http-sink                      ✅ RUNNING  0:🛑 FAILED                   tasks: org.apache.kafka.connect.errors.ConnectException: Exiting WorkerSinkTask due to unrecoverable exception.
Caused by: Error while processing HTTP request with Url : http://httpserver:9006, Error Message : Exception while processing HTTP request for a batch of 1 records., Exception : java.net.SocketTimeoutException: Read timed out
```

❔Questions:

* Did the API receive anything?
* Is the API slow, or is it the network?

#### **📍 Step 2**
<!-- select:start -->
<!-- select-menu-labels: 🙋 See solution for previous step? -->
#### --No--
#### --Yes--

> Did the API receive anything?

The HTTP server of the examples keeps the requests it received: [playground tools http-server requests](/playground%20tools%20http-server%20requests):

```bash
playground tools http-server requests
14:40:50 ℹ️ 🌐 answers: 200 after 0 ms, body {"message":"Hello, World!"}
14:40:50 ℹ️ 📥 3 request(s) received since the start or the last reset (3 kept)
#1 14:39:59 POST / → 200  application/json, 69 bytes
   [{"name":"Gus_Schoen1","id":1,"email":"Leanna.Gottlieb@example.net"}]
#2 14:40:01 POST / → 200  application/json, 69 bytes
   [{"name":"Gus_Schoen1","id":1,"email":"Leanna.Gottlieb@example.net"}]
#3 14:40:04 POST / → 200  application/json, 69 bytes
   [{"name":"Gus_Schoen1","id":1,"email":"Leanna.Gottlieb@example.net"}]
```

The server received the **same record 3 times** (the request and its 2 retries) and answered `200` right away each time. For the connector it failed; for the API it succeeded, 3 times. A retry after a timeout sends the request again: the API must be idempotent, or it gets duplicates.

So the server is not slow. Then where do the seconds go?

<!-- select:end -->

👉 Capture the traffic between the worker and the API while the connector retries, and find where the time goes.

> [!TIP]
> [playground debug tcp-dump](/playground%20debug%20tcp-dump) captures the traffic of a container and analyzes it. Start the capture, then restart the connector so that it sends its requests again.

#### **📍 Step 3**
<!-- select:start -->
<!-- select-menu-labels: 🙋 See solution for previous step? -->
#### --No--
#### --Yes--

In one terminal:

```bash
playground debug tcp-dump --container connect --port 9006 --duration 25
```

In another one, during the capture:

```bash
playground connector restart --connector http-sink
```

```log
🔎 Findings
   🟠 HIGH: 3 HTTP response(s) of POST / on httpserver:9006 arrived after the client gave up: the server answered after 1504.28 ms (median), but the client closed the connection after 1005.64 ms (FIN). The client timeout is shorter than the response time seen on the network (an HTTP client timeout, like http.request.timeout.ms of the HTTP sink): the request may have been processed anyway, and a retry sends it again.
   🟡 MEDIUM: 6 reset(s) connect → httpserver:9006 on established connection(s): a peer closed the connection abruptly (process stopped, idle timeout of a proxy or load balancer, protocol error).
   🟡 MEDIUM: HTTP POST / on httpserver:9006 is slow: p95 1504.35 ms, max 1504.35 ms.

🔌 TCP: 6 conversation(s), 3 connection(s) opened, 6 reset(s), 0 retransmission(s) (0.0%), 0 zero window(s)
   handshake (SYN → SYN/ACK): p50 1501.51 ms, p95 1502.93 ms, max 1502.93 ms

🌍 HTTP: 3 request(s), 3 response(s) (200 x3)
        3  POST / on httpserver:9006   p50 1504.28 ms, p95 1504.35 ms   200 x3, 3 after the client gave up
```

Read it like this:

* **Each response arrived after the connector gave up.** The connector closed each connection 1 s after its request (its `http.request.timeout.ms`), the `200` came 1.5 s after the request, and the connector answered it with a reset (the resets `connect → httpserver`). That is why the server saw successful requests while the connector saw timeouts.
* **The TCP handshake takes 1.5 s too.** A SYN/ACK is sent by the kernel of the server, not by the application: when the handshake itself is slow, the time is spent on the network, whatever the application does.

The server answers in 0 ms, the network adds 1.5 s: it is the network.

> [!TIP]
> The 3 attempts of this exercise are a sample: `playground analyze tcp-dump --sample http_client_timeout`.

<!-- select:end -->

👉 What is wrong with this network, and what are the fixes?

#### **📍 Step 4**
<!-- select:start -->
<!-- select-menu-labels: 🙋 See solution for previous step? -->
#### --No--
#### --Yes--

The model degraded the network on purpose, with [playground debug degrade-traffic](/playground%20debug%20degrade-traffic) (the playground way to add latency, loss or a rate limit to a container):

```bash
playground debug degrade-traffic --container httpserver --action status
14:46:03 ℹ️ 🔎 Traffic degradation of container httpserver
   eth0: qdisc netem 10: parent 1:1 limit 1000 delay 1.5s
```

The fixes, depending on what you can change:

* **The network**: in real life, the VPN, proxy or link that adds the latency. Here: `playground debug degrade-traffic --container httpserver --action stop`, then `playground connector restart --connector http-sink`.
* **The timeout**: above the real latency of the path, not of the server alone. With `"http.request.timeout.ms": "10000"`, the 10 records reach the API, slowly:

  ```bash
  playground tools http-server requests --last 3
  #18 14:45:28 POST / → 200  application/json, 83 bytes
     [{"name":"Chris.Thompson-Lind","id":8,"email":"Rodger.Herman-Kling94@example.org"}]
  #19 14:45:30 POST / → 200  application/json, 68 bytes
     [{"name":"Jerel_Kris","id":9,"email":"Eldon.McDermott@example.net"}]
  #20 14:45:31 POST / → 200  application/json, 68 bytes
     [{"name":"Florian17","id":10,"email":"Aric_Berge-Cole@example.net"}]
  ```

* **The throughput**: the HTTP sink sends one record per request by default (`batch.max.size` 1). With a slow network, each request pays the latency: batching (`batch.max.size`, with a `request.body.format` the API accepts) pays it once for many records.

<!-- select:end -->
🥁 So...the server or the network?

#### **🎓 Next Steps**

* Read the [🍪 A slow or broken network, on purpose](/deep-dive-network-traffic.md) deep dive (`degrade-traffic`, `block-traffic`, `tcp-dump`).
* Try a loss instead of a latency (`--loss 30%`): retransmissions show up in the capture.
* What to ask a customer in this situation: a capture on the worker while the connector sends (`tcpdump -w`), the response times measured on the API side, and the timeouts and retries of the connector config.

<!-- tabs:end -->

### Debezium PostgreSQL: the connector is RUNNING, the disk of the database fills up

<!-- tabs:start -->
#### **🔥 Description**

A Debezium PostgreSQL source connector is RUNNING, without any error. But the disk of the database keeps filling up, and the DBA points at the replication slot of the connector.

💡 What you'll learn:

* How a replication slot holds the WAL until the connector confirms it.
* Why a connector that captures quiet tables in a busy database never confirms anything.
* Fix it with a heartbeat query, and check it.

#### **🤯 Details**

Versions used:

* 🎯 CP: 8.4.1

* 🔗 Debezium PostgreSQL source: 3.2.6

* 🐘 PostgreSQL: 15

Connector config:

```json
{
  "connector.class": "io.debezium.connector.postgresql.PostgresConnector",
  "database.hostname": "postgres",
  "database.dbname": "postgres",
  "topic.prefix": "asgard",
  "plugin.name": "pgoutput",
  "slot.name": "debezium",
  "publication.autocreate.mode": "filtered",
  "table.include.list": "public.customers"
}
```

Reproduction model: [debezium-postgres-source-repro-000009-replication-slot-keeps-growing.sh](https://github.com/vdesabou/kafka-docker-playground/blob/master/academy/connect-connect-debezium-postgresql-source/debezium-postgres-source-repro-000009-replication-slot-keeps-growing.sh)

#### **📍 Step 1**

Run the example (or type `000009` and use the `fzf` completion of `-f`):

```bash
playground run -f academy/connect-connect-debezium-postgresql-source/debezium-postgres-source-repro-000009-replication-slot-keeps-growing.sh
```

The connector snapshots table `customers`, then another application writes a lot in table `audit_log`. The connector is RUNNING:

```log
debezium-postgres-source       ✅ RUNNING  0:🟢 RUNNING                 -
```

But:

```log
 slot_name | active | retained_wal
-----------+--------+--------------
 debezium  | t      | 153 MB
(1 row)
```

❔Questions:

* Is the connector working?
* Why does the slot keep 153 MB of WAL, and when will it release it?

#### **📍 Step 2**
<!-- select:start -->
<!-- select-menu-labels: 🙋 See solution for previous step? -->
#### --No--
#### --Yes--

[playground db cdc-check](/playground%20db%20cdc-check) checks the CDC prerequisites of the database, and shows the slots:

```bash
playground db cdc-check
   ℹ️  PostgreSQL version           15.8
   ✅ wal_level                    logical
   ✅ max_wal_senders              4
   ✅ replication slots            1 used of 4
   ℹ️  slot debezium (pgoutput)     active, 152 MB behind, wal_status reserved
   ℹ️  publication dbz_publication  1 table(s)
```

The slot is active (the connector is connected) but 152 MB behind. Compare the position the slot confirmed with the offset of the connector:

```bash
playground db sql << 'EOF'
SELECT slot_name, active, pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), confirmed_flush_lsn)) AS retained_wal, confirmed_flush_lsn, pg_current_wal_lsn() FROM pg_replication_slots;
EOF
```

```log
 slot_name | active | retained_wal | confirmed_flush_lsn | pg_current_wal_lsn
-----------+--------+--------------+---------------------+--------------------
 debezium  | t      | 153 MB       | 0/15FEB00           | 0/AED0278
```

```bash
playground connector offsets get --connector debezium-postgres-source
```

```log
      "offset": {
        "last_snapshot_record": true,
        "lsn": 23063296,
        ...
        "snapshot_completed": true
      }
```

`23063296` is `0x15FEB00`: the connector is still at the position of its snapshot, and a minute later nothing has moved. `connector diagnose` finds no error either.

Why? The publication of the connector only has table `customers` (`publication.autocreate.mode` `filtered`), and nobody changes it. PostgreSQL 15 does not even send the empty transactions of the other tables: the connector receives nothing, so it never confirms a newer position, and PostgreSQL keeps all the WAL written since then, for the slot.

<!-- select:end -->

👉 How can the connector confirm a newer position when its tables do not change?

> [!TIP]
> Look at the `heartbeat.*` settings of the [Debezium PostgreSQL connector](https://debezium.io/documentation/reference/stable/connectors/postgresql.html#postgresql-property-heartbeat-interval-ms).

#### **📍 Step 3**
<!-- select:start -->
<!-- select-menu-labels: 🙋 See solution for previous step? -->
#### --No--
#### --Yes--

`heartbeat.interval.ms` alone is not enough here: the heartbeats carry the offset the connector already has. After adding `"heartbeat.interval.ms": "10000"` and waiting 90 seconds:

```log
 slot_name | active | retained_wal
-----------+--------+--------------
 debezium  | t      | 153 MB
```

The connector has to receive a change: a `heartbeat.action.query` writes in a small table of its own, captured by the connector:

```bash
playground db sql << 'EOF'
CREATE TABLE debezium_heartbeat (id INT PRIMARY KEY, ts TIMESTAMP);
EOF
```

```json
"table.include.list": "public.customers,public.debezium_heartbeat",
"heartbeat.interval.ms": "10000",
"heartbeat.action.query": "INSERT INTO debezium_heartbeat (id, ts) VALUES (1, now()) ON CONFLICT (id) DO UPDATE SET ts = now()"
```

Debezium adds the table to its publication (`filtered` mode), and 90 seconds later:

```log
 slot_name | active | retained_wal
-----------+--------+--------------
 debezium  | t      | 1128 bytes
(1 row)
```

<!-- select:end -->
🥁 So...was the connector working?

#### **🎓 Next Steps**

* Read the [🍪 Oracle CDC](/deep-dive-oracle-cdc.md) deep dive for the same kind of question with LogMiner and XStream.
* What a stopped connector does to the slot: `playground connector stop --connector debezium-postgres-source`, write in `customers`, and watch `retained_wal` grow; a slot that is never used again must be dropped (`pg_drop_replication_slot`), or it fills the disk.
* `max_slot_wal_keep_size` (PostgreSQL 13+) caps the WAL a slot keeps: the database is protected, and the slot is invalidated (the connector must snapshot again).

<!-- tabs:end -->

### JDBC sink: an incompatible schema breaks the connector

<!-- tabs:start -->
#### **🔥 Description**

A JDBC sink connector that had been running for months fails with `column "quantity" is of type integer but expression is of type character varying`. Nobody changed the connector.

💡 What you'll learn:

* Find who changed what in Schema Registry, and when.
* Understand what a compatibility rule protects, and what happens after a bad version got in.
* Fix the subject, the producer and the sink, in that order.

#### **🤯 Details**

Versions used:

* 🎯 CP: 8.4.1

* 🔗 JDBC sink (PostgreSQL): 10.9.10

Connector config:

```json
{
  "connector.class": "io.confluent.connect.jdbc.JdbcSinkConnector",
  "connection.url": "jdbc:postgresql://postgres/postgres?user=myuser&password=mypassword&ssl=false",
  "topics": "orders",
  "auto.create": "true",
  "auto.evolve": "true"
}
```

Reproduction model: [postgres-sink-repro-000010-incompatible-schema-breaks-sink.sh](https://github.com/vdesabou/kafka-docker-playground/blob/master/academy/connect-connect-jdbc-postgresql-sink/postgres-sink-repro-000010-incompatible-schema-breaks-sink.sh)

> [!NOTE]
> Do not read the model before the exercise: it contains the answer.

#### **📍 Step 1**

Run the example (or type `000010` and use the `fzf` completion of `-f`):

```bash
playground run -f academy/connect-connect-jdbc-postgresql-sink/postgres-sink-repro-000010-incompatible-schema-breaks-sink.sh
```

5 orders are written, then 5 more arrive, and the task fails after its retries:

```log
postgres-sink                  ✅ RUNNING  0:🛑 FAILED                   tasks: org.apache.kafka.connect.errors.ConnectException: Exiting WorkerSinkTask due to unrecoverable exception.
java.sql.BatchUpdateException: Batch entry 0 INSERT INTO "postgres"."public"."orders" ("id","product","quantity","price") VALUES (('1'::int4),('Clay'),('Zackary'),('0.57448107'::real)) was aborted: ERROR: column "quantity" is of type integer but expression is of type character varying
```

❔Questions:

* What changed, and when?
* How did it get through Schema Registry?

#### **📍 Step 2**
<!-- select:start -->
<!-- select-menu-labels: 🙋 See solution for previous step? -->
#### --No--
#### --Yes--

> What changed, and when?

[playground schema history](/playground%20schema%20history) reads the history of Schema Registry (its `_schemas` topic):

```bash
playground schema history --subject orders-value
📅 2026-11-25
   16:07:58  ⏺️ orders-value: registered v1 (id 1, AVRO)
   16:08:00  🛡️ orders-value: compatibility NONE
   16:08:04  ⏺️ orders-value: registered v2 (id 2, AVRO)
```

Someone set the compatibility of the subject to `NONE`, and a new version was registered right after. What changed in it, with [playground schema diff](/playground%20schema%20diff):

```bash
playground schema diff --subject orders-value --from 1 --to 2
🔀 orders-value v1 (id 1)  →  orders-value v2 (id 2)  (AVRO)
   ✏️  quantity type: int → string
      💡 incompatible type change for both directions unless the rule is NONE

🛡️  Verdict of the Schema Registry for orders-value v2 (id 2) after orders-value v1 (id 1):
   ❌ BACKWARD
      TYPE_MISMATCH: The type (path '/fields/2/type') of a field in the new schema does not match with the old schema
   ❌ FORWARD
   ❌ FULL
   ✅ NONE
```

> How did it get through Schema Registry?

With the default rule (`BACKWARD`), Schema Registry would have refused it:

```bash
playground schema get-compatibility --subject orders-value
NONE
```

```bash
playground schema check-compatibility --subject orders-value --version 1 --compatibility BACKWARD << 'EOF'
{"type":"record","name":"myrecord","fields":[{"name":"id","type":"int"},{"name":"product","type":"string"},{"name":"quantity","type":"string"},{"name":"price","type":"float"}]}
EOF
❌ the schema is not compatible with version 1 of orders-value under BACKWARD (--compatibility rule): register would refuse it (40901)
   TYPE_MISMATCH: The type (path '/fields/2/type') of a field in the new schema does not match with the old schema
```

The table was created from version 1 (`quantity integer`): the records of version 2 cannot be written in it.

<!-- select:end -->

👉 Put the compatibility back, and check that the corrected producer (`quantity` back to an `int`, plus a new optional field `quantity_label`) would be accepted.

#### **📍 Step 3**
<!-- select:start -->
<!-- select-menu-labels: 🙋 See solution for previous step? -->
#### --No--
#### --Yes--

```bash
playground schema set-compatibility --subject orders-value --compatibility BACKWARD
```

Surprise: the corrected schema is refused.

```bash
playground schema check-compatibility --subject orders-value << 'EOF'
{"type":"record","name":"myrecord","fields":[{"name":"id","type":"int"},{"name":"product","type":"string"},{"name":"quantity","type":"int"},{"name":"price","type":"float"},{"name":"quantity_label","type":["null","string"],"default":null}]}
EOF
❌ the schema is not compatible with the versions the rule checks of orders-value under BACKWARD (subject rule): register would refuse it (40901)
   TYPE_MISMATCH: The type (path '/fields/2/type') of a field in the new schema does not match with the old schema
```

`BACKWARD` only compares a new schema with the **latest** version, and the latest is now the bad v2 (`quantity` string). The bad v2 itself even passes the check. Putting the rule back does not undo what got in while it was `NONE`: remove the bad version first (a soft delete, the records written with it can still be read by id):

```bash
playground schema delete --subject orders-value --version 2
```

```bash
playground schema check-compatibility --subject orders-value << 'EOF'
{"type":"record","name":"myrecord","fields":[{"name":"id","type":"int"},{"name":"product","type":"string"},{"name":"quantity","type":"int"},{"name":"price","type":"float"},{"name":"quantity_label","type":["null","string"],"default":null}]}
EOF
✅ the schema is compatible with the versions the rule checks of orders-value under BACKWARD (subject rule): register would accept it
```

Last, the sink: the 5 records of version 2 are still in the topic, and the table cannot take them. Skip them (they are bad data; the producer sends them again with the corrected schema) with [playground connector offsets alter](/playground%20connector%20offsets%20alter): set the offset of `orders` partition `0` from `5` to `10`, then restart the connector. It is RUNNING again.

<!-- select:end -->
🥁 So...who broke the connector?

#### **🎓 Next Steps**

* Read the [🍪 Schema Registry](/deep-dive-schema.md) deep dive.
* `BACKWARD_TRANSITIVE` compares a new schema with **every** version, not only the latest one: try `playground schema check-compatibility --compatibility BACKWARD_TRANSITIVE` with the schemas of this exercise.
* Lock the rule: `playground schema set-mode` and RBAC on the subject keep a producer team from relaxing the compatibility to get a change through.

<!-- tabs:end -->

### Which version of the HTTP sink brought its HTTP logs?

<!-- tabs:start -->
#### **🔥 Description**

A customer runs an older HTTP sink connector. To see the requests it sends, they set the `org.apache.http` logger to `TRACE`... and no HTTP log shows up. On a recent version, a colleague sees every request and header. Which version changed this, and what can the customer do without upgrading?

💡 What you'll learn:

* Turn a question about versions into a reproduction model with a verdict (`playground repro assert`).
* Find the version where a behaviour changed with `playground repro bisect`, and read the changelog in between.

#### **🤯 Details**

Versions used:

* 🎯 CP: 8.4.1

* 🔗 HTTP sink: 1.7.10 to 1.7.15 (the versions supported with CP 8)

Reproduction model: [http-sink-repro-000011-which-version-brought-http-logs.sh](https://github.com/vdesabou/kafka-docker-playground/blob/master/academy/connect-connect-http-sink/http-sink-repro-000011-which-version-brought-http-logs.sh): the HTTP sink sends 3 records with `TRACE` on `org.apache.http`, and the model ends with its verdict:

```bash
# the problem is reproduced when the logs of connect have no line of the HttpClient wire log
playground repro assert --reproduced-if-command "! docker logs connect 2>&1 | grep -q 'http-outgoing-'"
```

#### **📍 Step 1**

Run the model with the version of the customer, then with the latest one, and compare the verdicts:

```bash
playground run -f academy/connect-connect-http-sink/http-sink-repro-000011-which-version-brought-http-logs.sh --connector-tag 1.7.10
playground run -f academy/connect-connect-http-sink/http-sink-repro-000011-which-version-brought-http-logs.sh --connector-tag 1.7.15
```

❔Questions:

* Between 1.7.10 and 1.7.15, which version changed the behaviour?
* Is there a way to get the HTTP logs on the old versions?

> [!TIP]
> [playground repro bisect](/playground%20repro%20bisect) runs a model on several versions and reads the verdict of `repro assert` after each run.

#### **📍 Step 2**
<!-- select:start -->
<!-- select-menu-labels: 🙋 See solution for previous step? -->
#### --No--
#### --Yes--

A binary search over the Confluent Hub versions between 1.7.10 and 1.7.15 (5 runs, about 8 minutes):

```bash
playground repro bisect -f academy/connect-connect-http-sink/http-sink-repro-000011-which-version-brought-http-logs.sh --from 1.7.10 --to 1.7.15
```

```log
📊 verdicts of http-sink-repro-000011-which-version-brought-http-logs.sh:
   1.7.10         🐞 reproduced      1m30s    the command succeeded: ! docker logs connect 2>&1 | grep -q 'http-outgoing-'
   1.7.12         🐞 reproduced      1m27s    the command succeeded: ! docker logs connect 2>&1 | grep -q 'http-outgoing-'
   1.7.13         🐞 reproduced      1m29s    the command succeeded: ! docker logs connect 2>&1 | grep -q 'http-outgoing-'
   1.7.14         ✅ not reproduced   1m31s    the command failed: ! docker logs connect 2>&1 | grep -q 'http-outgoing-'
   1.7.15         ✅ not reproduced   1m31s    the command failed: ! docker logs connect 2>&1 | grep -q 'http-outgoing-'
🔀 the verdict changes between 1.7.13 (reproduced) → 1.7.14 (not reproduced)
📰 what changed between 1.7.13 and 1.7.14:
   📜 Release notes of confluentinc/kafka-connect-http after 1.7.13 up to 1.7.14: 1 version(s)
   🔢 v1.7.14 - 📅 release date: 2026-10-01
      • CC-45231: Route HttpClient logging through slf4j instead of unconfigured reload4j
```

Before 1.7.14, the Apache HttpClient of the connector logged through commons-logging to a reload4j that nothing configures: the `TRACE` level set on `org.apache.http` had no effect. Since 1.7.14, those logs go through slf4j like the rest of the worker:

```log
DEBUG [http-sink|task-0] http-outgoing-0 >> POST / HTTP/1.1 (org.apache.http.headers:133)
DEBUG [http-sink|task-0] http-outgoing-0 >> Content-Type: application/json (org.apache.http.headers:136)
```

> Is there a way to get the HTTP logs on the old versions?

Yes: add the `jcl-over-slf4j` bridge to the lib folder of the plugin, which is what 1.7.14 ships. The [HTTP sink example](https://github.com/vdesabou/kafka-docker-playground/blob/master/connect/connect-http-sink/http_no_auth.sh) does it for the versions before 1.7.14:

```bash
wget -q https://repo1.maven.org/maven2/org/slf4j/jcl-over-slf4j/2.0.7/jcl-over-slf4j-2.0.7.jar
cp jcl-over-slf4j-2.0.7.jar confluent-hub/confluentinc-kafka-connect-http/lib/
```

<!-- select:end -->
🥁 So...upgrade, or add a jar?

#### **🎓 Next Steps**

* Read the [🍪 Reproduction models](/deep-dive-reproduction-models.md) deep dive: `repro assert`, `repro bisect`, `repro status`.
* `--all` runs every version of the range instead of a binary search: useful when the behaviour may change more than once.
* `--tag A --tag B` does the same with Confluent Platform versions.

<!-- tabs:end -->
