# Google Cloud Pub/Sub Group Kafka Connector sink connector

## Objective

Quickly test the [Google Cloud Pub/Sub Group Kafka Connector](https://github.com/googleapis/java-pubsub-group-kafka-connector) sink connector (open source connector from Google, not the Confluent one).

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
playground run -f gcp-google-pubsub-sink.sh
```

| Script | Description |
| --- | --- |
| `gcp-google-pubsub-sink.sh` | `CloudPubSubSinkConnector` publishing Kafka records (with metadata and headers) to a Pub/Sub topic |

## What the script does

1. Downloads `pubsub-group-kafka-connector-1.3.3.jar`, `grpc-netty-1.75.0.jar` and `grpc-rls-1.75.0.jar` from Maven Central if missing, and installs them as a plugin in `confluent-hub/pubsub-group-kafka-connector/`
2. Starts the environment and authenticates `gcloud` with the service account key
3. Creates a Pub/Sub topic `topic-1-gs-<suffix>` and subscription `subscription-1-gs-<suffix>` (deleting them first if they exist)
4. Produces 3 Avro records with key `key1` to `pubsub-topic`
5. Creates the `pubsub-sink` connector (`metadata.publish` and `headers.publish` enabled)
6. After 2 minutes, pulls messages from the subscription and checks a `MESSAGE_ID` is returned
7. On exit, deletes the Pub/Sub topic and subscription

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
