# JDBC AWS Athena source connector

## Objective

Quickly test the [JDBC Source](https://docs.confluent.io/kafka-connectors/jdbc/current/source-connector/overview.html) connector with AWS Athena.

## Prerequisites

* AWS credentials: export `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` (or configure `~/.aws/credentials`), and `AWS_REGION` (or configure the region in `~/.aws/config`, read with `aws configure get region`).
* The `aws` CLI must be installed.
* An S3 bucket named `pg-bucket-$USER` with dashes and dots removed (e.g. `pgbucketjdoe`) is used as Athena staging directory (`s3://<bucket>/athena`). The script does not create it.
* `customers.sql` contains a hardcoded table `LOCATION` (`s3://pgbucketvsaboulin/athena`): adapt it to your own bucket.
* With CP 8.x, connector version 10.8.0 or later is required (older `--connector-tag` values exit with code 111).

The Simba Athena JDBC driver (`AthenaJDBC42-2.1.3.1002.jar`) is downloaded automatically if missing and copied into the JDBC connector `lib` folder.

## How to run

```bash
playground run -f athena-jdbc-source.sh
```

## What the script does

1. Downloads the Athena JDBC driver if needed and starts the environment.
2. Creates and populates the external table `CUSTOMERS` from `customers.sql`, using the `zzl0/athenacli` Docker image.
3. Creates the `athena-jdbc-source` connector with query `SELECT * FROM customers`, `timestamp` mode on column `update_ts`, and topic prefix `athena-customers`.
4. Consumes topic `athena-customers` with `playground topic consume` (expects at least 5 records).

## Known issues

In `timestamp` mode, the task can fail with:

```
java.sql.SQLDataException: [Simba][JDBC](10140) Error converting value to Timestamp.
        at io.confluent.connect.jdbc.dialect.GenericDatabaseDialect.currentTimeOnDB(GenericDatabaseDialect.java:565)
```

The generic dialect cannot read the current timestamp from Athena. A custom dialect using `SELECT DATE_FORMAT(CURRENT_TIMESTAMP, '%Y-%m-%d %H:%i:%s')` works around it.
