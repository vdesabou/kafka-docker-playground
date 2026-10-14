# Testing SMT easily with FileStream Sink connector

## Objective

Quickly test a chain of Single Message Transforms (SMTs) with the [FileStream Sink](https://docs.confluent.io/platform/current/connect/filestream_connector.html) connector, and see the result of each transformation in the logs.

Edit the `transforms` section of the connector config in `testing-smt.sh` to try your own chain. The common SMT plugins (Confluent `connect-transforms`, `jcustenborder` transform-common and json-schema) are on the plugin path.

## How to run

```bash
playground run -f testing-smt.sh
```

## What the script does

1. Produces one Avro `Customer` record to topic `filestream`.
2. Sets the log level of `org.apache.kafka.connect.runtime.TransformationChain` to `TRACE` with `playground debug log-level set`.
3. Creates a FileStream Sink connector writing to `/tmp/output.json` with the chain `InsertMeta,AddGroup,AddLoadTime,WrapPayload` (`InsertField` and `HoistField`).
4. Displays `/tmp/output.json` and waits for the `Applying transformation` log lines in the `connect` container.

Expected output:

```
Struct{payload=Struct{count=1,first_name=Mateo,last_name=Karolann,address=Oscar,topic_name=filestream,partition_id=0,offset_value=0,group_name=my group,kafka_datetime=Fri Mar 27 14:09:22 GMT 2026}}
```
