# Kudu Sink connector

## Objective

Quickly test the [Kudu Sink](https://docs.confluent.io/current/connect/kafka-connect-kudu/sink-connector/index.html) connector.

## Prerequisites

Download the Cloudera Impala JDBC driver `ImpalaJDBC42.jar` from this [page](https://www.cloudera.com/downloads/connectors/impala/jdbc.html) and place it in this folder.

If you're a Confluent employee, the jar is downloaded automatically from the playground S3 bucket when AWS credentials are set (see this [link](https://confluent.slack.com/archives/C0116NM415F/p1636391410032900)).

Not supported with the `cfk` environment. With CP 8.x, the minimum supported connector version is 1.0.6 (the script exits with code 111 otherwise).

## How to run

```bash
playground run -f kudu-sink.sh
```

## What the script does

1. Copies `ImpalaJDBC42.jar` into the `confluentinc-kafka-connect-kudu` plugin `lib` folder.
2. Starts the environment with a Kudu/Impala container (Impala LDAP authentication with user `kudu`).
3. Creates database `test` with `impala-shell`.
4. Creates the Kudu sink connector `kudu-sink` (topic `orders`, `auto.create=true`, `pk.mode=record_value` on field `id`).
5. Produces 2 Avro records to topic `orders` with `playground topic produce`.
6. Verifies that the data is in table `test.orders` with `impala-shell`.

Example of result:

```text
+-----+---------+----------+-------+
| id  | product | quantity | price |
+-----+---------+----------+-------+
| 2   | foo     | 2        | 0.87  |
+-----+---------+----------+-------+
```
