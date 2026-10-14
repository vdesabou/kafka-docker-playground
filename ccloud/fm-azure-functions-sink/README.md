# Fully Managed Azure Functions Sink connector

## Objective

Quickly test the [Fully Managed Azure Functions Sink](https://docs.confluent.io/cloud/current/connectors/cc-azure-functions-sink.html) connector.

## Prerequisites

See [Confluent Cloud examples](https://kafka-docker-playground.io/#/how-to-use?id=%f0%9f%8c%a4%ef%b8%8f-confluent-cloud-examples).

Azure login: the script runs `az login` (browser), unless `AZ_CLIENT_ID`, `AZ_CLIENT_SECRET` and `AZ_TENANT_ID` are set, in which case it logs in with that service principal.

| Variable | Description |
| --- | --- |
| `AZURE_SUBSCRIPTION_NAME` | Optional. Azure subscription to use when you have several [subscriptions](https://github.com/MicrosoftDocs/azure-docs-cli/blob/main/docs-ref-conceptual/manage-azure-subscriptions-azure-cli.md#change-the-active-subscription) (for Confluent support, use `COPS`) |
| `AZURE_REGION` | Optional. Azure region (default `westeurope`); also used as Confluent Cloud region |
| `AZURE_FUNCTIONS_CORE_TOOLS_VERSION` | Optional. `azure-functions-core-tools` npm version used to create and publish the function (default `4.13.0`) |

## How to run

```bash
playground run -f fully-managed-azure-functions-sink.sh
```

| Script | Description |
| --- | --- |
| `fully-managed-azure-functions-sink.sh` | Records sent to a Node.js HTTP-triggered Azure Function |

## What the script does

1. Creates a resource group and a storage account.
2. Generates a local Node.js functions project (`LocalFunctionProj`) with an anonymous HTTP trigger `HttpExample`, using the `mcr.microsoft.com/azure-functions/node` image.
3. Creates a consumption-plan function app (with retries on transient ARM lock errors), publishes the project and retrieves the function invoke URL.
4. Creates topic `functions-test` and the fully managed `AzureFunctionsSink` connector (`BYTES` input).
5. Produces 3 records with `playground topic produce`.
6. Verifies that 3 responses land in `success-<connector id>` and checks the `error-<connector id>` topic with `playground topic consume`.
7. Deletes the connector and the resource group at the end of the run.
