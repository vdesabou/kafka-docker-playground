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
