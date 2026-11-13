# Fully Managed Databricks Delta Lake Sink connector

## Objective

Quickly test the [Fully Managed Databricks Delta Lake Sink](https://docs.confluent.io/cloud/current/connectors/cc-databricks-delta-lake-sink/cc-databricks-delta-lake-sink.html) connector.

## Prerequisites

See [Confluent Cloud examples](https://kafka-docker-playground.io/#/how-to-use?id=%f0%9f%8c%a4%ef%b8%8f-confluent-cloud-examples).

### Databricks setup

Follow all steps from [here](https://docs.confluent.io/kafka-connectors/databricks-delta-lake-sink/current/databricks-aws-setup.html#set-up-databricks-delta-lake-aws).

The `aws` CLI must be configured with access to the staging bucket (the script empties it before the run).

| Variable | Description |
| --- | --- |
| `DATABRICKS_AWS_BUCKET_NAME` | S3 staging bucket name |
| `DATABRICKS_AWS_BUCKET_REGION` | S3 staging bucket region |
| `DATABRICKS_AWS_STAGING_S3_ACCESS_KEY_ID` | AWS access key id used by the connector for the staging bucket |
| `DATABRICKS_AWS_STAGING_S3_SECRET_ACCESS_KEY` | AWS secret access key used by the connector for the staging bucket |
| `DATABRICKS_SERVER_HOSTNAME` | Databricks server hostname |
| `DATABRICKS_HTTP_PATH` | HTTP path of a Databricks SQL warehouse (`/sql/1.0/warehouses/...`) or all-purpose cluster (`sql/protocolv1/o/...`) |
| `DATABRICKS_TOKEN` | Databricks personal access token |

## How to run

```bash
export DATABRICKS_AWS_BUCKET_NAME=<bucket>
export DATABRICKS_AWS_BUCKET_REGION=<region>
export DATABRICKS_AWS_STAGING_S3_ACCESS_KEY_ID=<access key id>
export DATABRICKS_AWS_STAGING_S3_SECRET_ACCESS_KEY=<secret access key>
export DATABRICKS_SERVER_HOSTNAME=<server hostname>
export DATABRICKS_HTTP_PATH=<http path>
export DATABRICKS_TOKEN=<token>
playground run -f fully-managed-databricks-delta-lake-sink.sh
```

| Script | Description |
| --- | --- |
| `fully-managed-databricks-delta-lake-sink.sh` | Avro `pageviews` records written to an auto-created Delta Lake table through an S3 staging bucket |

## What the script does

1. Makes sure the Databricks SQL warehouse is running (skipped when the http path is an all-purpose cluster). Stops with the Databricks error if the warehouse start is refused (for example `denyReason: INACTIVE` when the workspace is deactivated).
2. Empties the S3 staging bucket.
3. Creates topic `pageviews_fm_<user>_<run>_<cp version>` and produces 100 Avro records with `playground topic produce` (datagen `pageviews` schema). `<user>` is `$USER` and `<run>` is `$GITHUB_RUN_NUMBER` (the epoch when not set), in lower case, other characters than letters and digits replaced by `_`. One topic per run because the connector skips, and never auto-creates the table for, records whose offset is not above a file left under `topics/<topic>/` in the staging bucket by an earlier run (the bucket is not always emptied, for example when the caller is not allowed to).
4. Creates the fully managed `DatabricksDeltaLakeSink` connector, mapping the topic to a table of the same name (`delta.lake.topic2table.map`), created by the connector (`delta.lake.table.auto.create`). The table includes the user because the Databricks workspace is shared: writing into a table created by someone else fails with `[INSUFFICIENT_PERMISSIONS] Insufficient privileges: Principal '...' does not have SELECT on Table '...'`. The table is new on each run, so it only holds the records of this run.
5. Waits for the connector lag to reach 0 with `playground connector show-lag`.
6. Checks that the 100 records are in the table with `SELECT COUNT(*)` (`databricks_wait_for_table_rows`: SQL Statement Execution API when the http path is a SQL warehouse, Command Execution API when it is an all-purpose cluster), and fails otherwise. The lag alone proves nothing: the staging S3 writer commits the offsets before the `COPY INTO`, so the lag reaches 0 even when the `COPY INTO` fails and the task is `FAILED`. When the `COPY INTO` fails, the connector log only shows `java.sql.SQLException (SQLState=HY000, vendorCode=500051)`: the real error is in the Query History of the SQL warehouse, for example `PERMISSION_DENIED: Principal '...' does not have READ FILES on External Location '...'` (the principal of the token needs `READ FILES` on the external location of the staging bucket).
7. Deletes the connector, then drops the table, removes the staged files of the topic (with the staging S3 keys) and deletes the topic, as they are only for this run. A failure of these cleanups only logs a warning.
