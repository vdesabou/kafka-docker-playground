# Google Cloud Pub/Sub Group Kafka Connector Source connector

## Objective

Quickly test the [Google Cloud Pub/Sub Group Kafka Connector](https://github.com/googleapis/java-pubsub-group-kafka-connector) source connector (open source connector from Google, not the Confluent one).

## Prerequisites

* Active Google Cloud Platform (GCP) account with authorization to create resources
* A service account key, either saved as `keyfile.json` in this folder or provided through `GCP_KEYFILE_CONTENT` (see [Service account setup](#service-account-setup))

| Variable | Description |
| --- | --- |
| `GCP_PROJECT` | GCP project ID (required) |
| `GCP_KEYFILE_CONTENT` | Content of the service account key, used when `keyfile.json` is not present |

## How to run

```bash
export GCP_PROJECT=<your-gcp-project>
playground run -f gcp-google-pubsub-source.sh
```

| Script | Description |
| --- | --- |
| `gcp-google-pubsub-source.sh` | `CloudPubSubSourceConnector` reading a Pub/Sub subscription into `pubsub-topic` |

## What the script does

1. Downloads `pubsub-group-kafka-connector-1.3.3.jar`, `grpc-netty-1.75.0.jar` and `grpc-rls-1.75.0.jar` from Maven Central if missing, and installs them as a plugin in `confluent-hub/pubsub-group-kafka-connector/`
2. Starts the environment and authenticates `gcloud` with the service account key
3. Creates a Pub/Sub topic `topic-1-g-<suffix>` and subscription `subscription-1-g-<suffix>` (ack deadline 60s), deleting them first if they exist
4. Publishes three messages (`Peter`, `Megan`, `Erin`) to the Pub/Sub topic
5. Creates the `pubsub-source` connector and verifies records arrive in `pubsub-topic` with `playground topic consume`
6. On exit, deletes the Pub/Sub topic and subscription

## Benchmark

[`benchmark-load.bash`](benchmark-load.bash) publishes `benchmark message <i>` messages to the topic of the connector (`cps.project`, `cps.topic`) for [`playground connector benchmark`](https://kafka-docker-playground.io/#/playground%20connector%20benchmark), with the Pub/Sub python client (batches of 1000 messages) in a small `playground-benchmark-python` image built the first time ([`tools/benchmark-python/benchmark_producer.py`](../../tools/benchmark-python/benchmark_producer.py)), and the `keyfile.json` of the example. The messages wait in the subscription while the connector is paused, so a drain measures the connector.

> [!IMPORTANT]
> The script deletes the topic and the subscription on exit, after a `Continue (y/n)?` prompt: answer `n` to keep them for the benchmark. Running the example again deletes and recreates them.

```bash
# drain of 100000 messages
playground connector benchmark --nb-records 100000

# throughput during 2 minutes while batches of 10000 messages are published
playground connector benchmark --mode steady --duration 2m --nb-records 10000
```

`--shape small-txn` publishes the messages one by one, waiting for each one.

> [!WARNING]
> On CP 8.x the connector of this example fails to start (`ClassCastException: class io.grpc.override.ContextStorageOverride`, see [#7650](https://github.com/vdesabou/kafka-docker-playground/issues/7650)): run the example with `--tag 7.9.0`. There, a drain of 100000 messages stalled after about 12000 records, with `Failed to acknowledge message: ... DEADLINE_EXCEEDED` in the connect logs: start with a smaller `--nb-records`.

## Service account setup

Create a `Service Account` from the IAM & Admin console.

Set the `Service account name`:

![Service Account setup](Screenshot1.png)

Choose the permission `Pub/Sub` -> `Pub/Sub Admin`:

![Service Account setup](Screenshot2.png)

Create a key:

![Service Account setup](Screenshot3.png)

Download it as JSON:

![Service Account setup](Screenshot4.png)

Rename it to `keyfile.json` and place it in this folder, or export its content in `GCP_KEYFILE_CONTENT`:

```bash
export GCP_KEYFILE_CONTENT=$(cat keyfile.json | jq -aRs . | sed 's/^"//' | sed 's/"$//')
```
