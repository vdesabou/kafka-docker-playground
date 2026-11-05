# Java client (producer/consumer) (using Confluent Cloud)

## Objective

Quickly test the [Apache Kafka Java client](https://docs.confluent.io/kafka-clients/java/current/overview.html) (`kafka-clients`) and the Confluent Avro serializer for Schema Registry (`kafka-avro-serializer`) against Confluent Cloud.

The producer and consumer are the ones of [other/client-java](../../other/client-java/) (same Docker image). They read their configuration from `client.properties`, generated from [`client.properties.template`](client.properties.template) with the cluster and Schema Registry of the environment (`security.protocol=SASL_SSL`, `sasl.mechanism=PLAIN`, `sasl.jaas.config` with the API key and secret, `basic.auth.user.info` for Schema Registry). The file is gitignored.

## Prerequisites

See [Confluent Cloud examples](https://kafka-docker-playground.io/#/how-to-use?id=%f0%9f%8c%a4%ef%b8%8f-confluent-cloud-examples).

## How to run

```bash
playground run -f start.sh
```

| Script | Description |
| --- | --- |
| `start.sh` | Java producer and consumer, string and Avro records, in Docker containers against Confluent Cloud and its Schema Registry |

## What the script does

1. Bootstraps the Confluent Cloud environment, generates `client.properties`, and registers a cleanup that deletes the topics (with their subjects) and the consumer groups at the end (success or failure).
2. Recreates topics `client_java_<TAG>` and `client_java_avro_<TAG>` with 3 partitions, and deletes the consumer groups of a previous run.
3. Builds the `kdp-client-java` image from [other/client-java](../../other/client-java/).
4. Produces 10 string records and consumes them with group `client_java_<TAG>-group`, then 10 Avro records (`KafkaAvroSerializer`, subject `client_java_avro_<TAG>-value`) consumed with `KafkaAvroDeserializer`. The containers run with shorter TCP keepalives than the Linux default, below the idle timeout of the Confluent Cloud load balancers:

   ```bash
   docker run --rm --sysctl net.ipv4.tcp_keepalive_time=60 --sysctl net.ipv4.tcp_keepalive_intvl=30 \
       -v ${DIR}/client.properties:/tmp/client.properties:ro kdp-client-java \
       java -jar client-java.jar produce-avro client_java_avro_<TAG> /tmp/client.properties 10
   ```

   Each consumer exits with an error if fewer than 10 records arrive within 60 seconds.

5. Checks the Avro records with `playground topic consume --min-expected-messages 10`.

## Use another client version

Set `CLIENT_VERSION` to build the image with another kafka-clients version than the default, the `kafka.version` of `pom.xml` (`-Dkafka.version` in the build when set). `kafka-avro-serializer` follows with the Confluent Platform release of that Apache Kafka version: the `confluent.version` of `pom.xml` for 4.x, `7.N.0` for 3.N, `6.0.0`-`6.2.0` for 2.6-2.8, `5.N.0` for 2.0-2.5 (the 8.x serializer needs kafka-clients 4.x):

```bash
CLIENT_VERSION=3.9.1 playground run -f start.sh
```

Empty or unset: the default version. The client prints its version when it starts, check it in the output. The image is the one of [other/client-java](../../other/client-java/), built with `docker build --build-arg CLIENT_VERSION`. An old version may not support everything the example uses (the Avro serializer API changed over time).
