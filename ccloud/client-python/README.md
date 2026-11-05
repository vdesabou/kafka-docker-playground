# Python client (producer/consumer) (using Confluent Cloud)

## Objective

Quickly test the [Confluent Python Client for Apache Kafka](https://docs.confluent.io/kafka-clients/python/current/overview.html) (PyPI [`confluent-kafka`](https://pypi.org/project/confluent-kafka/), built on librdkafka) and its Avro serializer for Schema Registry against Confluent Cloud.

The producer and consumer are the ones of [other/client-python](../../other/client-python/) (same Docker image and [`client.py`](../../other/client-python/client.py)), with a configuration for the Confluent Cloud cluster and Schema Registry.

## Prerequisites

See [Confluent Cloud examples](https://kafka-docker-playground.io/#/how-to-use?id=%f0%9f%8c%a4%ef%b8%8f-confluent-cloud-examples).

## How to run

```bash
playground run -f start.sh
```

| Script | Description |
| --- | --- |
| `start.sh` | Python producer and consumer, string and Avro records, running in Docker containers against Confluent Cloud and its Schema Registry |

## What the script does

1. Bootstraps the Confluent Cloud environment, and generates `client.properties` (gitignored, it has the API keys) from [`client.properties.template`](client.properties.template): `security.protocol=SASL_SSL`, `sasl.mechanisms=PLAIN`, the cluster API key and secret, and the `schema.registry.*` properties of the Schema Registry client. A cleanup deletes the topics (and their subjects) and the consumer groups at the end (success or failure).
2. Recreates topics `client_python_<TAG>` and `client_python_avro_<TAG>`, and deletes their consumer groups `<topic>-group` (committed offsets of a previous run would point past the records of the recreated topics).
3. Builds the `kdp-client-python` image from [other/client-python](../../other/client-python/) (`confluent-kafka[avro,schemaregistry]` 2.16.1, librdkafka 2.16.0).
4. Produces 10 string records with `acks=all`, then consumes them. The consumer exits with an error if fewer than 10 records arrive within 60 seconds. The containers run with `--sysctl net.ipv4.tcp_keepalive_time=60`, below the idle timeout of the Confluent Cloud load balancers:

   ```bash
   docker run --rm --sysctl net.ipv4.tcp_keepalive_time=60 --sysctl net.ipv4.tcp_keepalive_intvl=30 -v ${DIR}/client.properties:/tmp/client.properties:ro kdp-client-python python client.py produce client_python_<TAG> /tmp/client.properties 10
   docker run --rm --sysctl net.ipv4.tcp_keepalive_time=60 --sysctl net.ipv4.tcp_keepalive_intvl=30 -v ${DIR}/client.properties:/tmp/client.properties:ro kdp-client-python python client.py consume client_python_<TAG> /tmp/client.properties 10
   ```

5. Same with Avro records (`produce-avro` / `consume-avro`): `AvroSerializer` registers the schema under subject `client_python_avro_<TAG>-value` in the Schema Registry of the environment, `AvroDeserializer` reads it back.
6. Checks the Avro records with `playground topic consume --min-expected-messages 10` (Java deserializer, same schema).

## Use another client version

Set `CLIENT_VERSION` to build the image with another confluent-kafka (with the avro and schemaregistry extras) version than the default, the version of `requirements.txt`:

```bash
CLIENT_VERSION=2.10.1 playground run -f start.sh
```

Empty or unset: the default version. The client prints its version when it starts, check it in the output. The image is the one of [other/client-python](../../other/client-python/), built with `docker build --build-arg CLIENT_VERSION`. An old version may not support everything the example uses (the Avro serializer API changed over time).
