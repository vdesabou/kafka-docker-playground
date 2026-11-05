# Rust client (producer/consumer) (using Confluent Cloud)

## Objective

Quickly test the [Confluent Rust Client for Apache Kafka](https://docs.confluent.io/kafka-clients/rust/current/overview.html) (crate [`confluent-kafka`](https://crates.io/crates/confluent-kafka)) against Confluent Cloud.

The producer and consumer are the ones of [other/client-rust](../../other/client-rust/) (same Docker image): with the `SASL_USERNAME` and `SASL_PASSWORD` environment variables set, they connect with `security.protocol=SASL_SSL`, `sasl.mechanism=PLAIN` and a `sasl.jaas.config` built from the API key and secret (PLAIN is the only SASL mechanism of the Rust client 1.0). The consumer uses the [KIP-848](https://cwiki.apache.org/confluence/display/KAFKA/KIP-848%3A+The+Next+Generation+of+the+Consumer+Rebalance+Protocol) consumer group protocol (`group.protocol=consumer`), the only one the client supports.

## Prerequisites

See [Confluent Cloud examples](https://kafka-docker-playground.io/#/how-to-use?id=%f0%9f%8c%a4%ef%b8%8f-confluent-cloud-examples).

## How to run

```bash
playground run -f start.sh
```

| Script | Description |
| --- | --- |
| `start.sh` | Rust producer and consumer running in Docker containers against Confluent Cloud |

## What the script does

1. Bootstraps the Confluent Cloud environment, and registers a cleanup that deletes the topic and the consumer group at the end (success or failure).
2. Recreates topic `client_rust_<TAG>` with 3 partitions.
3. Builds the `kdp-client-rust` image from [other/client-rust](../../other/client-rust/) (Rust 1.95, the first build takes a few minutes).
4. Produces 100 records with `acks=all` and waits for every acknowledgement. The API key and secret are passed as environment variables, never on a command line:

   ```bash
   docker run --rm -e SASL_USERNAME -e SASL_PASSWORD kdp-client-rust producer "$BOOTSTRAP_SERVERS" client_rust_<TAG> 100
   ```

5. Consumes them with group `client_rust_group_<TAG>` (`group.protocol=consumer`, `commit_sync()` after each batch). The consumer exits with an error if fewer than 100 records arrive within 120 seconds:

   ```bash
   docker run --rm -e SASL_USERNAME -e SASL_PASSWORD kdp-client-rust consumer "$BOOTSTRAP_SERVERS" client_rust_<TAG> client_rust_group_<TAG> 100 120
   ```

6. Checks the records with `playground topic consume --min-expected-messages 100`, and shows the committed offsets of the group with `playground consumer-group describe`.

## Use another client version

Set `CLIENT_VERSION` to build the image with another confluent-kafka crate version than the default, the version pinned in `Cargo.toml`:

```bash
CLIENT_VERSION=1.0.0-rc.2 playground run -f start.sh
playground run -f start.sh --client-version 1.0.0-rc.2   # the same, also offered by the interactive menu
```

Empty or unset: the default version. The client prints its version when it starts, check it in the output. The image is the one of [other/client-rust](../../other/client-rust/), built with `docker build --build-arg CLIENT_VERSION`. An old version may not support everything the example uses (the Avro serializer API changed over time).
