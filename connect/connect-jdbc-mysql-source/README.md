# JDBC MySQL Source connector

## Objective

Quickly test the [JDBC Source](https://docs.confluent.io/kafka-connectors/jdbc/current/source-connector/overview.html) connector with MySQL, using MySQL Connector/J 8.4.0.

## Prerequisites

With CP 8.x, the JDBC connector version must be 10.8.0 or later (the scripts exit with code 111 otherwise).

## How to run

```bash
playground run -f mysql.sh
```

| Script | Description |
| --- | --- |
| `mysql.sh` | No SSL (`useSSL=false`) |
| `mysql-ssl.sh` | SSL encryption: user `userssl` requires SSL, server certificate verified with a truststore |
| `mysql-mtls.sh` | SSL encryption + mutual TLS: user `usermtls`, client certificate provided with a keystore |

With `--enable-sql-datagen`, once the example succeeded, `playground run` injects rows in the `CUSTOMERS` table with [`benchmark-load.bash`](benchmark-load.bash) (the same load as `playground connector benchmark`) for 10 minutes: one row per transaction, from 5 parallel sessions, logging the rows inserted every 30 seconds. `SQL_DATAGEN_DURATION` (minutes, default `10`) and `SQL_DATAGEN_SESSIONS` (default `5`) change the duration and the number of sessions.

```bash
playground run -f mysql.sh --enable-sql-datagen

# inject rows for 2 minutes only
SQL_DATAGEN_DURATION=2 playground run -f mysql.sh --enable-sql-datagen
```

## What the script does

1. Downloads `mysql-connector-j-8.4.0.jar` if needed and copies it into the JDBC connector `lib` folder.
2. SSL / mTLS variants only: starts the `mysql` container first, copies its generated `ca.pem`, `client-cert.pem` and `client-key.pem`, and converts them into `security/truststore.jks` and `security/keystore.jks`.
3. Starts the environment, creates the `CUSTOMERS` table in database `mydb` (the columns of the other database examples: `id` auto-increment, `first_name`, `last_name`, `email`, `gender`, `club_status`, `comments`, `create_ts`, `update_ts`) and inserts 2 rows.
4. Creates the source connector (`mysql-source`, `mysql-ssl-source` or `mysql-mtls-source`) in `timestamp+incrementing` mode on `update_ts` / `id`, with `topic.prefix=mysql-`.
5. Verifies that at least 2 records land in topic `mysql-CUSTOMERS` with `playground topic consume`.
