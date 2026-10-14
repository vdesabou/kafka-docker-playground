# Apache Iceberg Sink connector

## Objective

Quickly test the [Apache Iceberg Sink](https://iceberg.apache.org/docs/latest/kafka-connect/) connector (`org.apache.iceberg.connect.IcebergSinkConnector`, originally [tabular-io/iceberg-kafka-connect](https://github.com/tabular-io/iceberg-kafka-connect)).

The environment uses a local Iceberg stack: MinIO as object storage (bucket `warehouse`), the `tabulario/iceberg-rest` REST catalog and a `spark-iceberg` container with Jupyter (based on [docker-spark-iceberg](https://github.com/tabular-io/docker-spark-iceberg)).

## How to run

```bash
playground run -f iceberg-sink.sh
```

| Script | Description |
| --- | --- |
| `iceberg-sink.sh` | Sink JSON records from topic `payments` to Iceberg table `orders.payments` using the REST catalog |

## What the script does

1. Starts the environment with MinIO, the Iceberg REST catalog and Spark/Jupyter; the `aws-cli` container creates the `s3://warehouse` bucket.
2. Creates the control topic `control-iceberg` and produces the content of `data/transactions.json` to topic `payments`.
3. Creates the `iceberg-sink` connector (REST catalog `http://rest:8181`, auto-created table `orders.payments`, commit interval 1s).
4. Waits for the consumer lag to reach 0 with `playground connector show-lag`.
5. Outside GitHub Actions: queries `SELECT * FROM orders.payments LIMIT 10` with `spark-sql` in the `spark-iceberg` container.

## Query the table

Open Jupyter Lab at [http://localhost:8888/lab/tree/notebooks](http://localhost:8888/lab/tree/notebooks) and use the sample notebook `notebooks/iceberg.ipynb`. The MinIO console is available at [http://localhost:9001](http://localhost:9001) (`minioadmin` / `minioadmin`).
