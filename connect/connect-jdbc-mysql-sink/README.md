# JDBC MySQL Sink connector



## Objective

Quickly test [JDBC Sink](https://docs.confluent.io/current/connect/kafka-connect-jdbc/sink-connector/index.html#quick-start) connector with MySQL.

## How to run

Without SSL:

```
$ playground run -f mysql-sink<use tab key to activate [fzf completion](https://kafka-docker-playground.io/#/cli?id=%e2%9a%a1-setup-completion) (otherwise use full path, i.e *not relative path*>
```

with SSL encryption:

```
$ playground run -f mysql-sink-ssl<use tab key to activate [fzf completion](https://kafka-docker-playground.io/#/cli?id=%e2%9a%a1-setup-completion) (otherwise use full path, i.e *not relative path*>
```

with SSL encryption + Mutual TLS authentication:

```
$ playground run -f mysql-sink-mtls<use tab key to activate [fzf completion](https://kafka-docker-playground.io/#/cli?id=%e2%9a%a1-setup-completion) (otherwise use full path, i.e *not relative path*>
```

## Details of what the script is doing

### Without SSL

Creating MySQL sink connector

```bash
$ curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.confluent.connect.jdbc.JdbcSinkConnector",
                    "tasks.max": "1",
                    "connection.url": "jdbc:mysql://mysql:3306/db?user=user&password=password&useSSL=false",
                    "topics": "orders",
                    "auto.create": "true"
          }' \
     http://localhost:8083/connectors/mysql-sink/config | jq .
```

Sending messages to topic orders

```bash
$ docker exec -i connect kafka-avro-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic orders --property value.schema='{"type":"record","name":"myrecord","fields":[{"name":"id","type":"int"},{"name":"product", "type": "string"}, {"name":"quantity", "type": "int"}, {"name":"price","type": "float"}]}' << EOF
{"id": 999, "product": "foo", "quantity": 100, "price": 50}
EOF
```


Describing the `orders` table in DB `db`:

```bash
$ docker exec mysql bash -c "mysql --user=root --password=password --database=db -e 'describe orders'"
```

Results:
```
Field   Type    Null    Key     Default Extra
product varchar(256)    NO              NULL
quantity        int(11) NO              NULL
price   float   NO              NULL
id      int(11) NO              NULL
```

Show content of `orders` table:

```bash
$ docker exec mysql bash -c "mysql --user=root --password=password --database=db -e 'select * from orders'"
```

Results:

```
product quantity        price   id
foo     100     50      999
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
