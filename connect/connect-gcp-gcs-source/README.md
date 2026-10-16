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

The bucket is created in region `europe-west2` (override with `GCS_BUCKET_REGION`). Version guards (exit code 111): connector 2.0.0+ requires CP 6.0+, and CP 8.x requires connector 2.6.16+.

## What the scripts do

1. Start the environment and authenticate `gcloud` with the service account key
2. Create the bucket `kafkadockerplaygroundbucket<user>...` if needed, label it and remove existing objects under `topics/gcs-topic`
3. Backup and Restore:
   1. Produce 10 Avro records to `gcs-topic` and create the `gcs-sink` connector (`flush.size=3`)
   2. List and read one Avro file of the bucket with `playground tools read-avro-file`
   3. Create the `gcs-source` connector with a `RegexRouter` transform adding the `copy_of_` prefix, and consume 9 records from `copy_of_gcs-topic`
4. Generalized:
   1. Empty `quickstart/` in the bucket (files left by a benchmark) and upload `generalized.quickstart.json` to it
   2. Create the `gcs-source` connector (`JsonFormat`, `topics.dir=quickstart`, `topic.regex.list=quick-start-topic:.*`) and consume 9 records from `quick-start-topic`

## Benchmark

[`benchmark-load.bash`](benchmark-load.bash) loads [`playground connector benchmark`](https://kafka-docker-playground.io/#/playground%20connector%20benchmark) with JSON files of `{"f1":"benchmark message <i>"}` lines (one record per line), uploaded to the `topics.dir` of the connector with `gcloud storage cp` and the credentials of the `gcloud-config` container created by the example. It applies to the generalized mode only (`mode=GENERIC` with a JSON format, `gcs-source-generalized.sh`); the Backup and Restore mode reads the files of a sink, and is refused. Once the example is running:

```bash
# drain of 100000 records in 10 files
playground connector benchmark --nb-records 100000

# per-object overhead: 2000 files of one record
playground connector benchmark --nb-records 2000 --shape small-txn

# throughput during 2 minutes while files of 20000 records are uploaded
playground connector benchmark --mode steady --duration 2m --nb-records 20000
```

The connector lists the objects after the last one it read (`startAfter`), so the files are named
`zz-benchmark-<epoch>-<batch>-<pid>-<n>.json`: they sort after the files of the example and of the previous runs.
For the same reason, steady mode uploads one file per batch, one after the other, and `--sessions` must not be used in
steady mode: an object uploaded after a higher name was read is skipped.

| Option | Load |
| --- | --- |
| `--shape bulk` (default) | files of `BENCHMARK_FILE_RECORDS` records (default `10000`) |
| `--shape small-txn` | one record per file: the cost of listing and opening each object (drain only, the upload of many small objects is slow) |
| `--mode steady` | one file of `--nb-records` records per batch |

`--shape update` and `--shape delete` are refused: a rewritten object is not read again.

In generalized mode, a task gets `task.batch.size` files at a time (default `10`), and the connector looks for new files
every `gcs.poll.interval.ms` (default `60000`), reconfiguring its task. With the default load (files of 10000 records),
the drain therefore goes by steps of 100000 records per minute, whatever the speed of the connector: raise
`task.batch.size` or lower `gcs.poll.interval.ms` to see the difference. The task restarts reset its JMX counters, so
the benchmark counts the records in the topic instead, and says so.

A steady load faster than that (the summary says the load generated much more than the connector processed) leaves
files in the bucket, that the next runs read too: rerun the example, which empties the `quickstart` folder.

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
