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

## Faster: `playground connector smt test`

Once the example is running, [`playground connector smt test`](https://kafka-docker-playground.io/#/playground%20connector%20smt%20test) applies the transforms of the connector to a record step by step, in a second, without updating the connector or producing again: what each transform changes (topic, key, value, headers, schema field by field), the predicates, and the transform that fails with its error.

```bash
# the transforms of filestream-sink on the first record of the topic, converted with its AvroConverter
playground connector smt test --connector filestream-sink --from-topic filestream --offset 0

# another transform chain on your own record
playground connector smt test --record '{"topic":"filestream","value":{"id":1,"name":"foo"}}' << 'EOF'
{"transforms":"wrap","transforms.wrap.type":"org.apache.kafka.connect.transforms.HoistField$Value","transforms.wrap.field":"payload"}
EOF
```
