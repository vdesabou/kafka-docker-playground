# Fully Managed Azure Data Lake Storage Gen2 Sink connector

## Objective

Quickly test the [Fully Managed Azure Data Lake Storage Gen2 Sink](https://docs.confluent.io/cloud/current/connectors/cc-azure-datalakeGen2-storage-sink.html) connector.

## Prerequisites

See [Confluent Cloud examples](https://kafka-docker-playground.io/#/how-to-use?id=%f0%9f%8c%a4%ef%b8%8f-confluent-cloud-examples).

Azure login: the script runs `az login` (browser), unless `AZ_CLIENT_ID`, `AZ_CLIENT_SECRET` and `AZ_TENANT_ID` are set, in which case it logs in with that service principal.

| Variable | Description |
| --- | --- |
| `AZURE_SUBSCRIPTION_NAME` | Optional. Azure subscription to use when you have several [subscriptions](https://github.com/MicrosoftDocs/azure-docs-cli/blob/main/docs-ref-conceptual/manage-azure-subscriptions-azure-cli.md#change-the-active-subscription) (for Confluent support, use `COPS`) |
| `AZURE_REGION` | Optional. Azure region (default `westeurope`); also used as Confluent Cloud region |

## How to run

```bash
playground run -f fully-managed-azure-data-lake-storage-gen2-sink.sh
```

| Script | Description |
| --- | --- |
| `fully-managed-azure-data-lake-storage-gen2-sink.sh` | Avro records written as Avro files to Azure Data Lake Storage Gen2 |

## What the script does

1. Creates a resource group and a `StorageV2` storage account.
2. Registers an Entra (Azure AD) app `pg<user>` with its service principal and assigns it the `Storage Blob Data Owner` role on the resource group (in CI, pre-created credentials are used).
3. Creates topic `datalake-topic` and the fully managed `AzureDataLakeGen2Sink` connector (Avro in, Avro out, `HOURLY` partitioning, `flush.size` 1000).
4. Produces 1000 Avro records with `playground topic produce`.
5. Lists the files written in the `topics` file system with `az storage fs file list` and shows the connector lag.
6. Deletes the connector and the resource group at the end of the run.
