# Azure Blob Storage Sink connector

## Objective

Quickly test the [Azure Blob Storage Sink](https://docs.confluent.io/kafka-connectors/azure-blob-storage-sink/current/overview.html) connector.

## Prerequisites

- [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli) (`az`). The script logs in automatically: interactive browser login, or service principal login when `AZ_CLIENT_ID`, `AZ_CLIENT_SECRET` and `AZ_TENANT_ID` are set.
- With CP 8.0+, connector version 1.6.0 or later is required when `--connector-tag` is set (the scripts exit with code `111` otherwise).

| Variable | Description |
| --- | --- |
| `AZURE_SUBSCRIPTION_NAME` | [Azure subscription](https://learn.microsoft.com/en-us/cli/azure/manage-azure-subscriptions-azure-cli) where the resources are created. Mandatory with a Confluent account (for Confluent support, the subscription is `COPS`) |
| `AZURE_REGION` | Optional, Azure region (default `westeurope`) |

## How to run

```bash
playground run -f azure-blob-storage-sink.sh
```

| Script | Description |
| --- | --- |
| `azure-blob-storage-sink.sh` | Basic example |
| `azure-blob-storage-sink-proxy.sh` | Same, going through an nginx forward proxy (`azblob.proxy.url=https://nginx-proxy:8888`) |

## What the script does

1. Creates an Azure resource group, a storage account and a blob container, and writes the account name, key and container name to the `data` file (used through `${file:/data:...}` in the connector config).
2. Creates the Azure Blob Storage sink connector (`io.confluent.connect.azure.blob.AzureBlobStorageSinkConnector`) with `AvroFormat` and `flush.size=3`.
3. Produces 10 Avro records to topic `blob-topic` with `playground topic produce`.
4. Lists the files of the container, downloads `topics/blob-topic/partition=0/blob-topic+0+0000000000.avro` and displays it with `playground tools read-avro-file`.
5. On exit, asks for confirmation and then deletes the resource group.
