# Kudu Source connector

## Objective

Quickly test the [Kudu Source](https://docs.confluent.io/current/connect/kafka-connect-kudu/source-connector/index.html) connector.

## Prerequisites

Download the Cloudera Impala JDBC driver `ImpalaJDBC42.jar` from this [page](https://www.cloudera.com/downloads/connectors/impala/jdbc.html) and place it in this folder.

If you're a Confluent employee, the jar is downloaded automatically from the playground S3 bucket when AWS credentials are set (see this [link](https://confluent.slack.com/archives/C0116NM415F/p1636391410032900)).

Not supported with the `cfk` environment. With CP 8.x, the minimum supported connector version is 1.0.6 (the script exits with code 111 otherwise).

## How to run

```bash
playground run -f kudu-source.sh
```

## What the script does

1. Copies `ImpalaJDBC42.jar` into the `confluentinc-kafka-connect-kudu` plugin `lib` folder.
2. Starts the environment with a Kudu/Impala container (Impala LDAP authentication with user `kudu`).
3. Creates database `test` and Kudu table `accounts` with `impala-shell`, and inserts 2 rows (`alice`, `bob`).
4. Creates the Kudu source connector `kudu-source` (`mode=incrementing` on column `id`, `topic.prefix=test-kudu-`).
5. Verifies that topic `test-kudu-accounts` receives 2 records with `playground topic consume`.

Example of records:

```json
{"id":{"long":1},"name":{"string":"alice"}}
{"id":{"long":2},"name":{"string":"bob"}}
```
