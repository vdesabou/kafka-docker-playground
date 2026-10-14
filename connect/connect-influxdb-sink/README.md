# InfluxDB Sink connector

## Objective

Quickly test the [InfluxDB Sink](https://docs.confluent.io/kafka-connectors/influxdb/current/influx-db-sink-connector/overview.html) connector.

## Prerequisites

With CP 8.x, connector version 1.2.0 or later is required (older `--connector-tag` values exit with code 111).

## How to run

```bash
playground run -f influxdb-sink.sh
```

| Script | Description |
| --- | --- |
| `influxdb-sink.sh` | Basic example: Avro records with a `measurement` field are written to InfluxDB |
| `influxdb-sink-with-tags.sh` | Records with a `tags` map field; `InsertField` and `ReplaceField` SMTs add the `measurement` field and rename `product` to `name` |

## What the script does

1. Starts the environment with an InfluxDB container.
2. Produces Avro records to topic `orders` (or `product` for the tags variant) with `playground topic produce`.
3. Creates the `influxdb-sink` connector pointing to `http://influxdb:8086`.
4. Queries InfluxDB with the `influx` CLI (`select * from orders` / `select * from product`) and checks the data is there.

Example of query result for `influxdb-sink.sh`:

```bash
playground container exec --container influxdb --command "influx -database orders -execute 'select * from orders'"
```
