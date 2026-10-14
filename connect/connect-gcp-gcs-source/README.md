# GCS Source connector

## Objective

Quickly test the [GCS Source](https://docs.confluent.io/kafka-connectors/gcs-source/current/index.html) connector, in both [Backup and Restore](https://docs.confluent.io/kafka-connectors/gcs-source/current/backup-and-restore/overview.html) and [Generalized](https://docs.confluent.io/kafka-connectors/gcs-source/current/generalized/overview.html) modes.

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
playground run -f gcs-source-backup-and-restore.sh
```

| Script | Description |
| --- | --- |
| `gcs-source-backup-and-restore.sh` | Backup and Restore mode: GCS sink writes Avro files, GCS source reads them back into `copy_of_gcs-topic` |
| `gcs-source-generalized.sh` | Generalized mode (`mode=GENERIC`): reads a JSON file uploaded to the bucket into `quick-start-topic` (requires connector 2.1.0+) |

The bucket is created in region `europe-west2` (first script argument). Version guards (exit code 111): connector 2.0.0+ requires CP 6.0+, and CP 8.x requires connector 2.6.16+.

## What the scripts do

1. Start the environment and authenticate `gcloud` with the service account key
2. Create the bucket `kafkadockerplaygroundbucket<user>...` if needed, label it and remove existing objects under `topics/gcs-topic`
3. Backup and Restore:
   1. Produce 10 Avro records to `gcs-topic` and create the `gcs-sink` connector (`flush.size=3`)
   2. List and read one Avro file of the bucket with `playground tools read-avro-file`
   3. Create the `gcs-source` connector with a `RegexRouter` transform adding the `copy_of_` prefix, and consume 9 records from `copy_of_gcs-topic`
4. Generalized:
   1. Upload `generalized.quickstart.json` to `quickstart/` in the bucket
   2. Create the `gcs-source` connector (`JsonFormat`, `topics.dir=quickstart`, `topic.regex.list=quick-start-topic:.*`) and consume 9 records from `quick-start-topic`

## Service account setup

Create a `Service Account` from the IAM & Admin console.

Set the `Service account name`:

![Service Account setup](Screenshot1.png)

Choose the permission `Storage Admin` (probably more than required):

![Service Account setup](Screenshot2.png)

Create a key:

![Service Account setup](Screenshot3.png)

Download it as JSON:

![Service Account setup](Screenshot4.png)

Rename it to `keyfile.json` and place it in this folder, or export its content in `GCP_KEYFILE_CONTENT`:

```bash
export GCP_KEYFILE_CONTENT=$(cat keyfile.json | jq -aRs . | sed 's/^"//' | sed 's/"$//')
```
