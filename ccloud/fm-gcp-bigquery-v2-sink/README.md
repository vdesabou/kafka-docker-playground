# Fully Managed GCP BigQuery Sink V2 connector

## Objective

Quickly test the [Fully Managed Google BigQuery Sink V2](https://docs.confluent.io/cloud/current/connectors/cc-gcp-bigquery-storage-sink.html) connector (Storage Write API).

## Prerequisites

See [Confluent Cloud examples](https://kafka-docker-playground.io/#/how-to-use?id=%f0%9f%8c%a4%ef%b8%8f-confluent-cloud-examples).

An active Google Cloud Platform (GCP) account with authorization to create resources is required.

| Variable | Description |
| --- | --- |
| `GCP_PROJECT` | GCP project id |
| `GCP_KEYFILE_CONTENT` | Service account key content, if `./keyfile.json` is not present (see below) |

### GCP BigQuery setup

Follow [Quickstart using the web UI in the GCP Console](https://cloud.google.com/bigquery/docs/quickstarts/quickstart-web-ui) to get familiar with GCP BigQuery.

Create a `Service Account` from the IAM & Admin console and set `Service account name`:

![Service Account setup](Screenshot1.png)

Choose permission `BigQuery`->`BigQuery Admin`:

![Service Account setup](Screenshot2.png)

Create a key:

![Service Account setup](Screenshot3.png)

Download it as JSON:

![Service Account setup](Screenshot4.png)

Rename it to `keyfile.json` and place it in `./keyfile.json`, or set `GCP_KEYFILE_CONTENT`:

```bash
export GCP_KEYFILE_CONTENT=$(cat keyfile.json | jq -aRs . | sed 's/^"//' | sed 's/"$//')
```

## How to run

```bash
export GCP_PROJECT=<gcp project>
playground run -f fully-managed-gcp-bigquery-sink-v2.sh
```

| Script | Description |
| --- | --- |
| `fully-managed-gcp-bigquery-sink-v2.sh` | Avro records streamed (`ingestion.mode` `STREAMING`) to an auto-created, non-partitioned table |

## What the script does

1. Authenticates `gcloud` with the service account key (in a `google/cloud-sdk` container) and creates a BigQuery dataset.
2. Creates topic `bqtopic` and produces 10 Avro records with `playground topic produce`.
3. Creates the fully managed `BigQueryStorageSink` connector (`auto.create.tables` `NON-PARTITIONED`, `sanitize.topics`, `sanitize.field.names`).
4. Waits 60 seconds and queries table `bqtopic` with `bq query`, checking that `value1` is present.
5. Deletes the connector and the dataset at the end of the run.
