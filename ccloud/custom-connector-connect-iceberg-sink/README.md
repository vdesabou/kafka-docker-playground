# Custom Connector Apache Iceberg Sink Connector connector

## Objective

Quickly test the [Apache Iceberg Sink Connector](https://www.confluent.io/hub/iceberg/iceberg-kafka-connect) deployed as a Confluent Cloud [Custom Connector](https://docs.confluent.io/cloud/current/connectors/bring-your-connector/overview.html).

The Iceberg REST catalog and the MinIO object store run locally (based on [docker-spark-iceberg](https://github.com/tabular-io/docker-spark-iceberg)) and are exposed to the custom connector through ngrok TCP tunnels.

## Prerequisites

See [Confluent Cloud examples](https://kafka-docker-playground.io/#/how-to-use?id=%f0%9f%8c%a4%ef%b8%8f-confluent-cloud-examples).

| Variable | Description |
| --- | --- |
| `NGROK_AUTH_TOKEN` | ngrok auth token ([sign up](https://dashboard.ngrok.com/signup), token available [here](https://dashboard.ngrok.com/get-started/your-authtoken)) |
| `ICEBERG_VERSION` | Optional. Version of `iceberg/iceberg-kafka-connect` uploaded as custom plugin (default `1.9.2`), downloaded from Confluent Hub if not present |

> [!WARNING]
> The local MinIO (port 9000) and Iceberg REST catalog (port 8181) are exposed on the internet through ngrok. The script asks for confirmation before continuing.

## How to run

```bash
export NGROK_AUTH_TOKEN="<your ngrok token>"
playground run -f custom-iceberg-sink.sh
```

| Script | Description |
| --- | --- |
| `custom-iceberg-sink.sh` | Apache Iceberg Sink connector deployed as a Confluent Cloud custom connector, with a local REST catalog and MinIO |

## What the script does

1. Downloads `iceberg-iceberg-kafka-connect-<ICEBERG_VERSION>.zip` if needed and bootstraps the Confluent Cloud environment.
2. Deletes any previous custom plugin `pg_<USER>_apache_iceberg_sink`, then creates it again and uploads the zip as a plugin version (`iceberg.kafka.sasl.jaas.config` declared as sensitive).
3. Recreates topics `payments` and `control-iceberg`, then starts MinIO, the Iceberg REST catalog, Spark/Jupyter and ngrok with `docker compose`.
4. Produces the records of `data/transactions.json` to `payments` with `playground topic produce`.
5. Creates the custom connector `ICEBERG_SINK_CUSTOM_<USER>` writing to table `orders.payments` (auto-created) through the ngrok endpoints.
6. Waits for the consumer lag to be 0 with `playground connector show-lag`, then queries `orders.payments` with `spark-sql` (skipped in CI).
7. On exit, asks for confirmation before deleting the connector, the plugin version and the custom plugin.

You can also open Jupyter Lab at [http://localhost:8888/lab/tree/notebooks](http://localhost:8888/lab/tree/notebooks) and use the sample notebook `notebooks/iceberg.ipynb` to query the table.
