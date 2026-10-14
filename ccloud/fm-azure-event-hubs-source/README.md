# Fully Managed Azure Event Hubs Source connector

## Objective

Quickly test the [Fully Managed Azure Event Hubs Source](https://docs.confluent.io/cloud/current/connectors/cc-azure-event-hubs-source.html) connector.

## Prerequisites

See [Confluent Cloud examples](https://kafka-docker-playground.io/#/how-to-use?id=%f0%9f%8c%a4%ef%b8%8f-confluent-cloud-examples).

Azure login: the script runs `az login` (browser), unless `AZ_CLIENT_ID`, `AZ_CLIENT_SECRET` and `AZ_TENANT_ID` are set, in which case it logs in with that service principal.

| Variable | Description |
| --- | --- |
| `AZURE_SUBSCRIPTION_NAME` | Optional. Azure subscription to use when you have several subscriptions (for Confluent support, use `COPS`) |
| `AZURE_REGION` | Optional. Azure region (default `westeurope`); also used as Confluent Cloud region |

## How to run

```bash
playground run -f fully-managed-azure-event-hubs.sh
```

| Script | Description |
| --- | --- |
| `fully-managed-azure-event-hubs.sh` | Events sent to an Event Hub by a Java client are copied to topic `event_hub_topic` |

## What the script does

1. Builds the `simple-send` Java client (based on the Azure [SimpleSend sample](https://github.com/Azure/azure-event-hubs/tree/master/samples/Java/Basic/SimpleSend)).
2. Creates a resource group, an Event Hubs namespace and an Event Hub, and retrieves the `RootManageSharedAccessKey` SAS key and connection string.
3. Starts the local `simple-send` container (`docker-compose.yml`).
4. Creates the fully managed `AzureEventHubsSource` connector, writing to topic `event_hub_topic`.
5. Sends events to the Event Hub with `simple-send`.
6. Verifies the topic with `playground topic consume`.
7. Deletes the connector and the resource group at the end of the run.
