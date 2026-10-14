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
