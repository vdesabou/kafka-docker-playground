# JDBC Oracle 21c Source connector

## Objective

Quickly test the [JDBC Source](https://docs.confluent.io/kafka-connectors/jdbc/current/source-connector/overview.html) connector with Oracle 21c.

## Prerequisites

* With CP 8.x, the JDBC connector version must be 10.8.0 or later (the scripts exit with code 111 otherwise).
* Oracle Database image: the scripts first try to download a prebuilt image from the playground S3 bucket (Confluent employees only, needs AWS credentials: see this [Slack thread](https://confluent.slack.com/archives/C0116NM415F/p1636391410032900) and [this one](https://confluent.slack.com/archives/C0116NM415F/p1636389483030900)). Otherwise, download Oracle Database 21c (21.3) for Linux x86-64 `LINUX.X64_213000_db_home.zip` from this [page](https://www.oracle.com/database/technologies/oracle21c-linux-downloads.html) and place it in this folder. The first run then builds the image `oracle/database:21.3.0-ee` with the [oracle/docker-images](https://github.com/oracle/docker-images/blob/master/OracleDatabase/SingleInstance/README.md) project, which takes about 10 minutes.

**Make sure to increase the Docker disk image size (96 GB is known to work)**:

![Docker image disk](Screenshot1.png)

## How to run

```bash
playground run -f oracle21.sh
```

| Script | Description |
| --- | --- |
| `oracle21.sh` | No SSL (`jdbc:oracle:thin:@oracle:1521/ORCLCDB`) |
| `oracle21-ssl.sh` | SSL encryption (TCPS on port 1532), server DN verified |
| `oracle21-mtls.sh` | SSL encryption + mutual TLS (case #3 in this [document](https://www.oracle.com/technetwork/topics/wp-oracle-jdbc-thin-ssl-130128.pdf)) |
| `oracle21-mtls-db-auth.sh` | SSL encryption + mutual TLS + DB authentication with the client certificate (case #4 in the same document) |

The [Oracle JDBC thin driver SSL white paper](https://www.oracle.com/technetwork/topics/wp-oracle-jdbc-thin-ssl-130128.pdf) is the best resource for Oracle DB and SSL.

### Performance testing

With `--enable-sql-datagen`, `playground run` injects rows in the `CUSTOMERS` table for 10 minutes once the example succeeded (see [Benchmark](#benchmark)):

```bash
playground run -f oracle21.sh --enable-sql-datagen

# inject rows for 2 minutes only
SQL_DATAGEN_DURATION=2 playground run -f oracle21.sh --enable-sql-datagen
```

Increase `SQL_DATAGEN_SESSIONS` (default `5`) to increase throughput.

## What the script does

1. Gets or builds the Oracle Database image and starts it (alone first for the SSL variants), then waits for `DATABASE IS READY TO USE`.
2. Creates user `C##MYUSER` with the `CONNECT`, `CREATE SESSION`, `CREATE TABLE`, `CREATE SEQUENCE` and `CREATE TRIGGER` privileges.
3. SSL variants only: creates the Oracle wallets and the JKS stores, copies the `.ora` files from `ssl/` or `mtls/` into the container and restarts the listener (see below).
4. Creates table `CUSTOMERS` (identity `ID`, trigger `TRG_CUSTOMERS_UPD` setting `UPDATE_TS` on insert/update) and inserts 5 rows.
5. Creates the source connector (`oracle-source`, `oracle-source-ssl`, `oracle-source-mtls` or `oracle-source-mtls-db-auth`) in `timestamp` mode on `UPDATE_TS`, with `numeric.mapping=best_fit`, `schema.pattern=C##MYUSER`, `table.whitelist=CUSTOMERS` and `topic.prefix=oracle-`.
6. Verifies that records land in topic `oracle-CUSTOMERS` with `playground topic consume`.

## Benchmark

[`benchmark-load.bash`](benchmark-load.bash) loads rows in the `CUSTOMERS` table for [`playground connector benchmark`](https://kafka-docker-playground.io/#/playground%20connector%20benchmark), with the same database user and container database (CDB or PDB) as the variant of the example that was run. Once the example is running:

```bash
# time to capture 1M rows inserted in one transaction
playground connector benchmark --nb-records 1000000 --shape bulk

# 100k transactions of one row, then 1M updates of existing rows
playground connector benchmark --nb-records 100000 --shape small-txn
playground connector benchmark --nb-records 1000000 --shape update
```

The connector is paused while the rows are loaded, then resumed, and the benchmark measures the time it takes to produce the records.

`playground run -f oracle21.sh --enable-sql-datagen` uses the same load once the example succeeded: one row per transaction (`--shape small-txn`) from 5 parallel sessions for 10 minutes (`SQL_DATAGEN_SESSIONS`, `SQL_DATAGEN_DURATION` in minutes), logging the rows inserted every 30 seconds.

## SSL setup details

### SSL encryption

The `oracle` container is started first to generate the certificates in Oracle wallets. Wallet `/tmp/server` is created with:

```bash
# Create a wallet for the test CA
orapki wallet create -wallet /tmp/root -pwd WalletPasswd123
# Add a self-signed certificate to the wallet
orapki wallet add -wallet /tmp/root -dn CN=root_test,C=US -keysize 2048 -self_signed -validity 3650 -pwd WalletPasswd123
# Export the certificate
orapki wallet export -wallet /tmp/root -dn CN=root_test,C=US -cert /tmp/root/b64certificate.txt -pwd WalletPasswd123

# Create a wallet for the Oracle server, with auto login enabled
orapki wallet create -wallet /tmp/server -pwd WalletPasswd123 -auto_login
# Add a user in the wallet (a new pair of private/public keys is created)
orapki wallet add -wallet /tmp/server -dn CN=server,C=US -pwd WalletPasswd123 -keysize 2048
# Export the certificate request to a file
orapki wallet export -wallet /tmp/server -dn CN=server,C=US -pwd WalletPasswd123 -request /tmp/server/creq.txt
# Using the test CA, sign the certificate request
orapki cert create -wallet /tmp/root -request /tmp/server/creq.txt -cert /tmp/server/cert.txt -validity 3650 -pwd WalletPasswd123
# Add the test CA's trusted certificate to the wallet
orapki wallet add -wallet /tmp/server -trusted_cert -cert /tmp/root/b64certificate.txt -pwd WalletPasswd123
# Add the user certificate to the wallet
orapki wallet add -wallet /tmp/server -user_cert -cert /tmp/server/cert.txt -pwd WalletPasswd123
```

`truststore.jks` is created by importing the test CA certificate:

```bash
keytool -import -v -alias testroot -file /tmp/b64certificate.txt -keystore /tmp/truststore.jks -storetype JKS -storepass 'welcome123' -noprompt
```

The Oracle listener is reconfigured with a TCPS endpoint, using `ssl/listener.ora`:

```text
SSL_CLIENT_AUTHENTICATION = FALSE

WALLET_LOCATION =
  (SOURCE =
    (METHOD = FILE)
    (METHOD_DATA =
      (DIRECTORY = /tmp/server)
    )
  )

LISTENER =
(DESCRIPTION_LIST =
  (DESCRIPTION =
    (ADDRESS = (PROTOCOL = IPC)(KEY = EXTPROC1))
    (ADDRESS = (PROTOCOL = TCP)(HOST = 0.0.0.0)(PORT = 1521))
  )
  (DESCRIPTION =
     (ADDRESS = (PROTOCOL = TCPS)(HOST = 0.0.0.0)(PORT = 1532))
   )
)

DEDICATED_THROUGH_BROKER_LISTENER=ON
DIAG_ADR_ENABLED = off
```

`ssl/sqlnet.ora`:

```text
NAME.DIRECTORY_PATH= (TNSNAMES, EZCONNECT, HOSTNAME)
WALLET_LOCATION =
   (SOURCE =
     (METHOD = FILE)
     (METHOD_DATA =
       (DIRECTORY = /tmp/server)
     )
   )

SSL_CLIENT_AUTHENTICATION = FALSE
SSL_CIPHER_SUITES = (SSL_ECDHE_RSA_WITH_AES_256_GCM_SHA384, SSL_DHE_RSA_WITH_AES_256_GCM_SHA384, SSL_ECDHE_RSA_WITH_AES_128_GCM_SHA256, SSL_DHE_RSA_WITH_AES_128_GCM_SHA256, SSL_RSA_WITH_AES_256_GCM_SHA384, SSL_RSA_WITH_AES_128_GCM_SHA256)
```

`ssl/tnsnames.ora`:

```text
ORCLPDB1=
  (DESCRIPTION =
    (ADDRESS = (PROTOCOL = TCPS)(HOST = 0.0.0.0)(PORT = 1532))
    (CONNECT_DATA =
      (SERVER = DEDICATED)
      (SERVICE_NAME = ORCLPDB1)
    )
  )
```

The `connect` container is configured with the truststore at JVM level (`docker-compose.plaintext.ssl.yml`):

```yaml
      KAFKA_OPTS: -Djavax.net.ssl.trustStore=/tmp/truststore.jks -Djavax.net.ssl.trustStorePassword=welcome123 -Doracle.net.ssl_server_dn_match=true
```

The connector uses the TCPS URL and forces the driver to verify that the server DN matches:

```json
"connection.oracle.net.ssl_server_dn_match": "true",
"connection.url": "jdbc:oracle:thin:@(DESCRIPTION=(ADDRESS=(PROTOCOL=TCPS)(HOST=oracle)(PORT=1532))(CONNECT_DATA=(SERVICE_NAME=ORCLCDB))(SECURITY=(SSL_SERVER_CERT_DN=\"CN=server,C=US\")))"
```

With JDBC connector versions lower than 10.x, `connection.oracle.net.*` properties are not supported and must be set at JVM level instead.

### SSL encryption + mutual TLS

`truststore.jks` is the same as above. A client `keystore.jks` is created and its certificate signed by the test CA:

```bash
keytool -genkey -alias testclient -dname 'CN=connect,C=US' -storepass 'welcome123' -storetype JKS -keystore /tmp/keystore.jks -keyalg RSA
# Generate a CSR (Certificate Signing Request)
keytool -certreq -alias testclient -file /tmp/csr.txt -keystore /tmp/keystore.jks -storepass 'welcome123'
# Sign the client certificate using the test CA (inside the oracle container)
orapki cert create -wallet /tmp/root -request /tmp/csr.txt -cert /tmp/cert.txt -validity 3650 -pwd WalletPasswd123
# Import the test CA certificate, then the signed certificate
keytool -import -v -noprompt -alias testroot -file /tmp/b64certificate.txt -keystore /tmp/keystore.jks -storepass 'welcome123'
keytool -import -v -alias testclient -file /tmp/cert.txt -keystore /tmp/keystore.jks -storepass 'welcome123'
```

The `.ora` files in `mtls/` are the same as above except `SSL_CLIENT_AUTHENTICATION = TRUE` (and `SQLNET.AUTHENTICATION_SERVICES = (TCPS,NTS,BEQ)` in `sqlnet.ora`, used by the DB authentication variant).

The `connect` container is configured with the truststore **and** the keystore (`docker-compose.plaintext.mtls.yml`):

```yaml
      KAFKA_OPTS: -Djavax.net.ssl.trustStore=/tmp/truststore.jks -Djavax.net.ssl.trustStorePassword=welcome123 -Djavax.net.ssl.keyStore=/tmp/keystore.jks -Djavax.net.ssl.keyStorePassword=welcome123 -Doracle.net.ssl_server_dn_match=true
```

### SSL encryption + mutual TLS + DB authentication

User `C##MYUSER` is altered to be identified by the client certificate:

```sql
ALTER USER C##MYUSER IDENTIFIED EXTERNALLY AS 'CN=connect,C=US';
```

The connector does not set `connection.user` / `connection.password`. TCPS authentication is enabled at JVM level (`docker-compose.plaintext.mtls-db-auth.yml`):

```yaml
      KAFKA_OPTS: -Djavax.net.ssl.trustStore=/tmp/truststore.jks -Djavax.net.ssl.trustStorePassword=welcome123 -Djavax.net.ssl.keyStore=/tmp/keystore.jks -Djavax.net.ssl.keyStorePassword=welcome123 -Doracle.net.ssl_server_dn_match=true -Doracle.net.authentication_services="(TCPS)"
```
