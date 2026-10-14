# Custom SMT example with HTTP V2 Sink connector

## Objective

Quickly test a [Custom SMT](https://docs.confluent.io/cloud/current/connectors/configure-custom-single-message-transforms/quick-start-custom-smt.html) with the fully managed HTTP V2 Sink connector.

## Prerequisites

See [Confluent Cloud examples](https://kafka-docker-playground.io/#/how-to-use?id=%f0%9f%8c%a4%ef%b8%8f-confluent-cloud-examples).

| Variable | Description |
| --- | --- |
| `NGROK_AUTH_TOKEN` | Required. [Ngrok](https://ngrok.com) auth token, used to expose the local HTTP server to the internet so that the fully managed connector can reach it |

The Confluent Cloud cluster must be in a region where [Custom SMT is supported](https://docs.confluent.io/cloud/current/connectors/configure-custom-single-message-transforms/custom-smt-limitations-support.html); the script exits with an error otherwise.

## How to run

```bash
export NGROK_AUTH_TOKEN=<your ngrok auth token>
playground run -f fm-custom-smt-http-v2-sink.sh
```

| Script | Description |
| --- | --- |
| `fm-custom-smt-http-v2-sink.sh` | HTTP V2 Sink with the custom `InsertUuid` SMT uploaded as a Confluent Cloud connect artifact |

## What the script does

1. Clones and builds [kafka-connect-insert-uuid](https://github.com/confluentinc/kafka-connect-insert-uuid) (`InsertUuid-1.0-SNAPSHOT.jar`), if not already built.
2. Checks that the cluster region supports Custom SMT, then uploads the JAR as connect artifact `pg_<user>_insert_uuid_smt` with `confluent connect artifact create` (replacing an existing one) and waits for it to be `READY`.
3. Starts a local HTTP server and ngrok (`docker-compose.noauth.yml`).
4. Produces 10 Avro records to topic `http-topic` with `playground topic produce`.
5. Creates the fully managed `HttpSinkV2` connector with the `InsertUuid$Value` transform (`custom.smt.artifact.id`).
6. Verifies 10 records in `success-<connector id>` with `playground topic consume`, and that the HTTP server received a `uuid` field.
7. Deletes the connector and the SMT artifact at the end of the run.
