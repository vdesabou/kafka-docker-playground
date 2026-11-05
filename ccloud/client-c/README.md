# C/C++ client (librdkafka) (producer/consumer) (using Confluent Cloud)

## Objective

Quickly test the [Confluent C/C++ Client for Apache Kafka](https://docs.confluent.io/kafka-clients/librdkafka/current/overview.html) ([librdkafka](https://github.com/confluentinc/librdkafka)) against Confluent Cloud.

The producer and consumer are the ones of [other/client-c](../../other/client-c/) (same Docker image, librdkafka from the Confluent clients apt repository). Only string records: librdkafka has no Schema Registry serializer.

## Prerequisites

See [Confluent Cloud examples](https://kafka-docker-playground.io/#/how-to-use?id=%f0%9f%8c%a4%ef%b8%8f-confluent-cloud-examples).

## How to run

```bash
playground run -f start.sh
```

| Script | Description |
| --- | --- |
| `start.sh` | C producer and consumer running in Docker containers against Confluent Cloud |

## What the script does

1. Bootstraps the Confluent Cloud environment, generates `client.properties` (gitignored, it has the API key) from [`client.properties.template`](client.properties.template) (`security.protocol=SASL_SSL`, `sasl.mechanisms=PLAIN`, `sasl.username` / `sasl.password`, `socket.keepalive.enable=true`), and registers a cleanup that deletes the topic and the consumer group at the end (success or failure).
2. Recreates topic `client_c_<TAG>` with 3 partitions, and deletes the consumer group `client_c_<TAG>-group` of a previous run.
3. Builds the `kdp-client-c` image from [other/client-c](../../other/client-c/).
4. Produces 10 records with `acks=all`, then consumes them with group `client_c_<TAG>-group` (synchronous commits, exits with an error if fewer than 10 records arrive within 60 seconds). The containers run with TCP keepalives shorter than the idle timeout of the Confluent Cloud load balancers:

   ```bash
   docker run --rm --sysctl net.ipv4.tcp_keepalive_time=60 --sysctl net.ipv4.tcp_keepalive_intvl=30 -v ${DIR}/client.properties:/tmp/client.properties:ro kdp-client-c client produce client_c_<TAG> /tmp/client.properties 10
   docker run --rm --sysctl net.ipv4.tcp_keepalive_time=60 --sysctl net.ipv4.tcp_keepalive_intvl=30 -v ${DIR}/client.properties:/tmp/client.properties:ro kdp-client-c client consume client_c_<TAG> /tmp/client.properties 10
   ```

5. Checks the records with `playground topic consume --min-expected-messages 10`.

## Use another client version

Set `CLIENT_VERSION` to build the image with another librdkafka version than the default, `2.16.0` (`DEFAULT_CLIENT_VERSION` in the `Dockerfile`, packages `librdkafka1` / `librdkafka-dev` of the Confluent apt repository):

```bash
CLIENT_VERSION=2.10.1 playground run -f start.sh
playground run -f start.sh --client-version 2.10.1   # the same, also offered by the interactive menu
```

Empty or unset: the default version. The client prints its version when it starts, check it in the output. The image is the one of [other/client-c](../../other/client-c/), built with `docker build --build-arg CLIENT_VERSION`. An old version may not support everything the example uses (the Avro serializer API changed over time).
