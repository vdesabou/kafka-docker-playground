# Flink SQL with Kafka

## Objective

Quickly test [Flink SQL](https://nightlies.apache.org/flink/flink-docs-stable/docs/dev/table/sql/overview/) reading from and writing to Kafka with the [Kafka SQL connector](https://nightlies.apache.org/flink/flink-docs-stable/docs/connectors/table/kafka/), using the `playground flink` commands.

The script:

* starts the plaintext environment with Flink (`--enable-flink`): jobmanager, taskmanager and sql-client containers, with the `flink-sql-connector-kafka` jar downloaded through `FLINK_URL`
* sends 10 JSON orders to topic `orders`
* submits a streaming job with `playground flink sql` (`INSERT INTO orders_enriched SELECT ... FROM orders`), and checks the 10 records in topic `orders-enriched`
* runs a batch query on a bounded read of `orders` (`'scan.bounded.mode' = 'latest-offset'`), and checks that it counts 10 orders
* lists the running job with `playground flink list-jobs`, and cancels it with `playground flink cancel`

## How to run

```bash
playground run -f flink-sql-kafka<tab>
```

When `FLINK_TAG` is not set, the Flink version is pinned to `2.2`, because the Kafka SQL connector is released for one Flink minor version. To use another one, set both:

```bash
export FLINK_TAG=2.1
export FLINK_KAFKA_CONNECTOR_VERSION=5.0.0-2.1
```

Flink UI: [http://localhost:18081](http://localhost:18081)

Then try your own statements:

```bash
playground flink sql << 'EOF'
SET 'execution.runtime-mode' = 'batch';
CREATE TABLE orders (id INT, product STRING, quantity INT) WITH (
  'connector' = 'kafka', 'topic' = 'orders', 'properties.bootstrap.servers' = 'broker:9092',
  'scan.startup.mode' = 'earliest-offset', 'scan.bounded.mode' = 'latest-offset', 'format' = 'json'
);
SELECT product, SUM(quantity) FROM orders GROUP BY product;
EOF
```
