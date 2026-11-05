# JavaScript client (producer/consumer)

## Objective

Quickly test the [Confluent JavaScript Client for Apache Kafka](https://docs.confluent.io/kafka-clients/javascript/current/overview.html) (npm [`@confluentinc/kafka-javascript`](https://www.npmjs.com/package/@confluentinc/kafka-javascript), built on librdkafka) and the Avro serializer of the Confluent JavaScript client for Schema Registry ([`@confluentinc/schemaregistry`](https://www.npmjs.com/package/@confluentinc/schemaregistry)) against a local Confluent Platform cluster.

This is Confluent's client, not [KafkaJS](https://kafka.js.org/) (see [other/client-kafkajs](../client-kafkajs/)): [`client.js`](client.js) uses its promisified KafkaJS-compatible API (`require('@confluentinc/kafka-javascript').KafkaJS`) with librdkafka configuration properties (`bootstrap.servers`, `group.id`...).

## How to run

```bash
playground run -f start.sh
```

| Script | Description |
| --- | --- |
| `start.sh` | JavaScript producer and consumer, string and Avro records, in the `client-javascript` container, against the plaintext broker and Schema Registry |

## What the script does

1. Starts only the `client-javascript` container and what it depends on (broker, Schema Registry), with `playground start-environment --service client-javascript`. The image is built from the `Dockerfile` (Node.js 24, `npm ci` of `@confluentinc/kafka-javascript` and `@confluentinc/schemaregistry` 1.11.0 from [`package.json`](package.json) / `package-lock.json`). The client reads its configuration from [`client.properties`](client.properties), mounted in `/tmp/client.properties`: one librdkafka property per line, plus `schema.registry.url` (and `schema.registry.basic.auth.user.info`) for the Schema Registry client.
2. Creates topics `javascript-string` and `javascript-avro` with 3 partitions.
3. Produces 10 string records (key `key-<i>`, value `{"id":"id-<i>","amount":<i*10.5>}`, `acks=all`, each send awaited), then consumes them with group `javascript-string-group` (`enable.auto.commit=false`, `commitOffsets()` after each record). The consumer exits with an error if fewer than 10 records arrive within 60 seconds:

   ```bash
   playground container exec -c client-javascript --command "node client.js produce javascript-string /tmp/client.properties 10"
   playground container exec -c client-javascript --command "node client.js consume javascript-string /tmp/client.properties 10"
   ```

4. Same with Avro records of schema `io.confluent.playground.Payment` (fields `id` and `amount`): the producer registers it under subject `javascript-avro-value` and serializes with `AvroSerializer` (`useLatestVersion`), the consumer reads it back with `AvroDeserializer`:

   ```bash
   playground container exec -c client-javascript --command "node client.js produce-avro javascript-avro /tmp/client.properties 10"
   playground container exec -c client-javascript --command "node client.js consume-avro javascript-avro /tmp/client.properties 10"
   ```

5. Shows the schema registered under subject `javascript-avro-value` with `playground schema get`, and the committed offsets of both groups with `playground consumer-group describe`.

[ccloud/client-javascript](../../ccloud/client-javascript/) uses the same image against Confluent Cloud.

To try your own client code or configuration, edit `client.js` (rebuild with `playground container recreate`) or `client.properties` (read at each run, no rebuild needed).
