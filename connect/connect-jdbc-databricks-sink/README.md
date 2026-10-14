# JDBC Databricks Sink connector

## Objective

Quickly test the [JDBC Sink](https://docs.confluent.io/kafka-connectors/jdbc/current/sink-connector/overview.html) connector with a Databricks SQL warehouse, using the Databricks JDBC driver.

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
playground run -f databricks-jdbc-sink.sh
```

| Script | Description |
| --- | --- |
| `databricks-jdbc-sink.sh` | JDBC sink writing Avro records to a Databricks table |

## What the script does

1. Downloads the Databricks JDBC driver (`DatabricksJDBC42.jar`, 2.7.3) if needed and adds it to the JDBC connector `lib` folder.
2. Starts the SQL warehouse if it is stopped and waits until it is running.
3. Starts the environment with a `databricks-sql-cli-container` helper (Python SQL client built from `../connect-jdbc-databricks-source/databricks`).
4. Pre-creates the `orders` table (otherwise the sink fails with `ConnectException: null (INT32) type doesn't have a mapping to the SQL database column type`).
5. Creates the `databricks-sink` connector (`auto.create=false`, `connection.user=token`) on topic `orders`.
6. Produces 4 Avro records to `orders` with `playground topic produce`.
7. Runs `select count(*) from orders` through the SQL client to verify the rows landed.
