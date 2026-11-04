# Flink SQL on Confluent Cloud

## Objective

Quickly test [Confluent Cloud for Apache Flink](https://docs.confluent.io/cloud/current/flink/overview.html): a
[compute pool](https://docs.confluent.io/cloud/current/flink/concepts/compute-pools.html) and
[Flink SQL statements](https://docs.confluent.io/cloud/current/flink/concepts/statements.html) on the topics of a
Confluent Cloud cluster, with the `playground flink sql|list-jobs|cancel --environment ccloud` commands (the same
commands as the local [Flink SQL with Kafka](../../flink/flink-sql-kafka) example).

## Prerequisites

See [Confluent Cloud examples](https://kafka-docker-playground.io/#/how-to-use?id=%f0%9f%8c%a4%ef%b8%8f-confluent-cloud-examples).
The user logged in to the `confluent` CLI must be allowed to create a compute pool (or set `FLINK_COMPUTE_POOL`) and a
Flink API key (or set `FLINK_API_KEY` and `FLINK_API_SECRET`).

## How to run

```bash
playground run -f flink-sql-kafka<tab>
```

| Environment variable | Description |
| --- | --- |
| `FLINK_COMPUTE_POOL` | compute pool to use (`lfcp-xxx`), in the environment of the cluster. Default: an existing pool of the environment in the region of the cluster, else a new one `kdp-flink-<cloud>-<region>` |
| `FLINK_MAX_CFU` | `--max-cfu` of the pool when it is created (default `10`) |
| `FLINK_API_KEY` / `FLINK_API_SECRET` | Flink API key of the region, used to read the rows of the query. Default: a key created once by `playground flink sql` and kept in the [playground secrets](https://kafka-docker-playground.io/#/playground%20secrets) store (outside the repository) |

## What the script does

1. `bootstrap_ccloud_environment`: environment and cluster (an existing one, or a new one).
2. `bootstrap_ccloud_flink_compute_pool`: a compute pool in the environment and region of the cluster, created with
   `confluent flink compute-pool create` when there is none, and stored in `playground.ini` for `playground flink`.
   An idle pool costs nothing (billed per CFU minute used), so it is kept.
3. Sends 10 Avro orders to topic `flink_orders`: with its schema in Schema Registry, the topic is a Flink table already
   (catalog = environment, database = cluster).
4. With `playground flink sql`, creates table `flink_orders_enriched` (topic and schema) and submits a streaming
   statement `INSERT INTO flink_orders_enriched SELECT id, UPPER(product), quantity, quantity * 9.99 FROM flink_orders`,
   then checks the 10 records in topic `flink_orders_enriched`.
5. Runs a query on a bounded read of `flink_orders` (`/*+ OPTIONS('scan.bounded.mode' = 'latest-offset') */`), and
   checks that it counts 10 orders.
6. Lists the running statement with `playground flink list-jobs`, and stops it with `playground flink cancel`.
7. When it exits (success or failure), deletes the statements it created with `playground flink cancel --all --delete`.

Then try your own statements (each topic with a schema is a table):

```bash
playground flink sql << 'EOF'
SHOW TABLES;
SELECT product, SUM(quantity) AS q
FROM flink_orders /*+ OPTIONS('scan.bounded.mode' = 'latest-offset') */
GROUP BY product;
EOF

playground flink list-jobs --state RUNNING
playground flink cancel --all --delete
```

More in the [Flink deep dive](https://kafka-docker-playground.io/#/deep-dive-flink?id=_6-confluent-cloud-flink-environment-ccloud).
