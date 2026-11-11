# JDBC Vertica sink connector

## Objective

Quickly test the [JDBC Sink](https://docs.confluent.io/kafka-connectors/jdbc/current/sink-connector/overview.html) connector with Vertica (`cjonesy/docker-vertica`), using the Vertica JDBC driver 10.0.1 (`com.vertica.jdbc:vertica-jdbc:10.0.1-0` from Maven Central).

## Prerequisites

With CP 8.x, the JDBC connector version must be 10.8.0 or later (the script exits with code 111 otherwise).

## How to run

```bash
playground run -f vertica-sink.sh
```

| Script | Description |
| --- | --- |
| `vertica-sink.sh` | JDBC sink writing Avro records to a Vertica table |

## What the script does

1. Downloads `vertica-jdbc.jar` from Maven Central if needed, then copies it into the JDBC connector `lib` folder.
2. Starts Vertica alongside the plaintext environment and waits for `Vertica is now running`.
3. Creates table `docker.mytable (f1 varchar(20))` with `vsql`.
4. Produces 10 Avro records (`{"f1":"value<n>"}`) to topic `mytable` with `playground topic produce`.
5. Creates the `jdbc-vertica-sink` connector (`jdbc:vertica://vertica:5433/docker`, user `dbadmin`, `auto.create=true`).
6. Runs `select * from docker.mytable;` with `vsql` and checks that `value1` is present:

```text
   f1
---------
 value10
 value1
 ...
 value2
(10 rows)
```
