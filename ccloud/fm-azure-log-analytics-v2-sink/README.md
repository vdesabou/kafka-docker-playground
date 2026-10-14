# Fully Managed Azure Log Analytics V2 Sink connector

## Objective

Quickly test the [Fully Managed Azure Log Analytics V2 Sink](https://docs.confluent.io/cloud/current/connectors/cc-azure-log-analytics-sink-v2.html) connector, which uses the Azure Monitor Logs Ingestion API (Data Collection Rule).

## Prerequisites

See [Confluent Cloud examples](https://kafka-docker-playground.io/#/how-to-use?id=%f0%9f%8c%a4%ef%b8%8f-confluent-cloud-examples).

Azure login: the script runs `az login` (browser), unless `AZ_CLIENT_ID`, `AZ_CLIENT_SECRET` and `AZ_TENANT_ID` are set, in which case it logs in with that service principal. Your account must be allowed to create Entra apps and role assignments.

| Variable | Description |
| --- | --- |
| `AZURE_SUBSCRIPTION_NAME` | Optional. Azure subscription to use when you have several [subscriptions](https://github.com/MicrosoftDocs/azure-docs-cli/blob/main/docs-ref-conceptual/manage-azure-subscriptions-azure-cli.md#change-the-active-subscription) (for Confluent support, use `COPS`) |
| `AZURE_REGION` | Optional. Azure region (default `westeurope`); also used as Confluent Cloud region |

## How to run

```bash
playground run -f fully-managed-azure-log-analytics-v2-sink.sh
```

| Script | Description |
| --- | --- |
| `fully-managed-azure-log-analytics-v2-sink.sh` | Avro records sent to custom table `log_analytics_topic_CL` through a Data Collection Rule |

## What the script does

1. Creates a resource group, a Log Analytics workspace and the custom table `log_analytics_topic_CL`.
2. Creates a `Direct` Data Collection Rule (DCR) targeting the table, and resolves its immutable id and Logs Ingestion endpoint.
3. Creates an Entra app/service principal and assigns it the `Monitoring Metrics Publisher` role on the DCR (in CI, the pre-created `AZURE_LOGS_CLIENT_ID`/`AZURE_LOGS_CLIENT_SECRET`/`AZURE_LOGS_SP_OBJECT_ID` are used).
4. Produces 10 Avro records to topic `log_analytics_topic` with `playground topic produce`.
5. Creates the fully managed `AzureLogAnalyticsSinkV2` connector (`topic.to.table.map`, `table.to.dcr.map`) and shows its lag.
6. Outside CI only: waits 3 minutes (ingestion latency) and queries the table with `az monitor log-analytics query`.
7. Deletes the connector and the resource group at the end of the run. `stop.sh` also deletes the Entra app created locally.
