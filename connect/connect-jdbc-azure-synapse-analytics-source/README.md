# JDBC Azure Synapse Analytics Source connector

## Objective

Quickly test the [JDBC Source](https://docs.confluent.io/kafka-connectors/jdbc/current/source-connector/overview.html) connector with Azure Synapse Analytics (dedicated SQL pool, formerly SQL Data Warehouse).

## Prerequisites

* The `az` CLI must be installed. Login is interactive (browser), or via a Service Principal when `AZ_CLIENT_ID`, `AZ_CLIENT_SECRET` and `AZ_TENANT_ID` are set.
* With CP 8.x, connector version 10.8.0 or later is required (older `--connector-tag` values exit with code 111).

| Variable | Description |
| --- | --- |
| `AZURE_SUBSCRIPTION_NAME` | Azure subscription to use (mandatory with a `confluent.io` account) |
| `AZURE_REGION` | Azure region (default: `westeurope`) |

## How to run

```bash
playground run -f jdbc-azure-synapse-analytics-source.sh
```

## What the script does

1. Creates an Azure resource group, a SQL server (with a firewall rule for your public IP) and a SQL Data Warehouse instance.
2. Writes the JDBC URL and generated password to the `data` file, mounted in the `connect` container and read with the file config provider.
3. Creates and populates table `customers` with `sqlcmd` (the `fabiang/sqlcmd` image).
4. Creates the `jdbc-synapse-source` connector in `timestamp` mode on column `last_update`, with topic prefix `synapse-`.
5. Consumes topic `synapse-customers` with `playground topic consume` (expects 4 records).
6. On exit, deletes the resource group (also done by `stop.sh`).
