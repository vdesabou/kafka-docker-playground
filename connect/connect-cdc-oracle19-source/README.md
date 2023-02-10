# Oracle CDC Source (Oracle 19c) Source connector

## Objective

Quickly test [Oracle CDC Source Connector](https://docs.confluent.io/kafka-connect-oracle-cdc/current/) with Oracle 19c.

N.B: if you're a Confluent employee, please check this [link](https://confluent.slack.com/archives/C0116NM415F/p1636391410032900) and also [here](https://confluent.slack.com/archives/C0116NM415F/p1636389483030900).

Download Oracle Database 19c (19.3) for Linux x86-64 `LINUX.X64_193000_db_home.zip`from this [page](https://www.oracle.com/database/technologies/oracle19c-linux-downloads.html) and place it in `./LINUX.X64_193000_db_home.zip`


Note: The first time you'll run the script, it will build (using this [project](https://github.com/oracle/docker-images/blob/master/OracleDatabase/SingleInstance/README.md)) the docker image `oracle/database:19.3.0-ee`. It takes about 10 minutes.

**Please make sure to increase Docker disk image size (96Gb is known to be working)**:

![Docker image disk](Screenshot1.png)

## Note on `redo.log.row.fetch.size`

The connector is configured with `"redo.log.row.fetch.size":1` for demo purpose only. 
If you're planning to inject more data, it is recommended to increase the value.

You can set environment variable `ORACLE_DATAGEN` before running the example and it will use a Java based datagen tool:

Example:

```
DURATION=10
log "Injecting data for $DURATION minutes"
docker exec -d oracle-datagen bash -c "java ${JAVA_OPTS} -jar oracle-datagen-1.0-SNAPSHOT-jar-with-dependencies.jar --host oracle --username C##MYUSER --password mypassword --sidOrServerName sid --sidOrServerNameVal ORCLCDB --maxPoolSize 10 --durationTimeMin $DURATION"
```

You can increase thoughtput with `maxPoolSize`.

## How to run

Without SSL:

```
$ ./cdc-oracle19-cdb-table.sh
```

or

```
$ ./cdc-oracle19-pdb-table.sh
```

with SSL encryption:

```
$ ./cdc-oracle19-cdb-table-ssl.sh
```

or

```
$ ./cdc-oracle19-pdb-table-ssl.sh
```

with SSL encryption + Mutual TLS (case #3 in this [document](https://www.oracle.com/technetwork/database/enterprise-edition/wp-oracle-jdbc-thin-ssl-130128.pdf)):

```
$ ./cdc-oracle19-cdb-table-mtls.sh
```

or

```
$ ./cdc-oracle19-pdb-table-mtls.sh
```

with SSL encryption + Mutual TLS + DB authentication (case #4 in this [document](https://www.oracle.com/technetwork/database/enterprise-edition/wp-oracle-jdbc-thin-ssl-130128.pdf):

```
$ ./cdc-oracle19-cdb-table-mtls-db-auth.sh
```

N.B: `./cdc-oracle19-pdb-table-mtls-db-auth.sh` does not work, see [Oracle CDC: mTLS with DB authentication cannot work with PDB](https://github.com/vdesabou/kafka-docker-playground/issues/833)


N.B: this is the [best resource](https://www.oracle.com/technetwork/topics/wp-oracle-jdbc-thin-ssl-130128.pdf) I found for Oracle DB and SSL.

Note:

Using ksqlDB using CLI:

```bash
$ docker exec -i ksqldb-cli ksql http://ksqldb-server:8088
```

## Details of what the script is doing

### Without SSL

#### CDB table

Create the source connector with:

```bash
$ curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.confluent.connect.oracle.cdc.OracleCdcSourceConnector",
               "tasks.max":2,
               "key.converter": "io.confluent.connect.avro.AvroConverter",
               "key.converter.schema.registry.url": "http://schema-registry:8081",
               "value.converter": "io.confluent.connect.avro.AvroConverter",
               "value.converter.schema.registry.url": "http://schema-registry:8081",
               "confluent.license": "",
               "confluent.topic.bootstrap.servers": "broker:9092",
               "confluent.topic.replication.factor": "1",
               "oracle.server": "oracle",
               "oracle.port": 1521,
               "oracle.sid": "ORCLCDB",
               "oracle.username": "C##MYUSER",
               "oracle.password": "mypassword",
               "start.from":"snapshot",
               "redo.log.topic.name": "redo-log-topic",
               "redo.log.consumer.bootstrap.servers":"broker:9092",
               "table.inclusion.regex": ".*CUSTOMERS.*",
               "table.topic.name.template": "${databaseName}.${schemaName}.${tableName}",
               "numeric.mapping": "best_fit",
               "connection.pool.max.size": 20,
               "redo.log.row.fetch.size":1,
               "oracle.dictionary.mode": "auto"
          }' \
     http://localhost:8083/connectors/cdc-oracle-source-cdb/config | jq .
```

Verify the topic `ORCLCDB.C__MYUSER.CUSTOMERS`:

```bash
$ docker exec connect kafka-avro-console-consumer -bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic ORCLCDB.C__MYUSER.CUSTOMERS --from-beginning --max-messages 2
```

Results:

```json
{"ID":"\u0001","FIRST_NAME":{"string":"Rica"},"LAST_NAME":{"string":"Blaisdell"},"EMAIL":{"string":"rblaisdell0@rambler.ru"},"GENDER":{"string":"Female"},"CLUB_STATUS":{"string":"bronze"},"COMMENTS":{"string":"Universal optimal hierarchy"},"CREATE_TS":{"long":1604047105216},"UPDATE_TS":{"long":1604047105000},"op_type":"R","table":"ORCLCDB.C##MYUSER.CUSTOMERS","scn":"1449498"}
{"ID":"\u0002","FIRST_NAME":{"string":"Ruthie"},"LAST_NAME":{"string":"Brockherst"},"EMAIL":{"string":"rbrockherst1@ow.ly"},"GENDER":{"string":"Female"},"CLUB_STATUS":{"string":"platinum"},"COMMENTS":{"string":"Reverse-engineered tangible interface"},"CREATE_TS":{"long":1604047105230},"UPDATE_TS":{"long":1604047105000},"op_type":"R","table":"ORCLCDB.C##MYUSER.CUSTOMERS","scn":"1449498"}
```

#### PDB table

Grant select on CUSTOMERS table:

```bash
$ docker exec -i oracle sqlplus C\#\#MYUSER/mypassword@//localhost:1521/ORCLPDB1 << EOF
     ALTER SESSION SET CONTAINER=ORCLPDB1;
     GRANT select on CUSTOMERS TO C##MYUSER;
EOF
```

Create the source connector with:

```bash
$ curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.confluent.connect.oracle.cdc.OracleCdcSourceConnector",
               "tasks.max":2,
               "key.converter": "io.confluent.connect.avro.AvroConverter",
               "key.converter.schema.registry.url": "http://schema-registry:8081",
               "value.converter": "io.confluent.connect.avro.AvroConverter",
               "value.converter.schema.registry.url": "http://schema-registry:8081",
               "confluent.license": "",
               "confluent.topic.bootstrap.servers": "broker:9092",
               "confluent.topic.replication.factor": "1",
               "oracle.server": "oracle",
               "oracle.port": 1521,
               "oracle.sid": "ORCLCDB",
               "oracle.pdb.name": "ORCLPDB1",
               "oracle.username": "C##MYUSER",
               "oracle.password": "mypassword",
               "start.from":"snapshot",
               "redo.log.topic.name": "redo-log-topic",
               "redo.log.consumer.bootstrap.servers":"broker:9092",
               "table.inclusion.regex": "ORCLPDB1[.].*[.]CUSTOMERS",
               "table.topic.name.template": "${databaseName}.${schemaName}.${tableName}",
               "numeric.mapping": "best_fit",
               "connection.pool.max.size": 20,
               "redo.log.row.fetch.size":1,
               "oracle.dictionary.mode": "auto"
          }' \
     http://localhost:8083/connectors/cdc-oracle-source-pdb/config | jq .
```

Verify the topic `ORCLPDB1.C__MYUSER.CUSTOMERS`:

```bash
$ docker exec connect kafka-avro-console-consumer -bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic ORCLPDB1.C__MYUSER.CUSTOMERS --from-beginning --max-messages 2
```

Results:

```json
{"ID":"\u0001","FIRST_NAME":{"string":"Rica"},"LAST_NAME":{"string":"Blaisdell"},"EMAIL":{"string":"rblaisdell0@rambler.ru"},"GENDER":{"string":"Female"},"CLUB_STATUS":{"string":"bronze"},"COMMENTS":{"string":"Universal optimal hierarchy"},"CREATE_TS":{"long":1604047707934},"UPDATE_TS":{"long":1604047707000},"op_type":"R","table":"ORCLPDB1.C##MYUSER.CUSTOMERS","scn":"1449255"}
{"ID":"\u0002","FIRST_NAME":{"string":"Ruthie"},"LAST_NAME":{"string":"Brockherst"},"EMAIL":{"string":"rbrockherst1@ow.ly"},"GENDER":{"string":"Female"},"CLUB_STATUS":{"string":"platinum"},"COMMENTS":{"string":"Reverse-engineered tangible interface"},"CREATE_TS":{"long":1604047707939},"UPDATE_TS":{"long":1604047707000},"op_type":"R","table":"ORCLPDB1.C##MYUSER.CUSTOMERS","scn":"1449255"}
```

The above records was present before the connector startup thus the operation type is "R" which means "REFRESH".
Once started, the connector captures the new database changes and stream them into 2 topics:

The "table topic" like `ORCLPDB1.C__MYUSER.CUSTOMERS`
```json
{"ID":"*","FIRST_NAME":{"string":"Frantz"},"LAST_NAME":{"string":"Kafka"},"EMAIL":{"string":"fkafka@confluent.io"},"GENDER":{"string":"Male"},"CLUB_STATUS":{"string":"gold"},"COMMENTS":{"string":"Evil is whatever distracts"},"CREATE_TS":{"long":1619473009476},"UPDATE_TS":{"long":1619473009000},"table":{"string":"ORCLCDB.C##MYUSER.CUSTOMERS"},"scn":{"string":"1449894"},"op_type":{"string":"U"},"op_ts":{"string":"1619473009000"},"current_ts":{"string":"1619473012136"},"row_id":{"string":"AAAR9TAAHAAAACGAAA"},"username":{"string":"C##MYUSER"}}
```
The above event represent the state of the database record after being updated. It captures also some metadata which is not present in the refresh event like scn, operation timestamp, username, etc.

The "technical" event is present in the `redo-log-topic`
```json
{"SCN":{"long":1448360},"START_SCN":{"long":1448360},"COMMIT_SCN":{"long":1448361},"TIMESTAMP":{"long":1619524688000},"START_TIMESTAMP":{"long":1619524688000},"COMMIT_TIMESTAMP":{"long":1619524688000},"XIDUSN":{"long":8},"XIDSLT":{"long":8},"XIDSQN":{"long":725},"XID":{"bytes":"\b\u0000\b\u0000Õ\u0002\u0000\u0000"},"PXIDUSN":{"long":8},"PXIDSLT":{"long":8},"PXIDSQN":{"long":725},"PXID":{"bytes":"\b\u0000\b\u0000Õ\u0002\u0000\u0000"},"TX_NAME":null,"OPERATION":{"string":"UPDATE"},"OPERATION_CODE":{"int":3},"ROLLBACK":{"boolean":false},"SEG_OWNER":{"string":"C##MYUSER"},"SEG_NAME":{"string":"CUSTOMERS"},"TABLE_NAME":{"string":"CUSTOMERS"},"SEG_TYPE":{"int":2},"SEG_TYPE_NAME":{"string":"TABLE"},"TABLE_SPACE":{"string":"USERS"},"ROW_ID":{"string":"AAAR9TAAHAAAACHAAF"},"USERNAME":{"string":"C##MYUSER"},"OS_USERNAME":{"string":"oracle"},"MACHINE_NAME":{"string":"oracle"},"AUDIT_SESSIONID":{"long":90002},"SESSION_NUM":{"long":867},"SERIAL_NUM":{"long":29292},"SESSION_INFO":{"string":"login_username=C##MYUSER client_info= OS_username=oracle Machine_name=oracle OS_terminal= OS_process_id=3211 OS_program_name=sqlplus@oracle (TNS V1-V3)"},"THREAD_NUM":{"long":1},"SEQUENCE_NUM":{"long":3},"RBASQN":{"long":2},"RBABLK":{"long":192144},"RBABYTE":{"long":100},"UBAFIL":{"long":4},"UBABLK":{"long":16783950},"UBAREC":{"long":36},"UBASQN":{"long":218},"ABS_FILE_NUM":{"long":4},"REL_FILE_NUM":{"long":7},"DATA_BLK_NUM":{"long":135},"DATA_OBJ_NUM":{"long":73555},"DATA_OBJV_NUM":{"long":1},"DATA_OBJD_NUM":{"long":73555},"SQL_REDO":{"string":"update \"C##MYUSER\".\"CUSTOMERS\" set \"CLUB_STATUS\" = 'gold', \"UPDATE_TS\" = TO_TIMESTAMP('2021-04-27 11:58:07.000') where \"ID\" = '42' and \"FIRST_NAME\" = 'Frantz' and \"LAST_NAME\" = 'Kafka' and \"EMAIL\" = 'fkafka@confluent.io' and \"GENDER\" = 'Male' and \"CLUB_STATUS\" = 'bronze' and \"COMMENTS\" = 'Evil is whatever distracts' and \"CREATE_TS\" = TO_TIMESTAMP('2021-04-27 11:58:07.678') and \"UPDATE_TS\" = TO_TIMESTAMP('2021-04-27 11:58:07.000') and ROWID = 'AAAR9TAAHAAAACHAAF';"},"SQL_UNDO":{"string":"update \"C##MYUSER\".\"CUSTOMERS\" set \"CLUB_STATUS\" = 'bronze', \"UPDATE_TS\" = TO_TIMESTAMP('2021-04-27 11:58:07.000') where \"ID\" = '42' and \"FIRST_NAME\" = 'Frantz' and \"LAST_NAME\" = 'Kafka' and \"EMAIL\" = 'fkafka@confluent.io' and \"GENDER\" = 'Male' and \"CLUB_STATUS\" = 'gold' and \"COMMENTS\" = 'Evil is whatever distracts' and \"CREATE_TS\" = TO_TIMESTAMP('2021-04-27 11:58:07.678') and \"UPDATE_TS\" = TO_TIMESTAMP('2021-04-27 11:58:07.000') and ROWID = 'AAAR9TAAHAAAACHAAF';"},"RS_ID":{"string":" 0x000002.0002ee90.0064 "},"SSN":{"long":0},"CSF":{"boolean":false},"INFO":null,"STATUS":{"int":0},"REDO_VALUE":{"long":298},"UNDO_VALUE":{"long":299},"SAFE_RESUME_SCN":{"long":0},"CSCN":{"long":1448361},"OBJECT_ID":null,"EDITION_NAME":null,"CLIENT_ID":null,"SRC_CON_NAME":{"string":"CDB$ROOT"},"SRC_CON_ID":{"long":1},"SRC_CON_UID":{"long":1},"SRC_CON_DBID":{"long":0},"SRC_CON_GUID":null,"CON_ID":{"boolean":false}}
```

### With SSL encryption

`oracle` container is started first in order to get generated certificates from wallet.

wallet `/tmp/server` is created with:

```bash
# Create a wallet for the test CA

$ docker exec oracle bash -c "orapki wallet create -wallet /tmp/root -pwd WalletPasswd123"
# Add a self-signed certificate to the wallet
$ docker exec oracle bash -c "orapki wallet add -wallet /tmp/root -dn CN=root_test,C=US -keysize 2048 -self_signed -validity 3650 -pwd WalletPasswd123"
# Export the certificate
$ docker exec oracle bash -c "orapki wallet export -wallet /tmp/root -dn CN=root_test,C=US -cert /tmp/root/b64certificate.txt -pwd WalletPasswd123"

# Create a wallet for the Oracle server

# Create an empty wallet with auto login enabled
$ docker exec oracle bash -c "orapki wallet create -wallet /tmp/server -pwd WalletPasswd123 -auto_login"
# Add a user In the wallet (a new pair of private/public keys is created)
$ docker exec oracle bash -c "orapki wallet add -wallet /tmp/server -dn CN=server,C=US -pwd WalletPasswd123 -keysize 2048"
# Export the certificate request to a file
$ docker exec oracle bash -c "orapki wallet export -wallet /tmp/server -dn CN=server,C=US -pwd WalletPasswd123 -request /tmp/server/creq.txt"
# Using the test CA, sign the certificate request
$ docker exec oracle bash -c "orapki cert create -wallet /tmp/root -request /tmp/server/creq.txt -cert /tmp/server/cert.txt -validity 3650 -pwd WalletPasswd123"
# You now have the following files under the /tmp/server directory
$ docker exec oracle ls /tmp/server
# View the signed certificate:
$ docker exec oracle bash -c "orapki cert display -cert /tmp/server/cert.txt -complete"
# Add the test CA's trusted certificate to the wallet
$ docker exec oracle bash -c "orapki wallet add -wallet /tmp/server -trusted_cert -cert /tmp/root/b64certificate.txt -pwd WalletPasswd123"
# add the user certificate to the wallet:
$ docker exec oracle bash -c "orapki wallet add -wallet /tmp/server -user_cert -cert /tmp/server/cert.txt -pwd WalletPasswd123"
```

`truststore.jks` is created with:

```bash
# We import the test CA certificate
$ keytool -import -v -alias testroot -file /tmp/b64certificate.txt -keystore /tmp/truststore.jks -storetype JKS -storepass 'welcome123' -noprompt
log "Displaying truststore"
$ keytool -list -keystore /tmp/truststore.jks -storepass 'welcome123' -v
```


Oracle DB is updated to use new `.ora` files, with TCPS config:

listener.ora:

```
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

sqlnet.ora:

```
NAME.DIRECTORY_PATH= (TNSNAMES, EZCONNECT, HOSTNAME)
WALLET_LOCATION =
   (SOURCE =
     (METHOD = FILE)
     (METHOD_DATA =
       (DIRECTORY = /tmp/server)
     )
   )

SSL_CLIENT_AUTHENTICATION = FALSE
SSL_CIPHER_SUITES = (SSL_RSA_WITH_AES_256_CBC_SHA, SSL_RSA_WITH_3DES_EDE_CBC_SHA)
```

tnsnames.ora:

```
ORCLPDB1=
  (DESCRIPTION =
    (ADDRESS = (PROTOCOL = TCPS)(HOST = 0.0.0.0)(PORT = 1532))
    (CONNECT_DATA =
      (SERVER = DEDICATED)
      (SERVICE_NAME = ORCLPDB1)
    )
  )
ORCLCDB=
  (DESCRIPTION =
    (ADDRESS = (PROTOCOL = TCPS)(HOST = 0.0.0.0)(PORT = 1532))
    (CONNECT_DATA =
      (SERVER = DEDICATED)
      (SERVICE_NAME = ORCLCDB)
    )
  )
```

`oracle.port` is set to SSL listener port and we set `oracle.ssl.truststore.file`:

```
"oracle.port": 1532,
"oracle.ssl.truststore.file": "/tmp/truststore.jks",
"oracle.ssl.truststore.password": "welcome123",
```

### With SSL encryption + Mutual TLS (case #3 in this [document](https://www.oracle.com/technetwork/database/enterprise-edition/wp-oracle-jdbc-thin-ssl-130128.pdf))

`truststore.jks` is same as before.

`keystore.jks` is created with:

```bash
$ keytool -genkey -alias testclient -dname 'CN=connect,C=US' -storepass 'welcome123' -storetype JKS -keystore /tmp/keystore.jks -keyalg RSA
# Generate a CSR (Certificate Signing Request):
$ keytool -certreq -alias testclient -file /tmp/csr.txt -keystore /tmp/keystore.jks -storepass 'welcome123'
# Sign the client certificate using the test CA (root)
docker cp csr.txt oracle:/tmp/csr.txt
docker exec oracle bash -c "orapki cert create -wallet /tmp/root -request /tmp/csr.txt -cert /tmp/cert.txt -validity 3650 -pwd WalletPasswd123"
# import the test CA's certificate:
docker cp oracle:/tmp/root/b64certificate.txt b64certificate.txt
$ keytool -import -v -noprompt -alias testroot -file /tmp/b64certificate.txt -keystore /tmp/keystore.jks -storepass 'welcome123'
# Import the signed certificate
docker cp oracle:/tmp/cert.txt cert.txt
$ keytool -import -v -alias testclient -file /tmp/cert.txt -keystore /tmp/keystore.jks -storepass 'welcome123'
log "Displaying keystore"
$ keytool -list -keystore /tmp/keystore.jks -storepass 'welcome123' -v
```

`.ora` files are same as before except that we set `SSL_CLIENT_AUTHENTICATION = TRUE` and TCPS as authentication `SQLNET.AUTHENTICATION_SERVICES = (TCPS,NTS,BEQ)`.


`oracle.port` is set to SSL listener port and we set `oracle.connection.javax.net.ssl.keyStore`:

```json
"oracle.port": 1532,
"oracle.ssl.truststore.file": "/tmp/truststore.jks",
"oracle.ssl.truststore.password": "welcome123",
"oracle.username": "C##MYUSER",
"oracle.password": "mypassword",
"oracle.connection.javax.net.ssl.keyStore": "/tmp/keystore.jks",
"oracle.connection.javax.net.ssl.keyStorePassword": "welcome123",
```
### With SSL encryption + Mutual TLS + DB authentication (case #4 in this [document](https://www.oracle.com/technetwork/database/enterprise-edition/wp-oracle-jdbc-thin-ssl-130128.pdf)

`oracle.port` is set to SSL listener port and we set `oracle.connection.javax.net.ssl.keyStore` and `"connection.oracle.net.authentication_services": "(TCPS)"`:

```json
"oracle.port": 1532,
"oracle.ssl.truststore.file": "/tmp/truststore.jks",
"oracle.ssl.truststore.password": "welcome123",
"oracle.connection.javax.net.ssl.keyStore": "/tmp/keystore.jks",
"oracle.connection.javax.net.ssl.keyStorePassword": "welcome123",
"oracle.connection.oracle.net.authentication_services": "(TCPS)",
```

N.B: `oracle.username` and `oracle.password` are not set.

We also need to alter user `C##MYUSER` in order to be identified as `CN=connect,C=US`

```bash
$ docker exec -i oracle sqlplus sys/Admin123@//localhost:1521/ORCLCDB as sysdba <<- EOF
	ALTER USER C##MYUSER IDENTIFIED EXTERNALLY AS 'CN=connect,C=US';
	exit;
EOF
```

N.B: Control Center is reachable at [http://127.0.0.1:9021](http://127.0.0.1:9021])
