# Azure Blob Storage Source connector

## Objective

Quickly test the [Azure Blob Storage Source](https://docs.confluent.io/kafka-connectors/azure-blob-storage-source/current/index.html) connector, in both modes:

- [Backup and Restore Azure Blob Storage Source](https://docs.confluent.io/kafka-connectors/azure-blob-storage-source/current/backup-and-restore/overview.html): reads data written by the Azure Blob Storage sink connector.
- [Generalized Azure Blob Storage Source](https://docs.confluent.io/kafka-connectors/azure-blob-storage-source/current/generalized/overview.html) (`mode=GENERIC`, connector 2.2.0+): reads arbitrary files.

## Prerequisites

- [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli) (`az`). The script logs in automatically: interactive browser login, or service principal login when `AZ_CLIENT_ID`, `AZ_CLIENT_SECRET` and `AZ_TENANT_ID` are set.
- Version guards (the scripts exit with code `111` otherwise): connector 2.0.0+ requires CP 6.0+, and with CP 8.0+ connector version 2.6.16 or later is required when `--connector-tag` is set. `azure-blob-storage-source-generalized.sh` requires connector 2.2.0+.

| Variable | Description |
| --- | --- |
| `AZURE_SUBSCRIPTION_NAME` | [Azure subscription](https://learn.microsoft.com/en-us/cli/azure/manage-azure-subscriptions-azure-cli) where the resources are created. Mandatory with a Confluent account (for Confluent support, the subscription is `COPS`) |
| `AZURE_REGION` | Optional, Azure region (default `westeurope`) |

## How to run

```bash
playground run -f azure-blob-storage-source-backup-and-restore.sh
```

| Script | Description |
| --- | --- |
| `azure-blob-storage-source-backup-and-restore.sh` | Backup and Restore mode |
| `azure-blob-storage-source-proxy-backup-and-restore.sh` | Same, with the sink and source connectors going through an nginx forward proxy (`azblob.proxy.url=https://nginx-proxy:8888`); direct traffic to the storage account is blocked with `playground debug block-traffic` to make sure the proxy is used |
| `azure-blob-storage-source-generalized.sh` | Generalized mode reading `generalized.quickstart.json` |

## What the script does

1. Creates an Azure resource group, a storage account and a blob container, and writes the account name, key and container name to the `data` file (used through `${file:/data:...}` in the connector configs).
2. Backup and Restore: creates an Azure Blob Storage sink connector (`AvroFormat`), produces Avro records to `blob-topic`, then downloads one file and displays it with `playground tools read-avro-file`.
3. Backup and Restore: creates the source connector (`io.confluent.connect.azure.blob.storage.AzureBlobStorageSourceConnector`) with `CloudStorageAvroFormat` and a `RegexRouter` transform adding the `copy_of_` prefix, then verifies records are received in `copy_of_blob-topic`.
4. Generalized: uploads `generalized.quickstart.json` to `quickstart/`, creates the source connector with `mode=GENERIC`, `CloudStorageJsonFormat` and `topic.regex.list=quick-start-topic:.*`, then verifies 9 records are received in `quick-start-topic`.
5. On exit, asks for confirmation and then deletes the resource group.

## Benchmark

[`benchmark-load.bash`](benchmark-load.bash) loads [`playground connector benchmark`](https://kafka-docker-playground.io/#/playground%20connector%20benchmark) with JSON files of `{"f1":"benchmark message <i>"}` lines (one record per line), uploaded to the `topics.dir` of the connector with `az storage blob upload-batch` and the account of the `data` file written by the example. It applies to the generalized mode only (`mode=GENERIC` with a JSON format, `azure-blob-storage-source-generalized.sh`); the Backup and Restore mode reads the files of a sink, and is refused. Once the example is running:

> [!IMPORTANT]
> The script deletes the resource group on exit, after a `Continue (y/n)?` prompt: answer `n` to keep the storage account, run the benchmark, then delete it with `az group delete --name <resource group> --yes`.

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
every `azblob.poll.interval.ms` (default `60000`), reconfiguring its task. With the default load (files of 10000 records),
the drain therefore goes by steps of 100000 records per minute, whatever the speed of the connector: raise
`task.batch.size` or lower `azblob.poll.interval.ms` to see the difference. The task restarts reset its JMX counters, so
the benchmark counts the records in the topic instead, and says so.

A steady load faster than that (the summary says the load generated much more than the connector processed) leaves
files in the bucket, that the next runs read too: rerun the example, which creates a new storage account.
