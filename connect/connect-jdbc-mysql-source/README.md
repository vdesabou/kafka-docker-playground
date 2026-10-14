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
| `mysql.sh` | No SSL (`useSSL=false`). Supports `--enable-sql-datagen` to inject extra rows for 1 minute |
| `mysql-ssl.sh` | SSL encryption: user `userssl` requires SSL, server certificate verified with a truststore |
| `mysql-mtls.sh` | SSL encryption + mutual TLS: user `usermtls`, client certificate provided with a keystore |

To inject data continuously with the SQL datagen (built from `mysql-datagen/`):

```bash
playground run -f mysql.sh --enable-sql-datagen
```

## What the script does

1. Downloads `mysql-connector-j-8.4.0.jar` if needed and copies it into the JDBC connector `lib` folder.
2. SSL / mTLS variants only: starts the `mysql` container first, copies its generated `ca.pem`, `client-cert.pem` and `client-key.pem`, and converts them into `security/truststore.jks` and `security/keystore.jks`.
3. Starts the environment, creates the `team` table in database `mydb` (`id` auto-increment, `last_modified` DATETIME) and inserts 2 rows.
4. `mysql.sh` with `--enable-sql-datagen`: runs the SQL datagen against `mydb` for 1 minute.
5. Creates the source connector (`mysql-source`, `mysql-ssl-source` or `mysql-mtls-source`) in `timestamp+incrementing` mode on `last_modified` / `id`, with `topic.prefix=mysql-`.
6. Verifies that at least 2 records land in topic `mysql-team` with `playground topic consume`.
