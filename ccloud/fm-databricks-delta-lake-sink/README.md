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
| `DATABRICKS_SERVER_HOSTNAME` | Databricks SQL warehouse server hostname |
| `DATABRICKS_HTTP_PATH` | Databricks SQL warehouse HTTP path |
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

1. Makes sure the Databricks SQL warehouse is running. Stops with the Databricks error if the warehouse start is refused (for example `denyReason: INACTIVE` when the workspace is deactivated).
2. Empties the S3 staging bucket.
3. Creates topic `pageviews` and produces 100 Avro records with `playground topic produce` (datagen `pageviews` schema).
4. Creates the fully managed `DatabricksDeltaLakeSink` connector (`delta.lake.topic2table.map` `pageviews:pageviews`, `delta.lake.table.auto.create`).
5. Waits for the connector lag to reach 0 with `playground connector show-lag`.
6. Deletes the connector at the end of the run.
