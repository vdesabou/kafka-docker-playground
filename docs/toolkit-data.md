# 👉 Producing, consuming and SMTs

Put data in a topic, read it back, and check what a transform chain does to a record. Part of the [🧰 Reproduction toolkit](/reusables.md).

> [!TIP]
> For the details, see the deep dives on [producing](/deep-dive-topic-produce.md), [consuming](/deep-dive-topic-consume.md) and [testing SMTs](/deep-dive-connector-smt-test.md).

## 👉 Producing data

Use [playground topic produce](/playground%20topic%20produce): it creates the topic if needed, registers the schema (avro, json schema or protobuf) and generates realistic random data matching it. See the [command page](/playground%20topic%20produce) for all options.

> [!TIP]
> Pipe the schema or the payload with a quoted heredoc, `<< 'EOF'`, so that the `%g` placeholders survive the shell.

<!-- tabs:start -->

#### **String**

```bash
playground topic produce -t a-topic --nb-messages 10 --forced-value "This is a message %g"
```

#### **JSON**

```bash
playground topic produce -t a-topic --nb-messages 3 << 'EOF'
{"u_name": "scissors", "u_price": 2.75, "u_quantity": 3}
{"u_name": "tape", "u_price": 0.99, "u_quantity": 10}
{"u_name": "notebooks", "u_price": 1.99, "u_quantity": 5}
EOF
```

#### **Key and headers**

```bash
# key1, key2, etc.. (%g can also be used)
playground topic produce -t a-topic --nb-messages 3 --key "key1" --headers "header1:value1,header2:value2" << 'EOF'
{"u_name": "scissors", "u_price": 2.75, "u_quantity": 3}
{"u_name": "tape", "u_price": 0.99, "u_quantity": 10}
{"u_name": "notebooks", "u_price": 1.99, "u_quantity": 5}
EOF
```

#### **Avro**

```bash
playground topic produce -t a-topic --nb-messages 10 << 'EOF'
{
  "type": "record",
  "name": "myrecord",
  "fields": [
    {"name": "u_name", "type": "string"},
    {"name": "u_price", "type": "float"},
    {"name": "u_quantity", "type": "int"}
  ]
}
EOF
```

#### **Avro with key**

```bash
playground topic produce -t a-topic --nb-messages 10 --key '
{
  "type": "record",
  "name": "myrecordkey",
  "fields": [
    {"name": "ID", "type": "long"}
  ]
}
' << 'EOF'
{
  "type": "record",
  "name": "myrecordvalue",
  "fields": [
    {"name": "ID", "type": "long"},
    {"name": "product", "type": "string"},
    {"name": "quantity", "type": "int"},
    {"name": "price", "type": "float"}
  ]
}
EOF
```

#### **Protobuf**

```bash
playground topic produce -t a-topic --nb-messages 10 << 'EOF'
syntax = "proto3";

message MyRecord {
    string f1 = 1;
}
EOF
```

#### **JSON Schema**

```bash
playground topic produce -t a-topic --nb-messages 10 << 'EOF'
{
  "type": "object",
  "properties": {
    "f1": {"type": "string"}
  }
}
EOF
```

#### **Exact payload**

Use `--generate-only` first to get the skeleton of a message, then `--forced-value` to send exactly the record you need:

```bash
playground topic produce -t a-topic --nb-messages 1 --forced-value '{"f1": "value1"}' << 'EOF'
{
  "type": "record",
  "name": "myrecord",
  "fields": [
    {"name": "f1", "type": "string"}
  ]
}
EOF
```

#### **Schema file**

```bash
playground topic produce -t a-topic --nb-messages 10 < schema.avsc
```

#### **Tombstone**

```bash
playground topic produce -t a-topic --tombstone --key "mykey1"
```

#### **High volume**

```bash
playground topic produce -t a-topic --nb-messages 200000 --record-size 1000
```

#### **Steady flow**

A record every 100 ms until ctrl-c, for example to watch a connector catch up. The progress is logged every 10 seconds, and
after ctrl-c the number of records sent is exact:

```bash
playground topic produce -t a-topic --nb-messages -1 --throughput 10 --value '{"id": %g}'
```

#### **Force the format**

The format of `--value` (and `--key`) is detected from its content: a raw payload that contains `"_meta"`, `proto3`,
`"type": "object"`... would not be sent as is. Set it with `--value-format` (`avro`, `json-schema`, `protobuf`, `json`,
`sql`, `datagen`, `raw`):

