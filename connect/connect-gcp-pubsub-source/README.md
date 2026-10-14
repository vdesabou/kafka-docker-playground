# GCP Pub/Sub Source connector

## Objective

Quickly test the [GCP Pub/Sub Source](https://docs.confluent.io/kafka-connectors/gcp-pubsub/current/overview.html) connector.

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
playground run -f gcp-pubsub-source.sh
```

| Script | Description |
| --- | --- |
| `gcp-pubsub-source.sh` | Basic example, also checks that messages are acknowledged (no redelivery after the ack deadline) |
| `gcp-pubsub-source-nginx-proxy.sh` | Same, through an nginx HTTP/2 forward proxy (`gcp.pubsub.proxy.url=nginx_http2_proxy:8888`); not supported on arm64 |

Requires connector version 1.2.10 or later with CP 8.x (the scripts exit with code 111 otherwise).

## What the scripts do

1. Start the environment (plus the `nginx_http2_proxy` container for the proxy variant) and authenticate `gcloud` with the service account key
2. Create a Pub/Sub topic and subscription (ack deadline 60s), deleting them first if they exist
3. Publish three messages (`Peter`, `Megan`, `Erin`) to the Pub/Sub topic
4. Create the `pubsub-source` connector and verify 3 records arrive in the Kafka topic (`pubsub-topic-<suffix>` for the basic example, `pubsub-topic` for the proxy variant) with `playground topic consume`
5. Basic example only: wait 80 seconds and fail if messages were redelivered (exactly 3 records expected)
6. On exit, delete the Pub/Sub topic and subscription

Records look like:

```json
{"MessageData":{"string":"Megan"},"AttributesMap":{}}
{"MessageData":{"string":"Peter"},"AttributesMap":{}}
{"MessageData":{"string":"Erin"},"AttributesMap":{}}
```

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
