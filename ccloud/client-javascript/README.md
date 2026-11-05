# JavaScript client (producer/consumer) (using Confluent Cloud)

## Objective

Quickly test the [Confluent JavaScript Client for Apache Kafka](https://docs.confluent.io/kafka-clients/javascript/current/overview.html) (npm [`@confluentinc/kafka-javascript`](https://www.npmjs.com/package/@confluentinc/kafka-javascript), built on librdkafka) and the Avro serializer of [`@confluentinc/schemaregistry`](https://www.npmjs.com/package/@confluentinc/schemaregistry) against Confluent Cloud and its Schema Registry.

The producer and consumer are the ones of [other/client-javascript](../../other/client-javascript/) (same Docker image): this is Confluent's client, not [KafkaJS](https://kafka.js.org/) (see [ccloud/client-kafkajs](../client-kafkajs/)).

## Prerequisites

See [Confluent Cloud examples](https://kafka-docker-playground.io/#/how-to-use?id=%f0%9f%8c%a4%ef%b8%8f-confluent-cloud-examples).

## How to run

```bash
playground run -f start.sh
```

| Script | Description |
| --- | --- |
| `start.sh` | JavaScript producer and consumer, string and Avro records, running in Docker containers against Confluent Cloud |

## What the script does

1. Bootstraps the Confluent Cloud environment and generates `client.properties` (gitignored, it has the API keys) from [`client.properties.template`](client.properties.template): the librdkafka properties of the cluster (`SASL_SSL`, `PLAIN`) and the `schema.registry.*` properties of its Schema Registry. A cleanup registered at the start deletes the topics, their subjects and the consumer groups at the end (success or failure).
2. Recreates topics `client_javascript_<TAG>` and `client_javascript_avro_<TAG>`, and deletes the consumer groups of a previous run.
3. Builds the `vdesabou/javascript-ccloud-example-docker` image from [other/client-javascript](../../other/client-javascript/) (Node.js 24, `@confluentinc/kafka-javascript` and `@confluentinc/schemaregistry` 1.11.0).
4. Produces 10 string records and consumes them with group `client_javascript_<TAG>-group`. The containers mount `client.properties` read-only and run with TCP keepalives shorter than the idle timeout of the Confluent Cloud load balancers. The consumer exits with an error if fewer than 10 records arrive within 60 seconds:

   ```bash
   docker run --rm --sysctl net.ipv4.tcp_keepalive_time=60 --sysctl net.ipv4.tcp_keepalive_intvl=30 \
       -v ${DIR}/client.properties:/tmp/client.properties:ro vdesabou/javascript-ccloud-example-docker \
       node client.js produce client_javascript_<TAG> /tmp/client.properties 10
   ```

5. Same with Avro records (`AvroSerializer`, schema `io.confluent.playground.Payment` registered under subject `client_javascript_avro_<TAG>-value`, then `AvroDeserializer`).
6. Checks the Avro records with `playground topic consume --min-expected-messages 10` (Java deserializer, same schema).

## Use another client version

Set `CLIENT_VERSION` to build the image with another @confluentinc/kafka-javascript version than the default, the version of `package.json` (`@confluentinc/schemaregistry` keeps the version of `package-lock.json`):

```bash
CLIENT_VERSION=1.6.0 playground run -f start.sh
```

Empty or unset: the default version. The client prints its version when it starts, check it in the output. The image is the one of [other/client-javascript](../../other/client-javascript/), built with `docker build --build-arg CLIENT_VERSION`. An old version may not support everything the example uses (the Avro serializer API changed over time).
