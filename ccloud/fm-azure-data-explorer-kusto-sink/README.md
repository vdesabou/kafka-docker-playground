# Fully Managed Azure Data Explorer (Kusto) Database Sink connector

## Objective

Quickly test the [Fully Managed Azure Data Explorer (Kusto) Database Sink](https://docs.confluent.io/cloud/current/connectors/cc-azure-data-explorer-kusto-sink.html) connector.

## Prerequisites

See [Confluent Cloud examples](https://kafka-docker-playground.io/#/how-to-use?id=%f0%9f%8c%a4%ef%b8%8f-confluent-cloud-examples).

Azure login: the script runs `az login` (browser), unless `AZ_CLIENT_ID`, `AZ_CLIENT_SECRET` and `AZ_TENANT_ID` are set, in which case it logs in with that service principal.

| Variable | Description |
| --- | --- |
| `AZURE_SUBSCRIPTION_NAME` | Optional. Azure subscription to use when you have several [subscriptions](https://github.com/MicrosoftDocs/azure-docs-cli/blob/main/docs-ref-conceptual/manage-azure-subscriptions-azure-cli.md#change-the-active-subscription) (for Confluent support, use `COPS`) |
| `AZURE_REGION` | Optional. Azure region (default `westeurope`); also used as Confluent Cloud region |

## How to run

```bash
playground run -f fully-managed-azure-data-explorer-kusto-sink.sh
```

| Script | Description |
| --- | --- |
| `fully-managed-azure-data-explorer-kusto-sink.sh` | Avro data sunk to an Azure Data Explorer table using a JSON ingestion mapping |

## What the script does

1. Creates a resource group, an Azure Data Explorer cluster (`Dev(No SLA)_Standard_E2a_v4` SKU, creation takes around 15 minutes) and a database.
2. Creates the table `kusto_topic`, the JSON ingestion mapping `kusto_topic_json_mapping` and an ingestion batching policy of 10 seconds (default is 5 minutes).
3. Creates an Entra app/service principal with `Database Ingestor` and `Database Viewer` roles on the database (in CI, the pre-created service principal `AZURE_LOGS_CLIENT_ID`/`AZURE_LOGS_CLIENT_SECRET` is used instead).
4. Produces 10 Avro records to topic `kusto_topic` with `playground topic produce`.
5. Creates the fully managed `AzureDataExplorerKustoSink` connector (service principal authentication, queued ingestion).
6. Polls the table (up to 10 minutes) until it contains 10 rows, and prints them.
7. Deletes the connector, the resource group and the Entra app at the end of the run.
