# Schema ID in Kafka header with FileStream Source connector

## Objective

Quickly test writing the Schema Registry schema ID in a Kafka record header instead of the payload prefix, using the [FileStream Source](https://docs.confluent.io/platform/current/connect/filestream_connector.html) connector and the Avro converter with `value.converter.value.schema.id.serializer=io.confluent.kafka.serializers.schema.id.HeaderSchemaIdSerializer`.

## Prerequisites

* CP 8.1.0 or later (support for `value.converter.value.schema.id.serializer`). The script exits with code `111` on older versions.

## How to run

```bash
playground run -f filestream-source-schema-id-kafka-header.sh
```

## What the script does

1. Generates a JSON file with 10 lines (from Mockaroo) in `/tmp/kafka-connect/examples/file.json` in the `connect` container.
2. Creates a FileStream Source connector writing to topic `filestream`, with `AvroConverter` for values and `HeaderSchemaIdSerializer`.
3. Verifies the data with `playground topic consume --topic filestream`: records carry a `__value_schema_id` header and the value is not prefixed with the schema ID.
