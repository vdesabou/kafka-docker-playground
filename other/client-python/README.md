# Python client (producer/consumer)

## Objective

Quickly test the [Confluent Python Client for Apache Kafka](https://docs.confluent.io/kafka-clients/python/current/overview.html) (PyPI [`confluent-kafka`](https://pypi.org/project/confluent-kafka/), built on librdkafka) and its Avro serializer for Schema Registry against a local Confluent Platform cluster.

## How to run

```bash
playground run -f start.sh
```

| Script | Description |
| --- | --- |
| `start.sh` | Python producer and consumer, string and Avro records, in the `client-python` container, against the plaintext broker and Schema Registry |

## What the script does

1. Starts only the `client-python` container and what it depends on (broker, Schema Registry), with `playground start-environment --service client-python`. The image is built from the `Dockerfile` (`python:3.13-slim`, `confluent-kafka[avro,schemaregistry]` 2.16.1 from [`requirements.txt`](requirements.txt), whose wheel bundles librdkafka 2.16.0). The client is [`client.py`](client.py), and reads its configuration from [`client.properties`](client.properties), mounted in `/tmp/client.properties`: one librdkafka property per line, plus the `schema.registry.*` properties of the Schema Registry client.
2. Creates topics `python-string` and `python-avro` with 3 partitions.
3. Produces 10 string records (key `key-<i>`, value `{"id":"key-<i>","amount":<i * 10.5>}`) with `acks=all` and waits for every acknowledgement, then consumes them with group `python-string-group` (`enable.auto.commit=false`, synchronous commit of each record, `close()` at the end). The consumer exits with an error if fewer than 10 records arrive within 60 seconds:

   ```bash
   playground container exec -c client-python --command "python client.py produce python-string /tmp/client.properties 10"
   playground container exec -c client-python --command "python client.py consume python-string /tmp/client.properties 10"
   ```

4. Same with Avro records (schema `io.confluent.playground.Payment` with fields `id` and `amount`): `AvroSerializer` registers the schema under subject `python-avro-value`, `AvroDeserializer` reads it back:

   ```bash
   playground container exec -c client-python --command "python client.py produce-avro python-avro /tmp/client.properties 10"
   playground container exec -c client-python --command "python client.py consume-avro python-avro /tmp/client.properties 10"
   ```

5. Shows the schema registered under subject `python-avro-value` with `playground schema get`, and the committed offsets of both groups with `playground consumer-group describe`.

To try your own client code or configuration, edit `client.py` (rebuild with `playground container recreate`) or `client.properties` (read at each run, no rebuild needed). [ccloud/client-python](../../ccloud/client-python/) runs the same image against Confluent Cloud.

## Use another client version

Set `CLIENT_VERSION` to build the image with another confluent-kafka (with the avro and schemaregistry extras) version than the default, the version of `requirements.txt`:

```bash
CLIENT_VERSION=2.10.1 playground run -f start.sh
```

Empty or unset: the default version. The client prints its version when it starts, check it in the output. It is passed as a build argument by `docker-compose.plaintext.yml`. An old version may not support everything the example uses (the Avro serializer API changed over time).
