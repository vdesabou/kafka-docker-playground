# Azure Functions Sink connector

## Objective

Quickly test the [Azure Functions Sink](https://docs.confluent.io/kafka-connectors/azure-functions/current/overview.html) connector.

## Prerequisites

- [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli) (`az`). The script logs in automatically: interactive browser login, or service principal login when `AZ_CLIENT_ID`, `AZ_CLIENT_SECRET` and `AZ_TENANT_ID` are set.
- With CP 8.0+, connector version 2.0.7 or later is required when `--connector-tag` is set (the script exits with code `111` otherwise).

| Variable | Description |
| --- | --- |
| `AZURE_SUBSCRIPTION_NAME` | [Azure subscription](https://learn.microsoft.com/en-us/cli/azure/manage-azure-subscriptions-azure-cli) where the resources are created. Mandatory with a Confluent account (for Confluent support, the subscription is `COPS`) |
| `AZURE_REGION` | Optional, Azure region (default `westeurope`) |
| `AZURE_FUNCTIONS_CORE_TOOLS_VERSION` | Optional, version of `azure-functions-core-tools` used to create the function project (default `4.13.0`: `4.14.0` fails with npm `E401`) |

## How to run

```bash
playground run -f azure-functions-sink.sh
```

| Script | Description |
| --- | --- |
| `azure-functions-sink.sh` | Azure Functions sink connector calling an anonymous HTTP-triggered JavaScript function |

## What the script does

1. Creates an Azure resource group and a storage account.
2. Creates a local JavaScript functions project (`LocalFunctionProj`) with an anonymous `HTTP trigger` function, using the `mcr.microsoft.com/azure-functions/node:4-node22` image ([Microsoft quickstart](https://learn.microsoft.com/en-us/azure/azure-functions/create-first-function-cli-node)).
3. Creates the function app (consumption plan, Node 22, retried on transient ARM lock errors), publishes the project and retrieves the function invoke URL.
4. Produces 3 string records (key `key1`) to topic `functions-test` with `playground topic produce`.
5. Creates the Azure Functions sink connector (`io.confluent.connect.azure.functions.AzureFunctionsSinkConnector`), reporting results to `test-result` and errors to `test-error`.
6. Verifies 3 results are received in `test-result` with `playground topic consume`.
7. On exit, asks for confirmation and then deletes the resource group.
