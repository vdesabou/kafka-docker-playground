# Fully Managed ClickHouse Sink connector

## Objective

Quickly test the [Fully Managed ClickHouse Sink](https://docs.confluent.io/cloud/current/connectors/cc-clickhouse-sink-connector/cc-clickhouse-sink.html) connector.

## Prerequisites

See [Confluent Cloud examples](https://kafka-docker-playground.io/#/how-to-use?id=%f0%9f%8c%a4%ef%b8%8f-confluent-cloud-examples).

A [ClickHouse Cloud](https://clickhouse.com/cloud) service is expected to be used.

| Variable | Description |
| --- | --- |
| `CLICKHOUSE_CLOUD_USERNAME` | ClickHouse Cloud username |
| `CLICKHOUSE_CLOUD_PASSWORD` | ClickHouse Cloud password |
| `CLICKHOUSE_CLOUD_HOSTNAME` | ClickHouse Cloud service hostname (native secure port `9440` and HTTPS port `8443` are used) |

## How to run

```bash
export CLICKHOUSE_CLOUD_USERNAME=<username>
export CLICKHOUSE_CLOUD_PASSWORD=<password>
export CLICKHOUSE_CLOUD_HOSTNAME=<hostname>
playground run -f fully-managed-clickhouse-sink.sh
```

| Script | Description |
| --- | --- |
| `fully-managed-clickhouse-sink.sh` | Avro records written to a ClickHouse Cloud MergeTree table |

## What the script does

1. Creates topic `clickhouse_measures`.
2. Recreates the ClickHouse database `playground` and creates the `clickhouse_measures` table (`MergeTree`), using `clickhouse-client` in a container.
3. Produces 1 Avro record with `playground topic produce`.
4. Creates the fully managed `ClickHouseSink` connector (port `8443`, database `playground`).
5. Queries `SELECT * FROM clickhouse_measures` to show the data.
6. Deletes the connector at the end of the run.
