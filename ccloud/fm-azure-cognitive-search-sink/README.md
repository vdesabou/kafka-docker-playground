# Fully Managed Azure Cognitive Search Sink connector

## Objective

Quickly test the [Fully Managed Azure Cognitive Search Sink](https://docs.confluent.io/cloud/current/connectors/cc-azure-cognitive-search-sink.html) connector.

## Prerequisites

See [Confluent Cloud examples](https://kafka-docker-playground.io/#/how-to-use?id=%f0%9f%8c%a4%ef%b8%8f-confluent-cloud-examples).

Azure: the [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli) logs in with `az login` (browser), or with a service principal when `AZ_CLIENT_ID`, `AZ_CLIENT_SECRET` and `AZ_TENANT_ID` are set.

| Variable | Description |
| --- | --- |
| `AZURE_SUBSCRIPTION_NAME` | Optional. If you have multiple [Azure subscriptions](https://github.com/MicrosoftDocs/azure-docs-cli/blob/main/docs-ref-conceptual/manage-azure-subscriptions-azure-cli.md#change-the-active-subscription), subscription in which the Azure resource group is created (for Confluent support, subscription is `COPS`) |
| `AZURE_REGION` | Optional. Azure region (default `westeurope`). The Confluent Cloud cluster is expected on Azure in this region |

When not running in CI, the script creates an Azure AD service principal `pg<USER>` with the `Contributor` role on the resource group (see [service principal](https://docs.confluent.io/cloud/current/connectors/cc-azure-cognitive-search-sink.html#az-service-principal)), so your Azure user must be allowed to create service principals. In CI, `AZURE_COGNITIVE_APP_ID` and `AZURE_COGNITIVE_APP_PASSWORD` are used instead.

## How to run

```bash
playground run -f fully-managed-azure-cognitive-search-sink.sh
```

| Script | Description |
| --- | --- |
| `fully-managed-azure-cognitive-search-sink.sh` | Azure Cognitive Search Sink connector writing to index `hotels-sample-index` |

## What the script does

1. Recreates an Azure resource group and creates an Azure Search service (Basic SKU), both named `pg<USER>fms<TAG_BASE>` (truncated to 24 characters).
2. Creates the service principal and the search index `hotels-sample-index` through the Azure Search REST API.
3. Bootstraps the Confluent Cloud environment, recreates topic `hotels-sample` and produces 3 Avro records (`Marriott`, `HolidayInn`, `Motel8`).
4. Creates the fully managed connector `AzureCognitiveSearchSink_<USER>` (`index.name=${topic}-index`) and waits for it to be running.
5. Searches the index and verifies that the 3 documents are present.
6. Asks for confirmation before deleting the connector, then (on exit) before deleting the resource group.
