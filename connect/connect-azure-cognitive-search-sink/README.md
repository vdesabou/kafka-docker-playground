# Azure Cognitive Search Sink connector

## Objective

Quickly test the [Azure Cognitive Search Sink](https://docs.confluent.io/kafka-connectors/azure-search/current/overview.html) connector.

## Prerequisites

- [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli) (`az`). The script logs in automatically: interactive browser login, or service principal login when `AZ_CLIENT_ID`, `AZ_CLIENT_SECRET` and `AZ_TENANT_ID` are set.
- With CP 8.0+, connector version 1.1.8 or later is required when `--connector-tag` is set (the scripts exit with code `111` otherwise).

| Variable | Description |
| --- | --- |
| `AZURE_SUBSCRIPTION_NAME` | [Azure subscription](https://learn.microsoft.com/en-us/cli/azure/manage-azure-subscriptions-azure-cli) where the resources are created. Mandatory with a Confluent account (for Confluent support, the subscription is `COPS`) |
| `AZURE_REGION` | Optional, Azure region (default `westeurope`) |

## How to run

```bash
playground run -f azure-cognitive-search-sink.sh
```

| Script | Description |
| --- | --- |
| `azure-cognitive-search-sink.sh` | Basic example |
| `azure-cognitive-search-sink-proxy.sh` | Same, going through an nginx forward proxy (`proxy.host=nginx-proxy`, `proxy.port=8888`) |

## What the script does

1. Creates an Azure resource group and a `Basic` Azure Search service, then creates the index `hotels-sample-index` with the Search REST API. The service name and admin key are written to the `data` file (used through `${file:/data:...}` in the connector config).
2. Produces 3 Avro records with string keys (`marriottId`, `holidayinnId`, `motel8Id`) to topic `hotels-sample` with `playground topic produce`.
3. Creates the Azure Search sink connector (`io.confluent.connect.azure.search.AzureSearchSinkConnector`) with `index.name=${topic}-index`, reporting to `test-result` / `test-error`.
4. Searches the index with the Search REST API and verifies the 3 documents are present.
5. On exit, asks for confirmation and then deletes the resource group.
