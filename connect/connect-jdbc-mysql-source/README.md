# JDBC MySQL Source connector



## Objective

Quickly test [JDBC Source](https://docs.confluent.io/current/connect/kafka-connect-jdbc/source-connector/index.html#kconnect-long-jdbc-source-connector) connector with MySQL.




## How to run

Without SSL:

```
$ playground run -f mysql<use tab key to activate fzf completion (see https://kafka-docker-playground.io/#/cli?id=%e2%9a%a1-setup-completion), otherwise use full path, or correct relative path>
```

with SSL encryption:

```
$ playground run -f mysql-ssl<use tab key to activate fzf completion (see https://kafka-docker-playground.io/#/cli?id=%e2%9a%a1-setup-completion), otherwise use full path, or correct relative path>
```

with SSL encryption + Mutual TLS authentication:

```
$ playground run -f mysql-mtls<use tab key to activate fzf completion (see https://kafka-docker-playground.io/#/cli?id=%e2%9a%a1-setup-completion), otherwise use full path, or correct relative path>
```

### Without SSL

Creating MySQL sink connector

```bash
$ curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class":"io.confluent.connect.jdbc.JdbcSourceConnector",
                    "tasks.max":"10",
                    "connection.url":"jdbc:mysql://mysql:3306/db?user=user&password=password&useSSL=false",
                    "table.whitelist":"application",
                    "mode":"timestamp+incrementing",
                    "timestamp.column.name":"last_modified",
                    "incrementing.column.name":"id",
                    "topic.prefix":"mysql-"
          }' \
     http://localhost:8083/connectors/mysql-source/config | jq .
```

Sending messages to topic orders

```bash
playground topic consume --topic mysql-application --min-expected-messages 2 --timeout 60
```

Results:

```json
{"id":1,"name":"kafka","team_email":"kafka@apache.org","last_modified":1617377438000}
{"id":2,"name":"another","team_email":"another@apache.org","last_modified":1617377478000}
```
### With SSL

`mysql` container is started first in order to get generated `.pem` certificates from `/var/lib/mysql`

`keystore.jks` and `truststore.jks` are generated from these `.pem` certificates (see explanations [here](https://dev.mysql.com/doc/connector-j/5.1/en/connector-j-reference-using-ssl.html)):

```
keytool -importcert -alias MySQLCACert -noprompt -file /tmp/ca.pem -keystore /tmp/truststore.jks -storepass mypassword
# Convert the client key and certificate files to a PKCS #12 archive
openssl pkcs12 -export -in /tmp/client-cert.pem -inkey /tmp/client-key.pem -name "mysqlclient" -passout pass:mypassword -out /tmp/client-keystore.p12
# Import the client key and certificate into a Java keystore:
eytool -importkeystore -srckeystore /tmp/client-keystore.p12 -srcstoretype pkcs12 -srcstorepass mypassword -destkeystore /tmp/keystore.jks -deststoretype JKS -deststorepass mypassword
```

#### With SSL encryption

We use db user `userssl` to be sure SSL encryption is required:

```sql
-- used for ssl case
GRANT ALL PRIVILEGES ON *.* TO 'userssl'@'%' IDENTIFIED BY 'password' REQUIRE SSL;
```

`connect` container is configured with truststore:

```
      KAFKA_OPTS: -Djavax.net.ssl.trustStore=/etc/kafka/secrets/truststore.jks
                  -Djavax.net.ssl.trustStorePassword=mypassword
```

connection.url is:

```json
"connection.url": "jdbc:mysql://mysql:3306/db?user=userssl&password=password&verifyServerCertificate=true&useSSL=true&requireSSL=true&enabledTLSProtocols=TLSv1,TLSv1.1,TLSv1.2,TLSv1.3"
```

#### With SSL encryption + Mutual TLS auth

We use db user `usermtls` to be sure client certificate is required:

```sql
-- used for mtls case
GRANT ALL PRIVILEGES ON *.* TO 'usermtls'@'%' IDENTIFIED BY 'password' REQUIRE X509;
```

`connect` container is configured with truststore **and** keystore:

```
      KAFKA_OPTS: -Djavax.net.ssl.trustStore=/etc/kafka/secrets/truststore.jks
                  -Djavax.net.ssl.trustStorePassword=mypassword
                  -Djavax.net.ssl.keyStore=/etc/kafka/secrets/keystore.jks
                  -Djavax.net.ssl.keyStorePassword=mypassword
```

connection.url is:

```json
"connection.url": "jdbc:mysql://mysql:3306/db?user=usermtls&password=password&verifyServerCertificate=true&useSSL=true&requireSSL=true&enabledTLSProtocols=TLSv1,TLSv1.1,TLSv1.2,TLSv1.3"
```

N.B: Control Center is reachable at [http://127.0.0.1:9021](http://127.0.0.1:9021])