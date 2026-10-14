# Azure Service Bus Source connector

## Objective

Quickly test the [Azure Service Bus Source](https://docs.confluent.io/kafka-connectors/azure-servicebus/current/overview.html) connector.

## Prerequisites

- [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli) (`az`). The script logs in automatically: interactive browser login, or service principal login when `AZ_CLIENT_ID`, `AZ_CLIENT_SECRET` and `AZ_TENANT_ID` are set.
- With CP 8.0+, connector version 1.2.16 or later is required when `--connector-tag` is set (the script exits with code `111` otherwise).

| Variable | Description |
| --- | --- |
| `AZURE_SUBSCRIPTION_NAME` | [Azure subscription](https://learn.microsoft.com/en-us/cli/azure/manage-azure-subscriptions-azure-cli) where the resources are created. Mandatory with a Confluent account (for Confluent support, the subscription is `COPS`) |
| `AZURE_REGION` | Optional, Azure region (default `westeurope`) |

## How to run

```bash
playground run -f azure-service-bus-source.sh
```

| Script | Description |
| --- | --- |
| `azure-service-bus-source.sh` | Service Bus source connector reading a queue with SAS key authentication |

## What the script does

1. Builds the `QueuesGettingStarted` Java client, based on the [Azure Service Bus quickstart](https://learn.microsoft.com/en-us/azure/service-bus-messaging/service-bus-quickstart-cli).
2. Creates an Azure resource group, a Service Bus namespace and a queue, and writes the `RootManageSharedAccessKey` SAS key, namespace and queue name to the `data` file (used through `${file:/data:...}` in the connector config).
3. Creates the Service Bus source connector (`io.confluent.connect.azure.servicebus.ServiceBusSourceConnector`) writing to topic `servicebus-topic`.
4. Sends messages to the queue with the `QueuesGettingStarted` client.
5. Verifies the messages are received in `servicebus-topic` with `playground topic consume`, then asserts the queue is empty, i.e. messages were completed through the `commitRecord` API.
6. On exit, asks for confirmation and then deletes the resource group.
