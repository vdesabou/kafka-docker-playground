# Fully Managed GCS Source connector

## Objective

Quickly test the [Fully Managed GCS Source](https://docs.confluent.io/cloud/current/connectors/cc-gcs-source.html) connector.

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

### Service account setup

[Instructions](https://docs.confluent.io/kafka-connect-gcs-sink/current/overview.html)

* Create a `Service Account` from the IAM & Admin console and set the `Service account name`:

![Service Account setup](Screenshot1.png)

* Choose permission `Storage Admin` (probably not all of them are required):

![Service Account setup](Screenshot2.png)

* Create a key:

![Service Account setup](Screenshot3.png)

* Download it as JSON:

![Service Account setup](Screenshot4.png)

## How to run

```bash
playground run -f fully-managed-gcs-source.sh
```

The bucket region defaults to `europe-west2` (also used as Confluent Cloud region), override it with `GCS_BUCKET_REGION`.

| Script | Description |
| --- | --- |
| `fully-managed-gcs-source.sh` | Reads a JSON file from a GCS bucket (generalized mode) |

## What the script does

1. Bootstraps the Confluent Cloud environment on GCP and recreates topic `quick-start-topic`.
2. Creates the bucket if needed, labels it, and uploads `generalized.quickstart.json` to `quickstart/`.
3. Creates the `GcsSource` fully managed connector (`topics.dir` `quickstart`, `topic.regex.list` `quick-start-topic:.*`, JSON in and out).
4. Verifies that at least 9 records are in `quick-start-topic` (`playground topic consume`).
5. Asks before deleting the connector.

## Benchmark

[`benchmark-load.bash`](benchmark-load.bash) is the load of the self-managed example [`connect-gcp-gcs-source`](../../connect/connect-gcp-gcs-source/README.md#benchmark): it loads JSON files in the GCS bucket for [`playground connector benchmark`](https://kafka-docker-playground.io/#/playground%20connector%20benchmark). Run the example, answer `n` when it asks to delete the connector, then:

```bash
# time to read a backlog of 100k records
playground connector benchmark --nb-records 100000
```

The connector runs in Confluent Cloud, so there is no JMX: the benchmark counts the records from the end offsets of the topics of the connector (`--topic` to choose them) and a drain starts measuring at the first records seen after the resume (Confluent Cloud takes a few seconds to restart the tasks), and the throughput includes the network between this machine and Confluent Cloud (ngrok tunnel). Compare runs made from the same machine.
