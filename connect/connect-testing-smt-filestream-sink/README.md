# Testing SMT easily with FileStream Sink connector and `playground connector smt test`

## Objective

Quickly test a chain of Single Message Transforms (SMTs), and see what each transform does to a record.

The example runs a [FileStream Sink](https://docs.confluent.io/platform/current/connect/filestream_connector.html) connector with a transform chain. It then shows all the ways to use [`playground connector smt test`](https://kafka-docker-playground.io/#/playground%20connector%20smt%20test). That command applies a transform chain to a record step by step, in a few seconds, without creating a connector or producing a record. It shows:

- what each transform changes: topic, key, value, headers, schema field by field
- the predicates
- the transform that fails, with its config and its error

Each run also writes an HTML report to `/tmp/playground-smt-test/`.

The common SMT plugins (Confluent `connect-transforms`, `jcustenborder` transform-common and json-schema) are on the plugin path.

## How to run

```bash
playground run -f testing-smt.sh
```

## What the script does

1. Produces one Avro `Customer` record to topic `filestream`.
2. Creates a FileStream Sink connector writing to `/tmp/output.json` with the chain `InsertMeta,AddGroup,AddLoadTime,WrapPayload` (`InsertField` and `HoistField`), and displays the file:

   ```
   Struct{payload=Struct{count=1,first_name=Mateo,last_name=Karolann,address=Oscar,topic_name=filestream,partition_id=0,offset_value=0,group_name=my group,kafka_datetime=Fri Mar 27 14:09:22 GMT 2026}}
   ```

3. Runs `playground connector smt test` in 11 ways:

| # | What | Command |
| --- | --- | --- |
| 1 | the transforms of the running connector, on a default record | `--connector filestream-sink` |
| 2 | the same, on the real record of the topic, read and converted with the connector's `AvroConverter` and Schema Registry | `--connector filestream-sink --from-topic filestream --offset 0` |
| 3 | the same, on your own record | `--connector filestream-sink --record '{"topic":"filestream","key":"k1","value":{...}}'` |
| 4 | a chain on stdin, with typed headers (the array form allows duplicate keys), `InsertHeader`, `HeaderFrom`, `DropHeaders`, `InsertField`, `RegexRouter`, a `HasHeaderKey` predicate and `negate` (a skipped step) | `--record '{..., "headers":[{"key":"trace","value":"a"},{"key":"trace","value":"b"}]}' << 'EOF'` |
| 5 | the chain and the record in files, on a value with a schema (`{"schema","payload"}` Struct): `Cast`, `ReplaceField`, `TimestampConverter`, `SetSchemaMetadata` | `--config @smt-test/transforms-struct.json --record @smt-test/record-struct.json` |
| 6 | a dropped record: `Filter` with the `RecordIsTombstone` predicate on a tombstone | `--record '{"topic":"orders","key":"o-1","value":null}'` |
| 7 | a failing transform, exit code `1`: `InsertField offset.field` on a source record | `--type source` |
| 8 | SMTs from plugins of the worker: Confluent `ExtractTopic` and jcustenborder `ChangeCase` | chain on stdin |
| 9 | another version of an SMT plugin, installed from Confluent Hub for the test only, and a jar with its dependencies (your own build): both are used instead of the worker's copy, and the output warns that the worker has another copy | `--smt-plugin confluentinc/connect-transforms:1.4.4`, `--smt-jar my-smt.jar --smt-jar its-dependency.jar` |
| 10 | `--json` for scripts: the final record is checked with `jq` | `--json` |
| 11 | the connector's transforms on CP 7.9.0 and on the current version, in throwaway `cp-server-connect` containers, with a comparison | `--connector filestream-sink --from-topic filestream --offset 0 --cp-version 7.9.0 --cp-version 8.3.2` |

Every run except the last uses `--no-open`, so only the comparison report opens in the browser. The paths of the other reports are printed (`📊 report: ...`).

## Try your own chain

With the example running:

```bash
# the record with typed headers, the transforms on stdin (or a whole connector config: only transforms.*, predicates.* and the converters are used)
playground connector smt test --record '{"topic":"orders","key":"o-1","value":{"id":1},"headers":{"source":"crm","retries":3}}' << 'EOF'
{
  "transforms": "route",
  "transforms.route.type": "org.apache.kafka.connect.transforms.RegexRouter",
  "transforms.route.regex": "(.*)",
  "transforms.route.replacement": "crm-$1"
}
EOF

# change the connector, then replay its real record
playground connector smt test --connector filestream-sink --from-topic filestream --offset 0
```

Without a running example, `--cp-version <version>` runs the chain in a throwaway `cp-server-connect` container.

`--verbose` prints the stack trace of a failing transform.

## Files

- `testing-smt.sh`: the example.
- `smt-test/record-struct.json`: a record with a Struct value (`{"schema","payload"}` envelope of the JsonConverter) and a header.
- `smt-test/transforms-struct.json`: a chain of Apache Kafka SMTs on that record.
- `docker-compose.plaintext.yml`: the plugin path with the FileStream connectors and the common SMT plugins.
