# JDBC Hive sink connector

## Objective

Quickly test the [JDBC Sink](https://docs.confluent.io/kafka-connectors/jdbc/current/sink-connector/overview.html) connector with Apache Hive (2.3.2), using either the Apache Hive JDBC driver or the Progress DataDirect Hive JDBC driver.

## Prerequisites

* With CP 8.x, the JDBC connector version must be 10.8.0 or later (the scripts exit with code 111 otherwise).
* `hive-jdbc-sink-datadirect.sh`: download and install the [Progress DataDirect JDBC driver for Apache Hive](https://documentation.progress.com/output/DataDirect/jdbcquickstarts/hivejdbc_quickstart/index.html#page/jdbchivequick%2Fquick-start-3a-progress-datadirect-for-jdbc-for-ap.html%23) manually and place it as `hive.jar` in this folder. The script exits if it is missing.

## How to run

```bash
playground run -f hive-jdbc-sink-datadirect.sh
```

| Script | Description |
| --- | --- |
| `hive-jdbc-sink-datadirect.sh` | JDBC sink using the Progress DataDirect driver (`jdbc:datadirect:hive://...`). Working version |
| `hive-jdbc-sink.sh` | JDBC sink using the Apache Hive JDBC driver 3.1.2 (`jdbc:hive2://...`). **Not working**, see below |

## What the script does

1. Downloads the Presto CLI (`presto.jar`) and, for the Apache variant, `hive-jdbc-3.1.2-standalone.jar`, then copies the driver jar(s) into the JDBC connector `lib` folder.
2. Starts a Hadoop (namenode, datanode), Hive (server, metastore on PostgreSQL) and Presto stack alongside the plaintext environment.
3. Creates table `pokes (foo INT, bar STRING)` with `beeline`.
4. Produces 10 Avro records to topic `pokes` with `playground topic produce`.
5. Creates the `jdbc-hive-sink` connector (`pk.mode=record_value` on `foo`, `table.name.format=default.${topic}`).
6. Queries `select * from pokes` through the Presto CLI (`localhost:18080`, catalog `hive`) to verify the data.

## Known issues

The Apache Hive JDBC driver does not implement `addBatch()` (see [HIVE-16221](https://issues.apache.org/jira/browse/HIVE-16221) and this [Stack Overflow question](https://stackoverflow.com/questions/50984798/batch-insert-in-hive-using-hive-jdbc)), so the sink fails with:

```log
WARN [jdbc-hive-sink|task-0] Write of 10 records failed, remainingRetries=8 (io.confluent.connect.jdbc.sink.JdbcSinkTask:101)
java.sql.SQLFeatureNotSupportedException: Method not supported
        at org.apache.hive.jdbc.HivePreparedStatement.addBatch(HivePreparedStatement.java:78)
        at io.confluent.connect.jdbc.sink.PreparedStatementBinder.bindRecord(PreparedStatementBinder.java:115)
        at io.confluent.connect.jdbc.sink.BufferedRecords.flush(BufferedRecords.java:183)
```

With the DataDirect driver, the data is written to Hive:

```text
presto:default> select * from pokes;
 foo |   bar
-----+----------
   1 | a string
   2 | a string
 ...
  10 | a string
(10 rows)
```
