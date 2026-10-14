# JDBC Hive source connector

## Objective

Quickly test the [JDBC Source](https://docs.confluent.io/kafka-connectors/jdbc/current/source-connector/overview.html) connector with Apache Hive (2.3.2), using the Apache Hive JDBC driver.

**NOT WORKING**: `getCatalogName()` is not implemented by the Hive JDBC driver, see [HIVE-3175](https://issues.apache.org/jira/browse/HIVE-3175).

## Prerequisites

With CP 8.x, the JDBC connector version must be 10.8.0 or later (the script exits with code 111 otherwise).

## How to run

```bash
playground run -f hive-source.sh
```

| Script | Description |
| --- | --- |
| `hive-source.sh` | JDBC source in `bulk` mode on a Hive table (fails, see below) |

## What the script does

1. Downloads the Hive JDBC driver and the Presto CLI (`presto.jar`), and copies `hive-jdbc-3.1.2-standalone.jar` into the JDBC connector `lib` folder.
2. Starts a Hadoop (namenode, datanode), Hive (server, metastore on PostgreSQL) and Presto stack alongside the plaintext environment.
3. Creates table `pokes (foo INT, bar STRING)` with `beeline` and inserts one row through the Presto CLI.
4. Creates the `jdbc-hive-source` connector (`jdbc:hive2://hive-server:10000/default`, `mode=bulk`, `topic.prefix=hive-`).

## Known issues

The task fails with:

```log
org.apache.kafka.connect.errors.ConnectException: java.sql.SQLFeatureNotSupportedException: Method not supported
        at io.confluent.connect.jdbc.source.JdbcSourceTask.poll(JdbcSourceTask.java:475)
Caused by: java.sql.SQLFeatureNotSupportedException: Method not supported
        at org.apache.hive.jdbc.HiveResultSetMetaData.getCatalogName(HiveResultSetMetaData.java:46)
        at io.confluent.connect.jdbc.dialect.GenericDatabaseDialect.describeColumn(GenericDatabaseDialect.java:773)
```
