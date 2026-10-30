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

[playground connector smt test](https://kafka-docker-playground.io/#/playground%20connector%20smt%20test) runs a chain of Single Message Transforms (SMTs) on one record and shows what each transform does to it, in a few seconds: what changes (topic, key, headers, value field by field, schema), each predicate and its result, a dropped record, the transform that fails with its error, and where each transform class comes from. No topic or connector is created, and the connector is not updated. The chain runs inside the `connect` container, with the classes and versions of the worker.

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

| You want | Add |
| --- | --- |
| a source record instead of a sink one | `--type source` |
| the same chain on other CP versions | `--cp-version 7.9.0 --cp-version 8.3.2` |
| an SMT that is not in the worker | `--smt-plugin confluentinc/connect-transforms:1.4.4` / `--smt-jar my-smt.jar` |
| the steps as data, for an assertion | `--json` |
| the stack trace of the failing step | `--verbose` |

An HTML report of the steps is written to `/tmp/playground-smt-test/`.

![playground connector smt test report](./images/report-smt-test.jpg)

> [!TIP]
> The [connect-testing-smt-filestream-sink](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-testing-smt-filestream-sink) example shows every way to use the command, with a ready-to-use record and chain: `playground run -f testing-smt.sh`

> [!TIP]
> The [🍪 deep dive on SMT testing](/deep-dive-connector-smt-test.md) has the rest: the [record format](/deep-dive-connector-smt-test?id=_2-the-chain-and-the-record) (schemaless or with a schema, headers, `--from-topic`), [how to read the output](/deep-dive-connector-smt-test?id=_3-reading-the-output) and the `--json` fields, [other CP versions and SMTs that are not in the worker](/deep-dive-connector-smt-test?id=_4-versions-and-plugins-cp-version-smt-plugin-smt-jar), a hands-on lab and recipes for support repros.

> [!NOTE]
> Self-managed connectors only: the transforms of a fully managed connector run in Confluent Cloud (give its config with `--config` for an indicative result on a self-managed worker). The cfk environment is not supported yet. The chain runs outside of a connector task, so `errors.tolerance` and the dead letter queue do not apply: a failing transform is reported as failing.
