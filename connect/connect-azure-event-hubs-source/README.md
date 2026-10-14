# Azure Event Hubs Source connector

## Objective

Quickly test the [Azure Event Hubs Source](https://docs.confluent.io/kafka-connectors/azure-event-hubs/current/overview.html) connector.

## Prerequisites

- [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli) (`az`). The script logs in automatically: interactive browser login, or service principal login when `AZ_CLIENT_ID`, `AZ_CLIENT_SECRET` and `AZ_TENANT_ID` are set.
- With CP 8.0+, connector version 2.0.11 or later is required when `--connector-tag` is set (the script exits with code `111` otherwise).

| Variable | Description |
| --- | --- |
| `AZURE_SUBSCRIPTION_NAME` | [Azure subscription](https://learn.microsoft.com/en-us/cli/azure/manage-azure-subscriptions-azure-cli) where the resources are created. Mandatory with a Confluent account (for Confluent support, the subscription is `COPS`) |
| `AZURE_REGION` | Optional, Azure region (default `westeurope`) |

## How to run

```bash
playground run -f azure-event-hubs-source.sh
```

| Script | Description |
| --- | --- |
| `azure-event-hubs-source.sh` | Event Hubs source connector with SAS key authentication |

## What the script does

1. Builds the `simple-send` Java client, based on the [Azure SimpleSend sample](https://github.com/Azure/azure-event-hubs/tree/master/samples/Java/Basic/SimpleSend).
2. Creates an Azure resource group, an Event Hubs namespace and an event hub, and writes the `RootManageSharedAccessKey` SAS key, namespace and hub name to the `data` file (used through `${file:/data:...}` in the connector config).
3. Creates the Event Hubs source connector (`io.confluent.connect.azure.eventhubs.EventHubsSourceConnector`) writing to topic `event-hub-topic`.
4. Sends events to the event hub with the `simple-send` client.
5. Verifies the events are received in `event-hub-topic` with `playground topic consume`.
6. On exit, asks for confirmation and then deletes the resource group.
