# Go client (producer/consumer)

## Objective

Quickly test the [Confluent Go Client for Apache Kafka](https://docs.confluent.io/kafka-clients/go/current/overview.html) (module [`github.com/confluentinc/confluent-kafka-go/v2`](https://pkg.go.dev/github.com/confluentinc/confluent-kafka-go/v2), built on librdkafka) and its Avro serializer for Schema Registry (`schemaregistry/serde/avrov2`) against a local Confluent Platform cluster.

## How to run

```bash
playground run -f start.sh
```

| Script | Description |
| --- | --- |
| `start.sh` | Go producer and consumer, string and Avro records, in the `client-go` container, against the plaintext broker and Schema Registry |

## What the script does

1. Starts only the `client-go` container and what it depends on (broker, Schema Registry), with `playground start-environment --service client-go`. The image is built from the `Dockerfile` (Go 1.27, `go build` of [`main.go`](main.go) with `confluent-kafka-go` v2.16.1 from [`go.mod`](go.mod), which bundles a static librdkafka). The first build takes a minute or two. The client reads its configuration from [`client.properties`](client.properties), mounted in `/tmp/client.properties`: one librdkafka property per line, plus the `schema.registry.*` properties of the Schema Registry client.
2. Creates topics `go-string` and `go-avro` with 3 partitions.
3. Produces 10 string records (key `key-<i>`, value `{"id":"payment-<i>","amount":<i>.5}`) with `acks=all` and waits for every delivery report, then consumes them with group `go-string-group` (`enable.auto.commit=false`, synchronous commit of each record, `Close()` at the end). The consumer exits with an error if fewer than 10 records arrive within 60 seconds:

   ```bash
   playground container exec -c client-go --command "client produce go-string /tmp/client.properties 10"
   playground container exec -c client-go --command "client consume go-string /tmp/client.properties 10"
   ```

4. Same with Avro records (Go struct `Payment` with fields `id` and `amount`): the `avrov2` serializer derives the schema from the struct and registers it under subject `go-avro-value`, the `avrov2` deserializer reads it back:

   ```bash
   playground container exec -c client-go --command "client produce-avro go-avro /tmp/client.properties 10"
   playground container exec -c client-go --command "client consume-avro go-avro /tmp/client.properties 10"
   ```

5. Shows the schema registered under subject `go-avro-value` with `playground schema get`, and the committed offsets of both groups with `playground consumer-group describe`.

To try your own client code or configuration, edit `main.go` (rebuild with `playground container recreate`) or `client.properties` (read at each run, no rebuild needed).

## Use another client version

Set `CLIENT_VERSION` to build the image with another confluent-kafka-go v2 version than the default, the version of `go.mod` (`go get` + `go mod tidy` in the build when set):

```bash
CLIENT_VERSION=2.10.1 playground run -f start.sh
```

Empty or unset: the default version. The client prints its version when it starts, check it in the output. It is passed as a build argument by `docker-compose.plaintext.yml`. An old version may not support everything the example uses (the Avro serializer API changed over time).
