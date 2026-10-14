# Azure Data Lake Storage Gen2 Sink connector

## Objective

Quickly test the [Azure Data Lake Storage Gen2 Sink](https://docs.confluent.io/kafka-connectors/azure-data-lake-gen2-sink/current/overview.html) connector.

## Prerequisites

- [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli) (`az`). The script logs in automatically: interactive browser login, or service principal login when `AZ_CLIENT_ID`, `AZ_CLIENT_SECRET` and `AZ_TENANT_ID` are set. Outside CI, your account must be allowed to register an Entra (Azure AD) app and assign roles.
- With CP 8.0+, connector version 1.6.0 or later is required when `--connector-tag` is set (the script exits with code `111` otherwise).

| Variable | Description |
| --- | --- |
| `AZURE_SUBSCRIPTION_NAME` | [Azure subscription](https://learn.microsoft.com/en-us/cli/azure/manage-azure-subscriptions-azure-cli) where the resources are created (list them with `az account list`). Mandatory with a Confluent account (for Confluent support, the subscription is `COPS`) |
| `AZURE_REGION` | Optional, Azure region (default `westeurope`) |

## How to run

```bash
playground run -f azure-data-lake-storage-gen2-sink.sh
```

| Script | Description |
| --- | --- |
| `azure-data-lake-storage-gen2-sink.sh` | Data Lake Storage Gen2 sink connector with OAuth (service principal) authentication |

## What the script does

1. Creates an Azure resource group. Outside CI, registers the Entra app `pg<user>`, resets its client secret, creates its service principal and assigns it the `Storage Blob Data Owner` role on the resource group.
2. Creates a `StorageV2` storage account and writes the client id, secret, account name and token endpoint to the `data` file (used through `${file:/data:...}` in the connector config).
3. Creates the Data Lake Storage Gen2 sink connector (`io.confluent.connect.azure.datalake.gen2.AzureDataLakeGen2SinkConnector`) with `AvroFormat` and `flush.size=3`.
4. Produces 10 Avro records to topic `datalake-topic` with `playground topic produce`.
5. Lists the files of the `topics` file system, downloads `datalake-topic/partition=0/datalake-topic+0+0000000000.avro` and displays it with `playground tools read-avro-file`.
6. On exit, asks for confirmation and then deletes the resource group.
