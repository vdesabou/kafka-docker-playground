# JDBC Oracle 12 Sink connector



## Objective

Quickly test [JDBC Sink](https://docs.confluent.io/current/connect/kafka-connect-jdbc/sink-connector/index.html#quick-start) connector with Oracle 12.

N.B: if you're a Confluent employee, please check this [link](https://confluent.slack.com/archives/C0116NM415F/p1636391410032900) and also [here](https://confluent.slack.com/archives/C0116NM415F/p1636389483030900).

* If you're using a JDBC connector version before `10.0.0`, you need to download Oracle Database 12.2.0.1 JDBC Driver `ojdbc8.jar`from this [page](https://www.oracle.com/database/technologies/jdbc-ucp-122-downloads.html) and place it in `./ojdbc8.jar`

Note: Oracle Database Enterprise Edition 12.x and 18c are no longer available for download. The software is available as a media or FTP request for those customers who own a valid Oracle Database product license for any edition. To request access to these releases, follow the instructions in [Oracle Support Document 1071023.1 (Requesting Physical Shipment or Download URL for Software Media)](https://support.oracle.com/epmos/faces/ui/km/DocumentDisplay.jspx?id=1071023.1) from My Oracle Support.

Note: The first time you'll run the script, it will build (using this [project](https://github.com/oracle/docker-images/blob/master/OracleDatabase/SingleInstance/README.md)) the docker image `oracle/database:12.2.0.1-ee`. It takes about 20 minutes.

**Please make sure to increase Docker disk image size (96Gb is known to be working)**:

![Docker image disk](Screenshot1.png)

## How to run

Without SSL:

```
$ ./oracle12-sink.sh
```

with SSL encryption:

```
$ ./oracle12-sink-ssl.sh
```

with SSL encryption + Mutual TLS (case #3 in this [document](https://www.oracle.com/technetwork/database/enterprise-edition/wp-oracle-jdbc-thin-ssl-130128.pdf)):

```
$ ./oracle12-sink-mtls.sh
```

with SSL encryption + Mutual TLS + DB authentication (case #4 in this [document](https://www.oracle.com/technetwork/database/enterprise-edition/wp-oracle-jdbc-thin-ssl-130128.pdf):

```
$ ./oracle12-sink-mtls-db-auth.sh
```

N.B: this is the [best resource](https://www.oracle.com/technetwork/topics/wp-oracle-jdbc-thin-ssl-130128.pdf) I found for Oracle DB and SSL.

## Details of what the script is doing

Build `oracle/database:12.2.0.1-ee` Docker image if required.

Wait (up to 15 minutes) that Oracle DB is up

### Without SSL

Create the source connector with:

```bash
$ curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.confluent.connect.jdbc.JdbcSinkConnector",
                    "tasks.max": "1",
                    "connection.user": "myuser",
                    "connection.password": "mypassword",
                    "connection.url": "jdbc:oracle:thin:@oracle:1521/ORCLPDB1",
                    "topics": "ORDERS",
                    "auto.create": "true",
                    "insert.mode":"insert",
                    "auto.evolve":"true"
          }' \
     http://localhost:8083/connectors/oracle-sink/config | jq .
```

Sending messages to topic `ORDERS`:

```bash
$ docker exec -i connect kafka-avro-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic ORDERS --property value.schema='{"type":"record","name":"myrecord","fields":[{"name":"id","type":"int"},{"name":"product", "type": "string"}, {"name":"quantity", "type": "int"}, {"name":"price","type": "float"}]}' << EOF
{"id": 999, "product": "foo", "quantity": 100, "price": 50}
EOF
```

Show content of `ORDERS` table:

```bash
$ docker exec oracle bash -c "echo 'select * from ORDERS;' | sqlplus myuser/mypassword@//localhost:1521/ORCLPDB1"
```

Results:

```
SQL>
product
--------------------------------------------------------------------------------
  quantity      price         id
---------- ---------- ----------
foo
       100   5.0E+001        999

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
```

`connect` container is configured with truststore:

```
      KAFKA_OPTS: -Djavax.net.ssl.trustStore=/tmp/truststore.jks
                  -Djavax.net.ssl.trustStorePassword=welcome123
```

`connection.url` is set to

```
jdbc:oracle:thin:@(DESCRIPTION=(ADDRESS=(PROTOCOL=TCPS)(HOST=oracle)(PORT=1532))(CONNECT_DATA=(SERVICE_NAME=ORCLCDB))(SECURITY=(SSL_SERVER_CERT_DN=\"CN=server,C=US\")))
```

Note that we force the driver to verify that the server’s DN matches with `"connection.oracle.net.ssl_server_dn_match": "true"` (note that for JDBC connector version lower than 10.x, this property have to be set at JVM level)

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

`.ora` files are same as before except that we set `SSL_CLIENT_AUTHENTICATION = TRUE`.


`connect` container is configured with truststore **and** keystore:

```
      KAFKA_OPTS: -Djavax.net.ssl.trustStore=/tmp/truststore.jks
                  -Djavax.net.ssl.trustStorePassword=welcome123
                  -Djavax.net.ssl.keyStore=/tmp/keystore.jks
                  -Djavax.net.ssl.keyStorePassword=welcome123
```
### With SSL encryption + Mutual TLS + DB authentication (case #4 in this [document](https://www.oracle.com/technetwork/database/enterprise-edition/wp-oracle-jdbc-thin-ssl-130128.pdf)

`.ora` files are same as before except that we set TCPS as authentication `SQLNET.AUTHENTICATION_SERVICES = (TCPS,NTS,BEQ)`.

Connector is set with `"connection.oracle.net.authentication_services": "(TCPS)"` (note that for JDBC connector version lower than 10.x, this property have to be set at JVM level):

```json
"connection.oracle.net.authentication_services": "(TCPS)",
"connection.url": "jdbc:oracle:thin:@(DESCRIPTION=(ADDRESS=(PROTOCOL=TCPS)(HOST=oracle)(PORT=1532))(CONNECT_DATA=(SERVICE_NAME=ORCLCDB))(SECURITY=(SSL_SERVER_CERT_DN=\"CN=server,C=US\")))",
```

N.B: `connection.user` and `connection.password` are not set.

We also need to alter user `myuser` in order to be identified as `CN=connect,C=US`

```bash
$ docker exec -i oracle sqlplus sys/Admin123@//localhost:1521/ORCLCDB as sysdba <<- EOF
	ALTER USER C##MYUSER IDENTIFIED EXTERNALLY AS 'CN=connect,C=US';
	exit;
EOF
```

N.B: Control Center is reachable at [http://127.0.0.1:9021](http://127.0.0.1:9021])
