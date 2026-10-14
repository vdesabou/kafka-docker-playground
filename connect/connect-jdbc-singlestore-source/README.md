# JDBC Singlestore source connector

## Objective

Quickly test the [JDBC Source](https://docs.confluent.io/kafka-connectors/jdbc/current/source-connector/overview.html) connector with [SingleStore](https://www.singlestore.com/), using the MySQL JDBC driver (5.1.45).

## Prerequisites

With CP 8.x, the JDBC connector version must be 10.8.0 or later (the script exits with code 111 otherwise).

## How to run

```bash
playground run -f jdbc-singlestore-source.sh
```

| Script | Description |
| --- | --- |
| `jdbc-singlestore-source.sh` | JDBC source in `timestamp+incrementing` mode on a SingleStore table |

## What the script does

1. Downloads `mysql-connector-java-5.1.45.jar` if needed and copies it into the JDBC connector `lib` folder.
2. Starts the environment with a `singlestore` container (`ghcr.io/singlestore-labs/singlestoredb-dev`) and waits until it accepts queries.
3. Creates database `db` and table `application` (`id`, `name`, `team_email`, `last_modified`), and inserts 2 rows.
4. Creates the `jdbc-singlestore-source` connector (`jdbc:mysql://singlestore:3306/db`, `mode=timestamp+incrementing` on `last_modified` / `id`, `topic.prefix=singlestore-`).
5. Verifies that 2 records land in topic `singlestore-application` with `playground topic consume`:

```json
{"id":1,"name":"kafka","team_email":"kafka@apache.org","last_modified":1644341162000}
{"id":2,"name":"another","team_email":"another@apache.org","last_modified":1644341163000}
```
