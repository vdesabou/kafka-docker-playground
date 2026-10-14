# Fully Managed GCP Pub/Sub Source connector

## Objective

Quickly test the [Fully Managed GCP Pub/Sub Source](https://docs.confluent.io/cloud/current/connectors/cc-google-pubsub-source.html) connector.

## Prerequisites

See [Confluent Cloud examples](https://kafka-docker-playground.io/#/how-to-use?id=%f0%9f%8c%a4%ef%b8%8f-confluent-cloud-examples).

You need an active Google Cloud Platform (GCP) account with authorization to create resources.

| Variable | Description |
| --- | --- |
| `GCP_PROJECT` | GCP project id (required) |
| `GCP_KEYFILE_CONTENT` | Service account key content, only needed if `keyfile.json` is not present in this folder |

GCP credentials: rename the service account key to `keyfile.json` and place it in this folder, or export `GCP_KEYFILE_CONTENT`, generated with:

```bash
GCP_KEYFILE_CONTENT=$(cat keyfile.json | jq -aRs . | sed 's/^"//' | sed 's/"$//')
```

### GCP Pub/Sub setup

* Create a `Service Account` from the IAM & Admin console and set the `Service account name`:

![Service Account setup](Screenshot1.png)

* Choose permission `Pub/Sub` -> `Pub/Sub Admin`:

![Service Account setup](Screenshot2.png)

* Create a key:

![Service Account setup](Screenshot3.png)

* Download it as JSON:

![Service Account setup](Screenshot4.png)

## How to run

```bash
playground run -f fully-managed-gcp-pubsub-source.sh
```

| Script | Description |
| --- | --- |
| `fully-managed-gcp-pubsub-source.sh` | Reads messages from a Pub/Sub subscription |

## What the script does

1. Bootstraps the Confluent Cloud environment and recreates topic `pubsub-topic`.
2. Creates Pub/Sub topic `topic-1-fm-<suffix>` and subscription `subscription-1-fm-<suffix>` (suffix is the CP tag or the CI run number).
3. Publishes 3 messages to the Pub/Sub topic.
4. Creates the `PubSubSource` fully managed connector.
5. Verifies that 3 records are in `pubsub-topic` (`playground topic consume`).
6. Asks before deleting the connector; on exit, deletes the Pub/Sub topic and subscription.
