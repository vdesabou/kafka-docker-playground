# JDBC Oracle 12 Source connector

![asciinema](https://github.com/vdesabou/gifs/blob/master/connect/connect-jdbc-oracle12-source/asciinema.gif?raw=true)

## Objective

Quickly test [JDBC Source](https://docs.confluent.io/current/connect/kafka-connect-jdbc/source-connector/index.html#kconnect-long-jdbc-source-connector) connector with Oracle 12.


* If you're using a JDBC connector version before `10.0.0`, you need to download Oracle Database 12.2.0.1 JDBC Driver `ojdbc8.jar`from this [page](https://www.oracle.com/database/technologies/jdbc-ucp-122-downloads.html) and place it in `./ojdbc8.jar`
* Download Oracle Database 12c Release 2 (12.2.0.1.0) for Linux x86-64 `linuxx64_12201_database.zip`from this [page](https://www.oracle.com/database/technologies/oracle12c-linux-12201-downloads.html) and place it in `./linuxx64_12201_database.zip`

Note: The first time you'll run the script, it will build (using this [project](https://github.com/oracle/docker-images/blob/master/OracleDatabase/SingleInstance/README.md)) the docker image `oracle/database:12.2.0.1-ee`. It takes about 20 minutes.

**Please make sure to increase Docker disk image size (96Gb is known to be working)**:

![Docker image disk](Screenshot1.png)

## How to run

Without SSL:

```
$ ./oracle12.sh
```

with SSL encryption:

```
$ ./oracle12-ssl.sh
```

with SSL encryption + Mutual TLS authentication:

```
$ ./oracle12-mtls.sh
```

## Details of what the script is doing

Build `oracle/database:12.2.0.1-ee` Docker image if required.

Wait (up to 15 minutes) that Oracle DB is up

### Without SSL

Create the source connector with:

```bash
$ curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class":"io.confluent.connect.jdbc.JdbcSourceConnector",
                    "tasks.max":"1",
                    "connection.user": "myuser",
                    "connection.password": "mypassword",
                    "connection.url": "jdbc:oracle:thin:@oracle:1521/ORCLPDB1",
                    "numeric.mapping":"best_fit",
                    "mode":"timestamp",
                    "poll.interval.ms":"1000",
                    "validate.non.null":"false",
                    "table.whitelist":"CUSTOMERS",
                    "timestamp.column.name":"UPDATE_TS",
                    "topic.prefix":"oracle-",
                    "errors.log.enable": "true",
                    "errors.log.include.messages": "true"
          }' \
     http://localhost:8083/connectors/oracle-source/config | jq .
```

Verify the topic `oracle-CUSTOMERS`:

```bash
$ docker exec connect kafka-avro-console-consumer -bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic oracle-CUSTOMERS --from-beginning --max-messages 2
```

Results:

```json
{"ID":1,"FIRST_NAME":{"string":"Rica"},"LAST_NAME":{"string":"Blaisdell"},"EMAIL":{"string":"rblaisdell0@rambler.ru"},"GENDER":{"string":"Female"},"CLUB_STATUS":{"string":"bronze"},"COMMENTS":{"string":"Universal optimal hierarchy"},"CREATE_TS":{"long":1571238426253},"UPDATE_TS":{"long":1571238426000}}
{"ID":2,"FIRST_NAME":{"string":"Ruthie"},"LAST_NAME":{"string":"Brockherst"},"EMAIL":{"string":"rbrockherst1@ow.ly"},"GENDER":{"string":"Female"},"CLUB_STATUS":{"string":"platinum"},"COMMENTS":{"string":"Reverse-engineered tangible interface"},"CREATE_TS":{"long":1571238426260},"UPDATE_TS":{"long":1571238426000}}
```

### With SSL encryption

`oracle` container is started first in order to get generated certificates from wallet.

wallet `/opt/oracle/admin/ORCLCDB/xdb_wallet/myWallet` is created with:

```bash
# Create a new auto-login wallet.
$ docker exec oracle bash -c "orapki wallet create -wallet /opt/oracle/admin/ORCLCDB/xdb_wallet/myWallet -pwd WalletPasswd123 -auto_login_local"
# Create a self-signed certificate and load it into the wallet.
$ docker exec oracle bash -c "orapki wallet add -wallet /opt/oracle/admin/ORCLCDB/xdb_wallet/myWallet  -pwd WalletPasswd123 -dn \"CN=oracle\" -keysize 1024 -self_signed -validity 3650"
# Check the contents of the wallet. Notice the self-signed certificate is both a user and trusted certificate.
$ docker exec oracle bash -c "orapki wallet display -wallet /opt/oracle/admin/ORCLCDB/xdb_wallet/myWallet -pwd WalletPasswd123"
# Export the certificate, so we can load it into the client (connect) later.
$ docker exec oracle bash -c "orapki wallet export -wallet /opt/oracle/admin/ORCLCDB/xdb_wallet/myWallet -pwd WalletPasswd123 -dn \"CN=oracle\" -cert /tmp/oracle-certificate.crt"
```

The server certificate `oracle-certificate.crt` is then added to JKS `OracleTrustStore.jks`:

```
$ keytool -noprompt -srcstorepass WalletPasswd123 -deststorepass WalletPasswd123 -import -trustcacerts -alias oracle -file /tmp/oracle-certificate.crt -keystore /tmp/OracleTrustStore.jks
```

Oracle DB is updated to use new `.ora` files, with TCPS config:

listener.ora:

```
SSL_CLIENT_AUTHENTICATION = FALSE

WALLET_LOCATION =
  (SOURCE =
    (METHOD = FILE)
    (METHOD_DATA =
      (DIRECTORY = /opt/oracle/admin/ORCLCDB/xdb_wallet/myWallet)
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
       (DIRECTORY = /opt/oracle/admin/ORCLCDB/xdb_wallet/myWallet)
     )
   )

SQLNET.AUTHENTICATION_SERVICES = (TCPS,NTS,BEQ)
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
```

`connect` container is configured with truststore:

```
      KAFKA_OPTS: -Djavax.net.ssl.trustStore=/tmp/OracleTrustStore.jks
                  -Djavax.net.ssl.trustStorePassword=WalletPasswd123
```

`connection.url`is set to `jdbc:oracle:thin:@(DESCRIPTION=(ADDRESS=(PROTOCOL=TCPS)(HOST=oracle)(PORT=1532))(CONNECT_DATA=(SERVICE_NAME=ORCLPDB1)))`

### With SSL encryption + Mutual TLS auth

`oracle` container is started first in order to get generated certificates from wallet.

Generate and export the client certificate `client-certificate.crt` and `clientKeystore.jks`:

```bash
$ keytool -genkey -alias client-alias -keyalg RSA -storepass Confluent101 -dname "CN=connect,OU=TEST,O=CONFLUENT,L=PaloAlto,S=Ca,C=US" -keystore /tmp/clientKeystore.jks
$ keytool -export -alias client-alias -storepass Confluent101 -file /tmp/client-certificate.crt -keystore /tmp/clientKeystore.jks -rfc
```

Import it into Oracle Wallet:

```
$ docker exec oracle bash -c "orapki wallet add -wallet /opt/oracle/admin/ORCLCDB/xdb_wallet/myWallet  -pwd WalletPasswd123 -trusted_cert -cert /tmp/client-certificate.crt"
```

`.ora` files are same as before except that we set `SSL_CLIENT_AUTHENTICATION = TRUE`.


`connect` container is configured with truststore **and** keystore:

```
      KAFKA_OPTS: -Djavax.net.ssl.trustStore=/tmp/OracleTrustStore.jks
                  -Djavax.net.ssl.trustStorePassword=WalletPasswd123
                  -Djavax.net.ssl.keyStore=/tmp/clientKeystore.jks
                  -Djavax.net.ssl.keyStorePassword=Confluent101
```

N.B: Control Center is reachable at [http://127.0.0.1:9021](http://127.0.0.1:9021])
