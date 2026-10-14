# Oracle CDC Source (Oracle 19c) Source connector

## Objective

Quickly test the [Oracle CDC Source](https://docs.confluent.io/kafka-connectors/oracle-cdc/current/overview.html) connector with Oracle 19c, using a container database (CDB) or a pluggable database (PDB), in plaintext, TLS or mutual TLS.

## Prerequisites

The scripts need an Oracle 19c Docker image. They look for it in this order:

1. A prebuilt image already present locally.
2. A prebuilt image downloaded from the Confluent S3 bucket (Confluent employees only, requires AWS credentials). If you're a Confluent employee, check this [link](https://confluent.slack.com/archives/C0116NM415F/p1636391410032900) and also [here](https://confluent.slack.com/archives/C0116NM415F/p1636389483030900).
3. Otherwise, the image is built using the [oracle/docker-images](https://github.com/oracle/docker-images/blob/master/OracleDatabase/SingleInstance/README.md) project. Download Oracle Database 19c (19.3) for Linux x86-64 `LINUX.X64_193000_db_home.zip` from this [page](https://www.oracle.com/database/technologies/oracle19c-linux-downloads.html) and place it in this folder (on Apple Silicon, `LINUX.ARM64_1919000_db_home.zip` is used instead). The first build takes about 10 minutes.

**Make sure to increase the Docker disk image size (96 GB is known to be working)**:

![Docker image disk](Screenshot1.png)

With CP 8.x, the connector version must be at least 2.14.9 (otherwise the scripts exit with code 111).

## How to run

```bash
playground run -f cdc-oracle19-cdb-table.sh
```

| Script | Description |
| --- | --- |
| `cdc-oracle19-cdb-table.sh` | Table `CUSTOMERS` in the CDB (`ORCLCDB`), plaintext |
| `cdc-oracle19-pdb-table.sh` | Table `CUSTOMERS` in the PDB (`ORCLPDB1`), plaintext |
| `cdc-oracle19-pdb-mview.sh` | Materialized view `CUSTOMERS_MV` in the PDB, refreshed after changes on `CUSTOMERS` |
| `cdc-oracle19-cdb-table-ssl.sh` | CDB, TLS encryption (TCPS listener on port 1532, client truststore) |
| `cdc-oracle19-pdb-table-ssl.sh` | PDB, TLS encryption |
| `cdc-oracle19-cdb-table-mtls.sh` | CDB, TLS encryption + mutual TLS (case #3 of the [Oracle JDBC thin SSL white paper](https://www.oracle.com/technetwork/topics/wp-oracle-jdbc-thin-ssl-130128.pdf)) |
| `cdc-oracle19-pdb-table-mtls.sh` | PDB, TLS encryption + mutual TLS |
| `cdc-oracle19-cdb-table-mtls-db-auth.sh` | CDB, TLS encryption + mutual TLS + database authentication with the client certificate (case #4 of the white paper) |
| `cdc-oracle19-pdb-table-mtls-db-auth.sh` | PDB variant of the above. **Does not work**, see [Oracle CDC: mTLS with DB authentication cannot work with PDB](https://github.com/vdesabou/kafka-docker-playground/issues/833) |

## What the script does

1. Gets or builds the Oracle 19c image and starts the environment with the matching docker-compose override (for TLS variants, the `oracle` container is started first to create the wallets and reconfigure the listener, then the rest of the stack).
2. Creates the `C##CDC_PRIVS` role and the `C##MYUSER` user with the LogMiner privileges, and enables supplemental logging (`cdb-table` and `pdb-table` also run Confluent's `oracle-readiness.sql` check).
3. Creates the `CUSTOMERS` table (with an update trigger) and inserts 5 rows.
4. Creates the Oracle CDC source connector (`start.from` = `snapshot`, redo log topic `redo-log-topic`, table topic template `${databaseName}.${schemaName}.${tableName}`).
5. Inserts, updates and deletes rows, then adds a `country` column and inserts/updates more rows.
6. Verifies the table topic (`ORCLCDB.C__MYUSER.CUSTOMERS` or `ORCLPDB1.C__MYUSER.CUSTOMERS`) and `redo-log-topic` with `playground topic consume`.

## Output

The 5 rows present before the connector started are snapshotted with `op_type` `R` (refresh):

```json
{"ID":"\u0001","FIRST_NAME":{"string":"Rica"},"LAST_NAME":{"string":"Blaisdell"},"EMAIL":{"string":"rblaisdell0@rambler.ru"},"GENDER":{"string":"Female"},"CLUB_STATUS":{"string":"bronze"},"COMMENTS":{"string":"Universal optimal hierarchy"},"CREATE_TS":{"long":1604047105216},"UPDATE_TS":{"long":1604047105000},"op_type":"R","table":"ORCLCDB.C##MYUSER.CUSTOMERS","scn":"1449498"}
```

Once started, the connector captures the new database changes into 2 topics.

The table topic (for example `ORCLPDB1.C__MYUSER.CUSTOMERS`) contains the state of the record after the change, plus metadata (SCN, operation timestamp, username, etc.):

```json
{"ID":"*","FIRST_NAME":{"string":"Frantz"},"LAST_NAME":{"string":"Kafka"},"EMAIL":{"string":"fkafka@confluent.io"},"GENDER":{"string":"Male"},"CLUB_STATUS":{"string":"gold"},"COMMENTS":{"string":"Evil is whatever distracts"},"CREATE_TS":{"long":1619473009476},"UPDATE_TS":{"long":1619473009000},"table":{"string":"ORCLCDB.C##MYUSER.CUSTOMERS"},"scn":{"string":"1449894"},"op_type":{"string":"U"},"op_ts":{"string":"1619473009000"},"current_ts":{"string":"1619473012136"},"row_id":{"string":"AAAR9TAAHAAAACGAAA"},"username":{"string":"C##MYUSER"}}
```

The `redo-log-topic` contains the raw LogMiner records (`SCN`, `OPERATION`, `SEG_OWNER`, `TABLE_NAME`, `SQL_REDO`, `SQL_UNDO`, session information, etc.).

## Performance testing

Set the `SQL_DATAGEN` environment variable, or use `--enable-sql-datagen` with `playground run`, on `cdc-oracle19-cdb-table.sh` or `cdc-oracle19-pdb-table.sh`. The script then builds a Java based datagen tool and injects data for 10 minutes at the end of the run:

```bash
playground container exec --container sql-datagen --command "bash -c \"java -jar sql-datagen-1.0-SNAPSHOT-jar-with-dependencies.jar --host oracle --username C##MYUSER --password mypassword --sidOrServerName sid --sidOrServerNameVal ORCLCDB --maxPoolSize 10 --durationTimeMin 10\""
```

You can increase throughput with `--maxPoolSize`.

### Note on redo.log.row.fetch.size

`redo.log.row.fetch.size` (default `10`) is the number of redo log rows fetched at a time. Some examples set it to `1` for demo purposes only, so that each change is fetched as soon as it is available (for example [`cdc-oracle21-pdb-table.sh`](../connect-cdc-oracle21-source/cdc-oracle21-pdb-table.sh)).
If you're planning to inject more data (for example with `SQL_DATAGEN`), keep the default or increase it (for example `1000`), otherwise the connector will lag behind.

## TLS setup details

The best resource found for Oracle DB and SSL is this [white paper](https://www.oracle.com/technetwork/topics/wp-oracle-jdbc-thin-ssl-130128.pdf).

### TLS encryption

- A test CA wallet (`/tmp/root`) and an auto-login server wallet (`/tmp/server`) signed by that CA are created with `orapki` in the `oracle` container.
- A client `truststore.jks` containing the test CA certificate is created with `keytool`.
- `listener.ora`, `sqlnet.ora` and `tnsnames.ora` (see the `ssl/` folder) add a TCPS listener on port 1532 using the server wallet, with `SSL_CLIENT_AUTHENTICATION = FALSE`.
- The connector uses the TCPS port and the truststore:

```json
"oracle.port": 1532,
"oracle.ssl.truststore.file": "/tmp/truststore.jks",
"oracle.ssl.truststore.password": "welcome123",
```

### TLS encryption + mutual TLS

- Same truststore as above, plus a client `keystore.jks` (`CN=connect,C=US`) whose certificate is signed by the test CA.
- The `.ora` files (see the `mtls/` folder) set `SSL_CLIENT_AUTHENTICATION = TRUE` and `SQLNET.AUTHENTICATION_SERVICES = (TCPS,NTS,BEQ)`.
- The connector adds the keystore:

```json
"oracle.port": 1532,
"oracle.ssl.truststore.file": "/tmp/truststore.jks",
"oracle.ssl.truststore.password": "welcome123",
"oracle.username": "C##MYUSER",
"oracle.password": "mypassword",
"oracle.connection.javax.net.ssl.keyStore": "/tmp/keystore.jks",
"oracle.connection.javax.net.ssl.keyStorePassword": "welcome123",
```

### TLS encryption + mutual TLS + DB authentication

`oracle.username` and `oracle.password` are not set; the database user is authenticated with the client certificate:

```json
"oracle.port": 1532,
"oracle.ssl.truststore.file": "/tmp/truststore.jks",
"oracle.ssl.truststore.password": "welcome123",
"oracle.connection.javax.net.ssl.keyStore": "/tmp/keystore.jks",
"oracle.connection.javax.net.ssl.keyStorePassword": "welcome123",
"oracle.connection.oracle.net.authentication_services": "(TCPS)",
```

The user `C##MYUSER` is altered to be identified by the certificate DN:

```sql
ALTER USER C##MYUSER IDENTIFIED EXTERNALLY AS 'CN=connect,C=US';
```
