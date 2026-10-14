# JDBC AWS Redshift source connector

## Objective

Quickly test the [JDBC Source](https://docs.confluent.io/kafka-connectors/jdbc/current/source-connector/overview.html) connector with AWS Redshift.

## Prerequisites

* AWS credentials: export `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` and `AWS_REGION`, or configure `~/.aws/credentials` and `~/.aws/config`.
* The `aws` CLI must be installed. The credentials must allow creating and deleting Redshift clusters and EC2 security groups.
* With CP 8.x, connector version 10.8.0 or later is required (older `--connector-tag` values exit with code 111).

The Redshift JDBC driver (`redshift-jdbc42-2.1.0.17.jar`) is downloaded automatically if missing and copied into the JDBC connector `lib` folder.

## How to run

```bash
playground run -f redshift-jdbc-source.sh
```

## What the script does

1. Removes stale Redshift clusters from previous runs, then creates a single-node `ra3.large` Redshift cluster, publicly accessible, and waits until it is available.
2. Creates a security group allowing ingress on port 5439 and attaches it to the cluster.
3. Creates and populates table `CUSTOMERS` from `customers.sql` with `psql` (the `debezium/postgres` image).
4. Creates the `redshift-jdbc-source` connector in `timestamp+incrementing` mode (`update_ts` / `id`) with topic prefix `redshift-`.
5. Consumes topic `redshift-customers` with `playground topic consume` (expects at least 5 records).
6. On exit, deletes the Redshift cluster.

Example of record:

```json
{
  "club_status": {
    "string": "bronze"
  },
  "comments": {
    "string": "Universal optimal hierarchy"
  },
  "create_ts": {
    "long": 1580230824909
  },
  "email": {
    "string": "rblaisdell0@rambler.ru"
  },
  "first_name": {
    "string": "Rica"
  },
  "gender": {
    "string": "Female"
  },
  "id": 1,
  "last_name": {
    "string": "Blaisdell"
  },
  "update_ts": {
    "long": 1580230824909
  }
}
```
