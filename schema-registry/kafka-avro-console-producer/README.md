# kafka-avro-console-producer recipes

## Objective

Two `kafka-avro-console-producer` syntaxes that are often asked about:

| Script | What it shows |
| --- | --- |
| `optional-field.sh` | an optional field (Avro union `["null","string"]`): the value is written `{"string": "..."}` (Avro JSON encoding), `null` as is |
| `key-value-serializers.sh` | a String key with an Avro value: `--property key.serializer=org.apache.kafka.common.serialization.StringSerializer` (by default, the key is Avro too) |

To put several event types in the same topic with a union of schema references, see [schema-registry/multiple-event-types-in-topic](https://github.com/vdesabou/kafka-docker-playground/tree/master/schema-registry/multiple-event-types-in-topic).

## How to run

```bash
playground run -f optional-field<tab>
playground run -f key-value-serializers<tab>
```

## What the scripts do

### `optional-field.sh`

1. registers this schema for subject `orders-value` (`playground schema register`), id 1:

   ```json
   {
     "type": "record",
     "name": "myrecord",
     "fields": [
       {"name": "id", "type": "int"},
       {"name": "product", "type": "string"},
       {"name": "quantity", "type": "int"},
       {"name": "description", "type": ["null", "string"], "default": null}
     ]
   }
   ```

2. produces 2 records with the registered schema id:

   ```bash
   kafka-avro-console-producer --bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 \
     --topic orders --property value.schema.id=1
   {"id": 111, "product": "foo1", "quantity": 101, "description": {"string": "my-first-command"}}
   {"id": 222, "product": "foo2", "quantity": 102, "description": null}
   ```


3. checks that the 2 records are in topic `orders`: `playground topic consume --topic orders --min-expected-messages 2`

### `key-value-serializers.sh`

1. produces 2 records with a String key and an Avro value:

   ```bash
   kafka-avro-console-producer --bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 \
     --topic my-topic \
     --property value.schema='{"type":"record","name":"myrecord","fields":[{"name":"f1","type":"string"}]}' \
     --property parse.key=true --property key.separator=: \
     --property key.serializer=org.apache.kafka.common.serialization.StringSerializer
   test-key1:{"f1": "value1"}
   test-key2:{"f1": "value2"}
   ```

2. consumes them with `kafka-avro-console-consumer --property print.key=true --property key.deserializer=org.apache.kafka.common.serialization.StringDeserializer`
3. checks that the 2 records are in topic `my-topic`: `playground topic consume --topic my-topic --min-expected-messages 2`

With Confluent Cloud or a secured cluster, add `--producer.config <file>` (and the `basic.auth.*` / `schema.registry.ssl.*` properties for Schema Registry).
