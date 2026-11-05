# KafkaJS client (producer/consumer)

## Objective

Quickly test [KafkaJS](https://kafka.js.org/) (npm [`kafkajs`](https://www.npmjs.com/package/kafkajs), a pure JavaScript client) and the Avro serializer of [`@kafkajs/confluent-schema-registry`](https://www.npmjs.com/package/@kafkajs/confluent-schema-registry) against a local Confluent Platform cluster and Schema Registry.

KafkaJS is a third-party client: it has had no release since 2.2.4 (February 2023). To compare with Confluent's JavaScript client, whose KafkaJS-compatible API is the usual migration path, see [other/client-javascript](../client-javascript/). [ccloud/client-kafkajs](../../ccloud/client-kafkajs/) uses the same image against Confluent Cloud.

## How to run

```bash
playground run -f start.sh
```

| Script | Description |
| --- | --- |
| `start.sh` | KafkaJS producer and consumer, string and Avro records, in the `client-kafkajs` container |

## What the script does

1. Starts only the `client-kafkajs` container and what it depends on (broker, Schema Registry), with `playground start-environment --service client-kafkajs`. The image is built from the `Dockerfile` (Node.js 24, `npm ci` of `kafkajs` 2.2.4 and `@kafkajs/confluent-schema-registry` 4.1.0 from [`package.json`](package.json) / `package-lock.json`). The client reads [`client.properties`](client.properties), mounted in `/tmp/client.properties`: the same librdkafka-style properties as the other client examples (`bootstrap.servers`, `security.protocol`, `sasl.mechanisms`, `sasl.username`, `sasl.password`), mapped by [`client.js`](client.js) to the KafkaJS `brokers`, `ssl` and `sasl` options, plus `schema.registry.url` (and `schema.registry.basic.auth.user.info`).
2. Creates topics `kafkajs-string` and `kafkajs-avro` with 3 partitions.
3. Produces 10 string records (`acks: -1`, awaiting each send) and consumes them with group `kafkajs-string-group` (`autoCommit: false`, `commitOffsets` after each record). The consumer exits with an error if fewer than 10 records arrive within 60 seconds:

   ```bash
   playground container exec -c client-kafkajs --command "node client.js produce kafkajs-string /tmp/client.properties 10"
   playground container exec -c client-kafkajs --command "node client.js consume kafkajs-string /tmp/client.properties 10"
   ```

4. Same with Avro records: schema `io.confluent.playground.Payment` registered under subject `kafkajs-avro-value`, `registry.encode` / `registry.decode` of `@kafkajs/confluent-schema-registry`.
5. Shows the schema with `playground schema get --subject kafkajs-avro-value`, and the committed offsets of both groups with `playground consumer-group describe`.

The image sets `NODE_OPTIONS=--disable-warning=TimeoutNegativeWarning`: kafkajs passes a negative delay to `setTimeout`, which Node.js 23+ reports on every client run (`TimeoutNegativeWarning: … is a negative number.`).

To try your own client code or configuration, edit `client.js` (rebuild with `playground container recreate`) or `client.properties` (read at each run, no rebuild needed).

## Use another client version

Set `CLIENT_VERSION` to build the image with another kafkajs version than the default, the version of `package.json` (`@kafkajs/confluent-schema-registry` keeps the version of `package-lock.json`):

```bash
CLIENT_VERSION=2.1.0 playground run -f start.sh
playground run -f start.sh --client-version 2.1.0   # the same, also offered by the interactive menu
```

Empty or unset: the default version. The client prints its version when it starts, check it in the output. It is passed as a build argument by `docker-compose.plaintext.yml`.
