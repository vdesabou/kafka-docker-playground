# JDBC Databricks Source connector

## Objective

Quickly test the [JDBC Source](https://docs.confluent.io/kafka-connectors/jdbc/current/source-connector/overview.html) connector with a Databricks SQL warehouse, using the Databricks JDBC driver.

## Prerequisites

### Register a trial account

1. Go to [Databricks](https://www.databricks.com/try-databricks) and register for a trial.
2. Once the trial instance is ready, log in to the portal and go to **SQL Warehouses** > **Connection details** to collect the server hostname and HTTP path.
3. Click your account in the top right corner, select **Settings** > **Developer** and generate a personal access token.

| Variable | Description |
| --- | --- |
| `DATABRICKS_HOST` | SQL warehouse server hostname (e.g. `dbc-xxxxxxxx-xxxx.cloud.databricks.com`) |
| `DATABRICKS_TOKEN` | Personal access token |
| `DATABRICKS_HTTP_PATH` | SQL warehouse HTTP path (e.g. `/sql/1.0/warehouses/<id>`) |

With CP 8.x, the JDBC connector version must be 10.8.0 or later (the script exits with code 111 otherwise).

## How to run

```bash
export DATABRICKS_HOST="<server hostname>"
export DATABRICKS_TOKEN="<personal access token>"
export DATABRICKS_HTTP_PATH="<http path>"
playground run -f databricks-jdbc-source.sh
```

| Script | Description |
| --- | --- |
| `databricks-jdbc-source.sh` | JDBC source in `incrementing` mode on a Databricks table |

## What the script does

1. Downloads the Databricks JDBC driver (`DatabricksJDBC42.jar`, 2.7.3) if needed and adds it to the JDBC connector `lib` folder.
2. Starts the SQL warehouse if it is stopped and waits until it is running.
3. Starts the environment with a `databricks-sql-cli-container` helper (Python SQL client built from `databricks/`).
4. Creates the `CUSTOMERS` table (identity `id` column) and inserts 21 rows through the SQL client.
5. Creates the `jdbc-databricks-source` connector (`mode=incrementing` on `id`, `topic.prefix=databricks-`).
6. Verifies that records land in topic `databricks-customers` with `playground topic consume`.
