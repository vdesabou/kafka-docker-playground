# Fully Managed Azure Service Bus Source connector

## Objective

Quickly test the [Fully Managed Azure Service Bus Source](https://docs.confluent.io/cloud/current/connectors/cc-azure-service-bus-source.html) connector.

## Prerequisites

See [Confluent Cloud examples](https://kafka-docker-playground.io/#/how-to-use?id=%f0%9f%8c%a4%ef%b8%8f-confluent-cloud-examples).

Azure login: the script runs `az login` (browser), unless `AZ_CLIENT_ID`, `AZ_CLIENT_SECRET` and `AZ_TENANT_ID` are set, in which case it logs in with that service principal.

| Variable | Description |
| --- | --- |
| `AZURE_SUBSCRIPTION_NAME` | Optional. Azure subscription to use when you have several subscriptions (for Confluent support, use `COPS`) |
| `AZURE_REGION` | Optional. Azure region (default `westeurope`); also used as Confluent Cloud region |

## How to run

```bash
playground run -f fully-managed-azure-service-bus-source.sh
```

| Script | Description |
| --- | --- |
| `fully-managed-azure-service-bus-source.sh` | Messages sent to a Service Bus queue are copied to topic `servicebus-topic` (Avro) |

## What the script does

1. Builds the `QueuesGettingStarted` Java client (based on the [Service Bus quickstart](https://docs.microsoft.com/en-us/azure/service-bus-messaging/service-bus-quickstart-cli#send-and-receive-messages)) and starts it locally (`docker-compose.yml`).
2. Creates topic `servicebus-topic`, a resource group, a Service Bus namespace and queue, and retrieves the `RootManageSharedAccessKey` SAS key.
3. Creates the fully managed `AzureServiceBusSource` connector (`output.data.format` `AVRO`).
4. Sends messages to the queue with `QueuesGettingStarted`.
5. Verifies that at least 5 records are in `servicebus-topic` with `playground topic consume`.
6. Asserts that the queue is empty afterwards (messages are completed by the connector).
7. Asks before deleting the connector. `stop.sh` deletes the resource group.
