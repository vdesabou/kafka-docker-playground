# InfluxDB Source connector

## Objective

Quickly test the [InfluxDB Source](https://docs.confluent.io/kafka-connectors/influxdb/current/influx-db-source-connector/overview.html) connector.

## Prerequisites

With CP 8.x, connector version 1.2.0 or later is required (older `--connector-tag` values exit with code 111).

## How to run

```bash
playground run -f influxdb-source.sh
```

## What the script does

1. Starts the environment with an InfluxDB container.
2. Creates database `testdb` and inserts a point into measurement `coin` (`INSERT coin,id=1 value=100`) with the `influx` CLI.
3. Creates the `influxdb-source` connector in `timestamp` mode with topic prefix `influx_` and JSON values without schema.
4. Consumes topic `influx_testdb` with `playground topic consume`.

Example of record:

```json
{
  "measurement": "coin",
  "tags": {
    "id": "1"
  },
  "time": "2020-01-10T13:48:37.0833919Z",
  "value": 100.0
}
```
