# JDBC AWS Redshift sink connector

## Objective

Quickly test the [JDBC Sink](https://docs.confluent.io/kafka-connectors/jdbc/current/sink-connector/overview.html) connector with AWS Redshift.

## Prerequisites

* AWS credentials: export `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` and `AWS_REGION`, or configure `~/.aws/credentials` and `~/.aws/config`.
* The `aws` CLI must be installed. The credentials must allow creating and deleting Redshift clusters and EC2 security groups.
* With CP 8.x, connector version 10.8.0 or later is required (older `--connector-tag` values exit with code 111).

The Redshift JDBC driver (`redshift-jdbc42-2.1.0.17.jar`) is downloaded automatically if missing and copied into the JDBC connector `lib` folder.

## How to run

```bash
playground run -f redshift-jdbc-sink.sh
```

## What the script does

1. Deletes any leftover Redshift cluster and security group from a previous run, then creates a single-node `ra3.large` Redshift cluster, publicly accessible, and waits until it is available.
2. Creates a security group allowing ingress on port 5439 and attaches it to the cluster.
3. Pre-creates table `orders` with `psql` (the `debezium/postgres` image), otherwise the connector fails with `null (INT32) type doesn't have a mapping to the SQL database column type`.
4. Creates the `redshift-jdbc-sink` connector (`insert` mode, `auto.create=false`, batched inserts of 512).
5. Produces 512 Avro records to topic `orders` with `playground topic produce`.
6. Runs `SELECT * from orders` against Redshift to verify the data.
7. On exit, deletes the Redshift cluster and the security group.