```bash
playground topic produce -t a-topic --value-format raw --value '{"_meta": "not a datagen schema", "id": %g}'
```

<!-- tabs:end -->

> [!NOTE]
> The [Java producers](/legacy-java-producer) are deprecated: use them only if you have very specific requirements, such as setting the record timestamp.

## 👉 Consuming data

Use [playground topic consume](/playground%20topic%20consume): it reads the topic from the beginning and detects the format (avro, protobuf, json schema or plain) on its own. Every record is displayed with its timestamp, partition, offset, headers, key and schema ID (add `--print-schema` to also print the registered schemas). The consumer stops when no record arrives for 10 seconds (30 on Confluent Cloud).

<!-- tabs:start -->

#### **Simplest**

```bash
playground topic consume --topic a-topic
```

#### **All topics**

```bash
playground topic consume
```

#### **Assert content**

Wait up to `--timeout` seconds for at least 10 records, consume them, and fail if fewer could be consumed (records that cannot be deserialized are reported and do not count) or if none contains `value1`. This is how examples verify that data flowed:

```bash
playground topic consume --topic a-topic --min-expected-messages 10 --grep "value1" --timeout 60
```

#### **Last records**

The most recent records, sorted by timestamp across partitions (by default, the first `--max-messages` 100 are displayed):

```bash
playground topic consume --topic a-topic --last 10
```

#### **From a time**

The records from a date (local time, add `Z` for UTC), an epoch, or a duration ago (`30s`, `10m`, `2h`, `1d`):

```bash
playground topic consume --topic a-topic --from-timestamp 10m
playground topic consume --topic a-topic --from-timestamp "2026-10-22 10:30"
```

#### **One offset**

The record a connector is stuck on (`--offset` is a number, `earliest` or `latest`, and needs `--partition`):

```bash
playground topic consume --topic a-topic --partition 0 --offset 1234 --max-messages 1
```

#### **JSON**

One json object per record (key and value embedded as json when they are valid json), only the records on stdout:

```bash
playground topic consume --topic a-topic --json | jq -r '.value.u_name'
```

#### **Count**

The number of records (not offsets: transaction markers, compacted records and records that cannot be deserialized do not count), alone on stdout:

```bash
playground topic consume --topic a-topic --count
playground topic consume --topic a-topic --count --grep "scissors"
```

#### **Tail**

```bash
playground topic consume --topic a-topic --tail
```

#### **Open in editor**

```bash
playground topic consume --topic a-topic --open
```

<!-- tabs:end -->

## 🧪 Testing SMTs

