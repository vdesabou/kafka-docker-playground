# Rust client (producer/consumer)

## Objective

Quickly test the [Confluent Rust Client for Apache Kafka](https://docs.confluent.io/kafka-clients/rust/current/overview.html) (crate [`confluent-kafka`](https://crates.io/crates/confluent-kafka)) against a local Confluent Platform cluster.

The Rust client is a native implementation of the Kafka protocol (no librdkafka), with an API close to the Java client (`KafkaProducer`, `KafkaConsumer`, `ProducerRecord`, Java-style configuration keys). Its consumer only supports the [KIP-848](https://cwiki.apache.org/confluence/display/KAFKA/KIP-848%3A+The+Next+Generation+of+the+Consumer+Rebalance+Protocol) consumer group protocol (`group.protocol=consumer`), GA since CP 8.0: the script exits with code 111 (skipped) on an older CP version.

## How to run

```bash
playground run -f start.sh
```

| Script | Description |
| --- | --- |
| `start.sh` | Rust producer and consumer, in the `client-rust` container, against the plaintext broker |

## What the script does

1. Starts the environment with the `client-rust` container, built from the `Dockerfile` (Rust 1.95, `cargo build --release` of [`src/producer.rs`](src/producer.rs) and [`src/consumer.rs`](src/consumer.rs), with the shared configuration in [`src/common.rs`](src/common.rs)). The first build takes a few minutes.
2. Creates topic `client-rust` with 3 partitions.
3. Produces 100 records (key `key-<i>`, so they spread over the 3 partitions, value `{"count":<i>}`) with `acks=all`, and waits for every acknowledgement:

   ```bash
   playground container exec -c client-rust --command "producer broker:9092 client-rust 100"
   ```

4. Consumes them with group `client-rust-group` (`group.protocol=consumer`, `enable.auto.commit=false`, `commit_sync()` after each batch). The consumer exits with an error if fewer than 100 records arrive within 60 seconds:

   ```bash
   playground container exec -c client-rust --command "consumer broker:9092 client-rust client-rust-group 100 60"
   ```

5. Checks the records with `playground topic consume --min-expected-messages 100`, and shows the committed offsets of the group with `playground consumer-group describe --group client-rust-group`.

With the `SASL_USERNAME` and `SASL_PASSWORD` environment variables set, both binaries connect with `SASL_SSL` / `PLAIN`: [ccloud/client-rust](../../ccloud/client-rust/) uses the same image against Confluent Cloud.

To try your own client code, edit `src/producer.rs` or `src/consumer.rs`, then rebuild the container with `playground container recreate`.
