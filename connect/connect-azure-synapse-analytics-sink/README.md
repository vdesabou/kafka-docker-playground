# Azure Synapse Analytics Sink connector

## Objective

Quickly test the [Azure Synapse Analytics Sink](https://docs.confluent.io/kafka-connectors/azure-sql-dw/current/overview.html) connector.

## Prerequisites

- [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli) (`az`). The script logs in automatically: interactive browser login, or service principal login when `AZ_CLIENT_ID`, `AZ_CLIENT_SECRET` and `AZ_TENANT_ID` are set.
- With CP 8.0+, connector version 1.0.10 or later is required when `--connector-tag` is set (the script exits with code `111` otherwise).

| Variable | Description |
| --- | --- |
| `AZURE_SUBSCRIPTION_NAME` | [Azure subscription](https://learn.microsoft.com/en-us/cli/azure/manage-azure-subscriptions-azure-cli) where the resources are created. Mandatory with a Confluent account (for Confluent support, the subscription is `COPS`) |
| `AZURE_REGION` | Optional, Azure region (default `westeurope`) |

## How to run

```bash
playground run -f azure-synapse-analytics-sink.sh
```

| Script | Description |
| --- | --- |
| `azure-synapse-analytics-sink.sh` | Azure Synapse Analytics (SQL Data Warehouse) sink connector with `auto.create` |

## What the script does

1. Creates an Azure resource group and a SQL server with a random admin password, adds a firewall rule for your public IP (from `https://ipinfo.io/ip`), then creates a SQL Data Warehouse. The JDBC URL, password and database name are written to the `data` file (used through `${file:/data:...}` in the connector config).
2. Produces 3 Avro records to topic `products` with `playground topic produce`.
3. Creates the Azure Synapse Analytics sink connector (`io.confluent.connect.azuresqldw.AzureSqlDwSinkConnector`) with `auto.create=true` and `table.name.format=kafka_${topic}`.
4. Queries table `kafka_products` with `sqlcmd` (in a `fabiang/sqlcmd` container) and verifies the data is there.
5. On exit, asks for confirmation and then deletes the resource group.
