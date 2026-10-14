# Azure Data Explorer (Kusto) Sink connector

## Objective

Quickly test the [Azure Data Explorer (Kusto) Sink](https://github.com/Azure/kafka-sink-azure-kusto) connector.

## Prerequisites

- [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli) (`az`). The script logs in automatically: interactive browser login, or service principal login when `AZ_CLIENT_ID`, `AZ_CLIENT_SECRET` and `AZ_TENANT_ID` are set. Your account must be allowed to create Entra apps (outside CI).
- CP 7.7.0 or later: the connector requires JDK 17 (the script exits with code `111` otherwise).

| Variable | Description |
| --- | --- |
| `AZURE_SUBSCRIPTION_NAME` | [Azure subscription](https://learn.microsoft.com/en-us/cli/azure/manage-azure-subscriptions-azure-cli) where the resources are created. Mandatory with a Confluent account (for Confluent support, the subscription is `COPS`) |
| `AZURE_REGION` | Optional, Azure region (default `westeurope`) |

The script creates everything else that is needed:

- an Azure Data Explorer cluster (`Dev(No SLA)_Standard_E2a_v4` SKU, creation takes around 15 minutes) and a database `playground_db`
- a table `kusto_topic`, a JSON ingestion mapping `kusto_topic_json_mapping` and an ingestion batching policy of 10 seconds (default is 5 minutes)
- an Entra app/service principal with `Database Ingestor` and `Database Viewer` roles on the database (in CI, the pre-created service principal `AZURE_LOGS_CLIENT_ID` / `AZURE_LOGS_CLIENT_SECRET` is used instead)

## How to run

```bash
playground run -f azure-data-explorer-kusto-sink.sh
```

| Script | Description |
| --- | --- |
| `azure-data-explorer-kusto-sink.sh` | Kusto sink connector with queued ingestion and JSON mapping |

## What the script does

1. Creates the resource group, the Entra app (outside CI), the Azure Data Explorer cluster and database, then the table, ingestion mapping, batching policy and role assignments (KQL management commands sent to the cluster REST API).
2. Produces 10 Avro records to topic `kusto_topic` with `playground topic produce`.
3. Creates the Kusto sink connector (`com.microsoft.azure.kusto.kafka.connect.sink.KustoSinkConnector`) with application (service principal) authentication, queued ingestion and `format=json`.
4. Waits for the connector to consume the records (`playground connector show-lag`), then polls the table until it contains the 10 rows (queued ingestion can take a few minutes).
5. On exit, asks for confirmation and then deletes the resource group and the Entra app.
