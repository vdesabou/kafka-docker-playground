# Go client (producer/consumer) (using Confluent Cloud)

## Objective

Quickly test the [Confluent Go Client for Apache Kafka](https://docs.confluent.io/kafka-clients/go/current/overview.html) (module [`github.com/confluentinc/confluent-kafka-go/v2`](https://pkg.go.dev/github.com/confluentinc/confluent-kafka-go/v2), built on librdkafka) and its Avro serializer for Schema Registry against Confluent Cloud.

The client is the one of [other/client-go](../../other/client-go/) (same code and Docker image), with a configuration file for the Confluent Cloud cluster and Schema Registry.

## Prerequisites

See [Confluent Cloud examples](https://kafka-docker-playground.io/#/how-to-use?id=%f0%9f%8c%a4%ef%b8%8f-confluent-cloud-examples).

## How to run

```bash
playground run -f start.sh
```

| Script | Description |
| --- | --- |
| `start.sh` | Go producer and consumer, string and Avro records, running in Docker containers against Confluent Cloud |

## What the script does

1. Bootstraps the Confluent Cloud environment and generates `client.properties` (gitignored, it has the API keys) from [`client.properties.template`](client.properties.template): `security.protocol=SASL_SSL`, `sasl.mechanisms=PLAIN`, the cluster API key, and the `schema.registry.*` properties of the Schema Registry client. Registers a cleanup that deletes the topics, the subject and the consumer groups at the end (success or failure).
2. Recreates topics `client_go_<TAG>` and `client_go_avro_<TAG>`, and deletes their consumer groups `<topic>-group` (committed offsets of a previous run would point past the records of the recreated topics).
3. Builds the `vdesabou/go-ccloud-example-docker` image from [other/client-go](../../other/client-go/) (Go 1.27, `confluent-kafka-go` v2.16.1).
4. Produces 10 string records with `acks=all` and consumes them. The containers run with `--sysctl net.ipv4.tcp_keepalive_time=60`, below the idle timeout of the Confluent Cloud load balancers. The consumer exits with an error if fewer than 10 records arrive within 60 seconds:

   ```bash
   docker run --rm -v ${DIR}/client.properties:/tmp/client.properties:ro vdesabou/go-ccloud-example-docker client produce client_go_<TAG> /tmp/client.properties 10
   docker run --rm -v ${DIR}/client.properties:/tmp/client.properties:ro vdesabou/go-ccloud-example-docker client consume client_go_<TAG> /tmp/client.properties 10
   ```

5. Same with Avro records (`produce-avro` / `consume-avro`): the `avrov2` serializer registers the schema of the Go struct `Payment` under subject `client_go_avro_<TAG>-value` in Confluent Cloud Schema Registry.
6. Checks the Avro records with `playground topic consume --min-expected-messages 10` (Java deserializer, same schema).

## Use another client version

Set `CLIENT_VERSION` to build the image with another confluent-kafka-go v2 version than the default, the version of `go.mod` (`go get` + `go mod tidy` in the build when set):

```bash
CLIENT_VERSION=2.10.1 playground run -f start.sh
```

Empty or unset: the default version. The client prints its version when it starts, check it in the output. The image is the one of [other/client-go](../../other/client-go/), built with `docker build --build-arg CLIENT_VERSION`. An old version may not support everything the example uses (the Avro serializer API changed over time).
