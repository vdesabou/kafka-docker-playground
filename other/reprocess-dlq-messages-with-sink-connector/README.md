# How to process DLQ records with a sink connector

## Objective

A sink connector with `errors.tolerance=all` sends the records it cannot process to a dead letter queue
(DLQ). Once the cause is fixed, the records must be processed again. This example shows two ways to do it:

| Script | How the DLQ records are processed |
| --- | --- |
| `process-dlq-messages-with-sink-connector.sh` | A second sink connector reads the DLQ topic, with a [subject alias](https://docs.confluent.io/platform/current/schema-registry/fundamentals/serdes-develop/index.html#subject-aliases) `dlq-value` → `avro-topic-value` so that the Avro records of the DLQ can be deserialized. Needs no extra tool, so it also works in production. |
| `replay-dlq-messages-with-playground.sh` | `playground topic dlq replay` produces the DLQ records again to their original topic (`__connect.errors.topic` header), where the original connector processes them. No second connector, no alias. |

Both scripts start with the same failure:

1. 10 Avro records are produced to `avro-topic`.
2. The `schema-registry` container is killed, then the `filestream-sink` connector is created with a DLQ
   (`errors.deadletterqueue.topic.name=dlq`, `errors.deadletterqueue.context.headers.enable=true`): the
   AvroConverter cannot fetch the schema, so the 10 records go to `dlq`.
3. `playground topic dlq inspect --topic dlq` shows why:

```
🔢 10 record(s) of connector filestream-sink, stage VALUE_CONVERTER (io.confluent.connect.avro.AvroConverter)
  ❌ org.apache.kafka.common.errors.NetworkException: Network connection error while deserializing data for topic avro-topic: schema-registry
  🌱 root cause: java.net.UnknownHostException: schema-registry
  📍 original records: topic avro-topic partition 0 offsets 0..9 (10)
  📬 dlq partition 0 offsets 0..9
```

4. `schema-registry` is restarted: the cause is fixed.

## How to run

```bash
playground run -f process-dlq-messages-with-sink-connector.sh
```

or

```bash
playground run -f replay-dlq-messages-with-playground.sh
```

## Details of what the scripts do

### With a second sink connector

The subject alias lets the AvroConverter of the second connector find the schema of the DLQ records:

```bash
playground schema set-alias --subject avro-topic-value --alias dlq-value
```

The `dlq-filestream-sink` connector reads `dlq` and writes the 10 records to `/tmp/output.json`.

### With playground topic dlq replay

```bash
playground topic dlq replay --topic dlq --dry-run
playground topic dlq replay --topic dlq
```

The records are produced to `avro-topic` byte for byte (key, value, timestamp, other headers), without the
`__connect.errors.*` headers. `filestream-sink` processes them and writes them to `/tmp/output.json`. The
script then checks that none of them went back to the DLQ.

Use `--to <topic>` to replay to another topic, and `--grep <regex>` to replay only one kind of error.
