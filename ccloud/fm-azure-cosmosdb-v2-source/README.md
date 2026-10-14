# Fully Managed Azure Cosmos DB V2 Source connector

## Objective

Quickly test the [Fully Managed Azure Cosmos DB V2 Source](https://docs.confluent.io/cloud/current/connectors/cc-azure-cosmos-source-v2.html) connector.

## Prerequisites

See [Confluent Cloud examples](https://kafka-docker-playground.io/#/how-to-use?id=%f0%9f%8c%a4%ef%b8%8f-confluent-cloud-examples).

Azure: the [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli) logs in with `az login` (browser), or with a service principal when `AZ_CLIENT_ID`, `AZ_CLIENT_SECRET` and `AZ_TENANT_ID` are set.

| Variable | Description |
| --- | --- |
| `AZURE_SUBSCRIPTION_NAME` | Optional. If you have multiple [Azure subscriptions](https://github.com/MicrosoftDocs/azure-docs-cli/blob/main/docs-ref-conceptual/manage-azure-subscriptions-azure-cli.md#change-the-active-subscription), subscription in which the Azure resource group is created (for Confluent support, subscription is `COPS`) |
| `AZURE_REGION` | Optional. Azure region (default `westeurope`). The Confluent Cloud cluster is expected on Azure in this region |

## How to run

```bash
playground run -f fully-managed-azure-cosmosdb-v2-source.sh
```

| Script | Description |
| --- | --- |
| `fully-managed-azure-cosmosdb-v2-source.sh` | Azure Cosmos DB V2 Source connector with Avro output |

## What the script does

1. Bootstraps the Confluent Cloud environment and recreates topic `apparelsv2`.
2. Recreates an Azure resource group, then creates a Cosmos DB account, a SQL database (throughput 400) and a container with partition key `/id` (all named `pg<USER>fmck<TAG_BASE>`, truncated to 24 characters).
3. Starts a local `azure-cosmos-client` container (Python `azure-cosmos` SDK) used to insert documents.
4. Creates the fully managed connector `CosmosDbSourceV2_<USER>` (`azure.cosmos.source.containers.topicMap=apparelsv2#<container>`) and waits for it to be running.
5. Inserts documents twice with `insert-data.py`, 30 seconds apart.
6. Verifies that topic `apparelsv2` contains at least 2 records with `playground topic consume`.
7. Asks for confirmation before deleting the connector, then (on exit) before deleting the Cosmos DB account and the resource group.
