# KafkaJS client (producer/consumer) (using Confluent Cloud)

## Objective

Quickly test [KafkaJS](https://kafka.js.org/) (npm [`kafkajs`](https://www.npmjs.com/package/kafkajs), a pure JavaScript client) and the Avro serializer of [`@kafkajs/confluent-schema-registry`](https://www.npmjs.com/package/@kafkajs/confluent-schema-registry) against Confluent Cloud and its Schema Registry.

KafkaJS is a third-party client: it has had no release since 2.2.4 (February 2023). The producer and consumer are the ones of [other/client-kafkajs](../../other/client-kafkajs/) (same Docker image). To compare with Confluent's JavaScript client, whose KafkaJS-compatible API is the usual migration path, see [ccloud/client-javascript](../client-javascript/).

## Prerequisites

See [Confluent Cloud examples](https://kafka-docker-playground.io/#/how-to-use?id=%f0%9f%8c%a4%ef%b8%8f-confluent-cloud-examples).

## How to run

```bash
playground run -f start.sh
```

| Script | Description |
| --- | --- |
| `start.sh` | KafkaJS producer and consumer, string and Avro records, running in Docker containers against Confluent Cloud |

## What the script does

1. Bootstraps the Confluent Cloud environment and generates `client.properties` (gitignored, it has the API keys) from [`client.properties.template`](client.properties.template): `bootstrap.servers`, `security.protocol=SASL_SSL`, `sasl.mechanisms=PLAIN`, `sasl.username` / `sasl.password`, mapped by `client.js` to the KafkaJS `brokers`, `ssl` and `sasl` options, and the `schema.registry.*` properties of its Schema Registry. A cleanup registered at the start deletes the topics, their subjects and the consumer groups at the end (success or failure).
2. Recreates topics `client_kafkajs_<TAG>` and `client_kafkajs_avro_<TAG>`, and deletes the consumer groups of a previous run.
3. Builds the `vdesabou/kafkajs-ccloud-example-docker` image from [other/client-kafkajs](../../other/client-kafkajs/) (Node.js 24, `kafkajs` 2.2.4, `@kafkajs/confluent-schema-registry` 4.1.0).
4. Produces 10 string records (`acks: -1`) and consumes them with group `client_kafkajs_<TAG>-group` (`autoCommit: false`, `commitOffsets` after each record). The containers mount `client.properties` read-only and run with TCP keepalives shorter than the idle timeout of the Confluent Cloud load balancers. The consumer exits with an error if fewer than 10 records arrive within 60 seconds:

   ```bash
   docker run --rm --sysctl net.ipv4.tcp_keepalive_time=60 --sysctl net.ipv4.tcp_keepalive_intvl=30 \
       -v ${DIR}/client.properties:/tmp/client.properties:ro vdesabou/kafkajs-ccloud-example-docker \
       node client.js produce client_kafkajs_<TAG> /tmp/client.properties 10
   ```

5. Same with Avro records (schema `io.confluent.playground.Payment` registered under subject `client_kafkajs_avro_<TAG>-value`, `registry.encode` / `registry.decode`).
6. Checks the Avro records with `playground topic consume --min-expected-messages 10` (Java deserializer, same schema).

The `haproxy/` folder is unrelated to this script.

## Use another client version

Set `CLIENT_VERSION` to build the image with another kafkajs version than the default, the version of `package.json` (`@kafkajs/confluent-schema-registry` keeps the version of `package-lock.json`):

```bash
CLIENT_VERSION=2.1.0 playground run -f start.sh
playground run -f start.sh --client-version 2.1.0   # the same, also offered by the interactive menu
```

Empty or unset: the default version. The client prints its version when it starts, check it in the output. The image is the one of [other/client-kafkajs](../../other/client-kafkajs/), built with `docker build --build-arg CLIENT_VERSION`.
