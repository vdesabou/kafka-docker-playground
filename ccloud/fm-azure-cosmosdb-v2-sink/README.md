# Fully Managed Azure Cosmos DB V2 Sink connector

## Objective

Quickly test the [Fully Managed Azure Cosmos DB V2 Sink](https://docs.confluent.io/cloud/current/connectors/cc-azure-cosmos-sink-v2.html) connector.

## Prerequisites

See [Confluent Cloud examples](https://kafka-docker-playground.io/#/how-to-use?id=%f0%9f%8c%a4%ef%b8%8f-confluent-cloud-examples).

Azure: the [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli) logs in with `az login` (browser), or with a service principal when `AZ_CLIENT_ID`, `AZ_CLIENT_SECRET` and `AZ_TENANT_ID` are set.

| Variable | Description |
| --- | --- |
| `AZURE_SUBSCRIPTION_NAME` | Optional. If you have multiple [Azure subscriptions](https://github.com/MicrosoftDocs/azure-docs-cli/blob/main/docs-ref-conceptual/manage-azure-subscriptions-azure-cli.md#change-the-active-subscription), subscription in which the Azure resource group is created (for Confluent support, subscription is `COPS`) |
| `AZURE_REGION` | Optional. Azure region (default `westeurope`). The Confluent Cloud cluster is expected on Azure in this region |

## How to run

```bash
playground run -f fully-managed-azure-cosmosdb-v2-sink.sh
```

| Script | Description |
| --- | --- |
| `fully-managed-azure-cosmosdb-v2-sink.sh` | Azure Cosmos DB V2 Sink connector with JSON input and `FullKeyStrategy` id strategy |

## What the script does

1. Bootstraps the Confluent Cloud environment and recreates topic `hotelsv2`.
2. Recreates an Azure resource group, then creates a Cosmos DB account, a SQL database (throughput 400) and a container with partition key `/id` (all named `pg<USER>fmcs<TAG_BASE>`, truncated to 24 characters).
3. Starts a local `azure-cosmos-client` container (Python `azure-cosmos` SDK) used for verification.
4. Creates the fully managed connector `CosmosDbSinkV2_<USER>` (`azure.cosmos.sink.containers.topicMap=hotelsv2#<container>`) and waits for it to be running.
5. Produces 3 JSON records to `hotelsv2` with `playground topic produce`.
6. Reads the container with `get-data.py` and verifies that it contains `Motel8`.
7. Asks for confirmation before deleting the connector, then (on exit) before deleting the Cosmos DB account and the resource group.
