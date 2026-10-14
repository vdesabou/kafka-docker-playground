# Fully Managed Azure Log Analytics Sink connector

## Objective

Quickly test the [Fully Managed Azure Log Analytics Sink](https://docs.confluent.io/cloud/current/connectors/cc-azure-log-analytics-sink.html) connector.

## Prerequisites

See [Confluent Cloud examples](https://kafka-docker-playground.io/#/how-to-use?id=%f0%9f%8c%a4%ef%b8%8f-confluent-cloud-examples).

Azure login: the script runs `az login` (browser), unless `AZ_CLIENT_ID`, `AZ_CLIENT_SECRET` and `AZ_TENANT_ID` are set, in which case it logs in with that service principal.

| Variable | Description |
| --- | --- |
| `AZURE_SUBSCRIPTION_NAME` | Optional. Azure subscription to use when you have several [subscriptions](https://github.com/MicrosoftDocs/azure-docs-cli/blob/main/docs-ref-conceptual/manage-azure-subscriptions-azure-cli.md#change-the-active-subscription) (for Confluent support, use `COPS`) |
| `AZURE_REGION` | Optional. Azure region (default `westeurope`); also used as Confluent Cloud region |

## How to run

```bash
playground run -f fully-managed-azure-log-analytics-sink.sh
```

| Script | Description |
| --- | --- |
| `fully-managed-azure-log-analytics-sink.sh` | Avro records sent to a Log Analytics workspace (custom log table `log_analytics_topic_CL`) |

## What the script does

1. Creates a resource group and a Log Analytics workspace, and retrieves its workspace id and primary shared key.
2. Produces 10 Avro records to topic `log_analytics_topic` with `playground topic produce`.
3. Creates the fully managed `AzureLogAnalyticsSink` connector.
4. Shows the connector lag with `playground connector show-lag`.
5. Outside CI only: waits 3 minutes (Log Analytics ingestion latency) and queries `log_analytics_topic_CL | limit 10` with `az monitor log-analytics query`.
6. Deletes the connector and the resource group at the end of the run.