[playground connector smt test](https://kafka-docker-playground.io/#/playground%20connector%20smt%20test) runs a chain of Single Message Transforms (SMTs) on one record and shows what each transform does to it, in a few seconds. No topic or connector is created, and the connector is not updated. You see, step by step:

* what changes: topic, partition, timestamp, key, headers (with their types), the value field by field, and the schema
* each predicate and its result, including `negate`: a skipped transform is shown as skipped
* a dropped record (a transform returned `null`, for example `Filter`)
* the transform that fails, with its config and its error (`--verbose` adds the stack trace)
* where each transform class comes from (`from`): the plugin and its version, or the Kafka version of the worker. A warning appears when another copy of the class is on the plugin path

The chain runs in a small harness inside the `connect` container, with the classpath and the `plugin.path` of the worker. The transforms, predicates and converters are the same classes and versions as in the worker.

```bash
# the transforms of a running connector, on a default record
playground connector smt test --connector filestream-sink

# the same transforms, on a real record of the topic (converted with the converters of the connector: avro, protobuf, json schema...)
playground connector smt test --connector filestream-sink --from-topic filestream --offset 0

# your own chain on stdin (a whole connector config works too: only transforms.*, predicates.* and the converters are used)
playground connector smt test --record '{"topic":"orders","key":"o-1","value":{"id":1}}' << 'EOF'
{
  "transforms": "route",
  "transforms.route.type": "org.apache.kafka.connect.transforms.RegexRouter",
  "transforms.route.regex": "(.*)",
  "transforms.route.replacement": "crm-$1"
}
EOF

# the transforms and the record in files
playground connector smt test --config @transforms.json --record @record.json
```

> [!TIP]
> The [connect-testing-smt-filestream-sink](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-testing-smt-filestream-sink) example shows every way to use the command, with a ready-to-use record and chain: `playground run -f testing-smt.sh`

### The record

`--record` is a JSON object (or `@file`), all fields optional. Without it, the record is `{"topic": <first topic of the connector or test-topic>, "key": "k1", "value": {"id": 1, "name": "foo"}}`.

| Field | Content |
| --- | --- |
| `topic`, `partition`, `offset`, `timestamp` | where the record comes from |
| `key`, `value` | schemaless JSON, `null` for a tombstone, or the `{"schema": ..., "payload": ...}` envelope of the `JsonConverter` for a value with a schema (a `Struct`) |
| `headers` | an object (`{"source": "crm", "retries": 3}`), or an array to repeat a key (`[{"key": "trace", "value": "a"}, {"key": "trace", "value": "b"}]`). Types follow the JSON value: `STRING`, `BOOLEAN`, `INT64`, `FLOAT64`, schemaless for an object |

A value with a schema:

```json
{
  "topic": "customers",
  "key": "c-42",
  "value": {
    "schema": {
      "type": "struct",
      "name": "Customer",
      "fields": [
        { "field": "customer_id", "type": "string" },
        { "field": "email", "type": "string" }
      ]
    },
    "payload": { "customer_id": "42", "email": "john@example.com" }
  },
  "headers": { "source": "crm" }
}
```

To test a real record instead, use `--from-topic <topic> --offset <n> [--partition <p>]`. The record is read from Kafka and converted with the key, value and header converters of the connector (or of the worker), with Schema Registry when they use it.

The record is a `SinkRecord` by default. Use `--type source` for the transforms of a source connector: some transforms only accept one kind of record. For example, `InsertField` with `offset.field` fails on a source record with `Only SinkRecord supported for [field insertion]`, as in a real source connector.

### The result

The terminal shows one block per step (✅ applied, ⏭️ skipped by its predicate, ➖ no change, 🗑️ dropped, ❌ failed), then the final record. An HTML report is also written to `/tmp/playground-smt-test/`, and opened in the browser when the command runs in an interactive terminal (`--no-open` to only write it). The report contains:

* the chain at the top, one badge per step
* one card per step: class, origin, config, predicate, then the topic, key, header and value changes (added, changed, removed), and the schema diff
* the error and its stack trace for a failing step
* a final record card: what the sink connector receives, or what the source connector sends to Kafka

![playground connector smt test report](./images/report-smt-test.jpg)

With `--json`, the steps are printed as JSON for scripts. The command exits with `1` when a transform fails (a dropped record is not an error):

```bash
playground connector smt test --json --config @transforms.json --record @record.json \
  | jq -e '[.steps[] | select(.record)] | last | .record.value | fromjson | .email_address == "john@example.com"'
```

### Another CP version

`--cp-version` (repeat the flag) runs the same chain in throwaway `cp-server-connect` containers of those versions, to see whether an upgrade changes what the transforms do. The summary and the report compare the final record of each version. It also works without a running example, with `--config`:

```bash
playground connector smt test --connector filestream-sink --from-topic filestream --offset 0 --cp-version 7.9.0 --cp-version 8.3.2
```

![playground connector smt test report comparing CP versions](./images/report-smt-test-cp-versions.jpg)

### SMTs that are not in the worker

The SMTs shipped with Kafka and the plugins on the `plugin.path` of the worker are available. To test others, without changing the worker:

```bash
# a Confluent Hub plugin (or another version than the one installed), installed for the test only and cached in ~/.playground-smt-tester
playground connector smt test --connector my-sink --smt-plugin confluentinc/connect-transforms:1.4.4

# your own build: repeat --smt-jar for the jars it depends on, they are loaded together as one plugin
playground connector smt test --config @transforms.json --smt-jar target/my-smt-1.0.0.jar --smt-jar lib/its-dependency.jar
```

These plugins take precedence over a copy of the same transform on the plugin path of the worker.

> [!NOTE]
> Self-managed connectors only: the transforms of a fully managed connector run in Confluent Cloud (give its config with `--config` for an indicative result on a self-managed worker). The cfk environment is not supported yet. The chain runs outside of a connector task, so `errors.tolerance` and the dead letter queue do not apply: a failing transform is reported as failing.
