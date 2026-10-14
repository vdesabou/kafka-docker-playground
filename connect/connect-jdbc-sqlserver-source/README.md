# JDBC SQL Server source connector

## Objective

Quickly test the [JDBC Source](https://docs.confluent.io/kafka-connectors/jdbc/current/source-connector/overview.html) connector with Microsoft SQL Server 2019, using either the jTDS or the Microsoft JDBC driver.

## Prerequisites

* With CP 8.x, the JDBC connector version must be 10.8.0 or later (the scripts exit with code 111 otherwise).
* `sqlserver-jtds-ssl.sh` exits with code 111 on CP 5.9.0 and older (non `ubi8` images), see [#1107](https://github.com/vdesabou/kafka-docker-playground/issues/1107).

## How to run

```bash
playground run -f sqlserver-microsoft.sh
```

| Script | Description |
| --- | --- |
| `sqlserver-jtds.sh` | jTDS driver, no SSL. Supports `--enable-sql-datagen` |
| `sqlserver-jtds-ssl.sh` | jTDS driver, SSL encryption (`ssl=require`) |
| `sqlserver-microsoft.sh` | Microsoft driver, no SSL (`encrypt=false`). Supports `--enable-sql-datagen` |
| `sqlserver-microsoft-ssl.sh` | Microsoft driver, SSL encryption with server certificate validation against a truststore |

To inject data for 10 minutes with the Java SQL datagen (built from `sqlserver-datagen/`) after the records are verified:

```bash
playground run -f sqlserver-microsoft.sh --enable-sql-datagen
```

## What the script does

1. SSL variants only: creates a self-signed certificate for `CN=sqlserver` and a JKS truststore (see below).
2. Starts the environment with a `sqlserver` container (`mcr.microsoft.com/mssql/server:2019-latest`).
3. Creates database `testDB` and table `customers` (identity `id` starting at 1001) with 4 rows.
4. Creates the source connector (`sqlserver-source` or `sqlserver-source-ssl`) in `incrementing` mode on `id`, with `topic.prefix=sqlserver-`.
5. Inserts one more row, then verifies that 5 records land in topic `sqlserver-customers` with `playground topic consume`.
6. Non-SSL variants with `--enable-sql-datagen`: runs the SQL datagen for 10 minutes.

## SSL setup details

Create a self-signed certificate and import it into a truststore:

```bash
openssl req -x509 -nodes -newkey rsa:2048 -subj '/CN=sqlserver' -keyout /tmp/mssql.key -out /tmp/mssql.pem -days 365
keytool -importcert -alias MSSQLCACert -noprompt -file /tmp/mssql.pem -keystore /tmp/truststore.jks -storepass confluent
```

`ssl/mssql.conf` forces encryption on the server:

```ini
[network]
tlscert = /tmp/mssql.pem
tlskey = /tmp/mssql.key
tlsprotocols = 1.2
forceencryption = 1
```

It is mounted in the `sqlserver` container with the certificate and key:

```yaml
    volumes:
      - ../../connect/connect-jdbc-sqlserver-source/ssl/mssql.conf:/var/opt/mssql/mssql.conf
      - ../../connect/connect-jdbc-sqlserver-source/ssl/mssql.pem:/tmp/mssql.pem
      - ../../connect/connect-jdbc-sqlserver-source/ssl/mssql.key:/tmp/mssql.key
```

jTDS: the truststore is set at JVM level on the `connect` container (`docker-compose.plaintext.jtds-ssl.yml`, which also mounts `ssl/truststore.jks` at `/tmp/truststore.jks`):

```yaml
      KAFKA_OPTS: -Djavax.net.ssl.trustStore=/tmp/truststore.jks -Djavax.net.ssl.trustStorePassword=confluent
```

```json
"connection.url": "jdbc:jtds:sqlserver://sqlserver:1433/testDB;ssl=require"
```

Microsoft driver: the truststore is set in the [connection URL](https://docs.microsoft.com/en-us/sql/connect/jdbc/connecting-with-ssl-encryption?view=sql-server-ver16):

```json
"connection.url": "jdbc:sqlserver://sqlserver:1433;databaseName=testDB;encrypt=true;trustServerCertificate=false;trustStore=/tmp/truststore.jks;trustStorePassword=confluent;"
```
