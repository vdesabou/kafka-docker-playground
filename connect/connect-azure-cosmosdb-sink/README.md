# Azure Cosmos DB Sink connector

## Objective

Quickly test the [Azure Cosmos DB Sink](https://github.com/microsoft/kafka-connect-cosmosdb) connector (Microsoft connector, see [sink documentation](https://github.com/microsoft/kafka-connect-cosmosdb/blob/dev/doc/README_Sink.md)).

## Prerequisites

- [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli) (`az`). The script logs in automatically: interactive browser login, or service principal login when `AZ_CLIENT_ID`, `AZ_CLIENT_SECRET` and `AZ_TENANT_ID` are set.
- CP 6.0 or later: the connector does not work with JDK 8, see [microsoft/kafka-connect-cosmosdb#413](https://github.com/microsoft/kafka-connect-cosmosdb/issues/413) (the script exits with code `111` otherwise).

| Variable | Description |
| --- | --- |
| `AZURE_SUBSCRIPTION_NAME` | [Azure subscription](https://learn.microsoft.com/en-us/cli/azure/manage-azure-subscriptions-azure-cli) where the resources are created. Mandatory with a Confluent account (for Confluent support, the subscription is `COPS`) |
| `AZURE_REGION` | Optional, Azure region (default `westeurope`) |

## How to run

```bash
playground run -f azure-cosmosdb-sink.sh
```

| Script | Description |
| --- | --- |
| `azure-cosmosdb-sink.sh` | Cosmos DB sink connector with JSON (schemaless) records |

## What the script does

1. Creates an Azure resource group, a Cosmos DB account, a SQL database (throughput 400) and a container partitioned on `/id` ([setup guide](https://github.com/microsoft/kafka-connect-cosmosdb/blob/dev/doc/CosmosDB_Setup.md)). The endpoint, primary key, database name and topic map (`hotels#<database>`) are written to the `data` file (used through `${file:/data:...}` in the connector config).
2. Produces 3 JSON records to topic `hotels` with `playground topic produce`.
3. Creates the Cosmos DB sink connector (`com.azure.cosmos.kafka.connect.sink.CosmosDBSinkConnector`).
4. Reads the container with a Python client (`azure-cosmos-client` container) and verifies the 3 documents are present.
5. On exit, asks for confirmation and then deletes the Cosmos DB account and the resource group.
