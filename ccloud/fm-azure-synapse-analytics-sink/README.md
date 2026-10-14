# Fully Managed Azure Synapse Analytics Sink connector

## Objective

Quickly test the [Fully Managed Azure Synapse Analytics Sink](https://docs.confluent.io/cloud/current/connectors/cc-azure-synapse-analytics-sink.html) connector.

## Prerequisites

See [Confluent Cloud examples](https://kafka-docker-playground.io/#/how-to-use?id=%f0%9f%8c%a4%ef%b8%8f-confluent-cloud-examples).

Azure login: the script runs `az login` (browser), unless `AZ_CLIENT_ID`, `AZ_CLIENT_SECRET` and `AZ_TENANT_ID` are set, in which case it logs in with that service principal.

| Variable | Description |
| --- | --- |
| `AZURE_SUBSCRIPTION_NAME` | Optional. Azure subscription to use when you have several [subscriptions](https://github.com/MicrosoftDocs/azure-docs-cli/blob/main/docs-ref-conceptual/manage-azure-subscriptions-azure-cli.md#change-the-active-subscription) (for Confluent support, use `COPS`) |
| `AZURE_REGION` | Optional. Azure region (default `westeurope`); also used as Confluent Cloud region |

## How to run

```bash
playground run -f fully-managed-azure-synapse-analytics-sink.sh
```

| Script | Description |
| --- | --- |
| `fully-managed-azure-synapse-analytics-sink.sh` | Avro records written to a dedicated SQL pool (SQL Data Warehouse), table auto-created |

## What the script does

1. Creates a resource group and an Azure SQL server (admin `myadmin`, random password printed outside CI), with a firewall rule for your public IP (plus Azure services in CI).
2. Creates a SQL Data Warehouse (dedicated SQL pool).
3. Creates topic `products` and the fully managed `AzureSqlDwSink` connector (`auto.create`, `auto.evolve`, `table.name.format` `kafka_${topic}`).
4. Produces 3 Avro records with `playground topic produce`, one of them with name `notebooks`.
5. Queries `kafka_products` with `sqlcmd` and checks that `notebooks` is present.
6. Deletes the connector and the resource group at the end of the run.
