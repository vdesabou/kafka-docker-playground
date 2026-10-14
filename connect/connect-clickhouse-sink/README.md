# ClickHouse Sink connector

## Objective

Quickly test the [ClickHouse Sink](https://clickhouse.com/docs/integrations/kafka/clickhouse-kafka-connect-sink) connector.

## Prerequisites

A [ClickHouse Cloud](https://clickhouse.com/cloud) service is required.

| Variable | Description |
| --- | --- |
| `CLICKHOUSE_CLOUD_USERNAME` | ClickHouse Cloud username |
| `CLICKHOUSE_CLOUD_PASSWORD` | ClickHouse Cloud password |
| `CLICKHOUSE_CLOUD_HOSTNAME` | ClickHouse Cloud hostname (without protocol or port) |

## How to run

```bash
playground run -f clickhouse-sink.sh
```

| Script | Description |
| --- | --- |
| `clickhouse-sink.sh` | Sink to ClickHouse Cloud over HTTPS (port 8443, `ssl=true`) |

## What the script does

1. Drops and recreates the `playground` database in ClickHouse Cloud, then creates the `clickhouse_measures` table (`MergeTree`), using `clickhouse-client` in a `clickhouse/clickhouse-server` container.
2. Checks connectivity to the ClickHouse HTTPS endpoint (port 8443) with a `SELECT 1` query (see [this KB](https://support.confluent.io/hc/en-us/articles/46567287376404-What-can-cause-a-ClickHouse-Sink-connector-on-Confluent-Cloud-to-fail-with-Connection-to-ClickHouse-is-not-active-Error)).
3. Produces one Avro record to topic `clickhouse_measures` with `playground topic produce`.
4. Creates the `clickhouse-sink` connector writing to database `playground`.
5. Verifies the row with `SELECT * FROM clickhouse_measures`.
