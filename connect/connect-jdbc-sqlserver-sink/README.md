# JDBC SQL Server sink connector



## Objective

Quickly test [JDBC SQL Server](https://docs.confluent.io/current/connect/kafka-connect-jdbc/sink-connector/index.html#kconnect-long-jdbc-sink-connector) sink connector.




## How to run

Without SSL:

```
$ just use <playground run> command and search for sqlserver-jtds-sink.sh in this folder

$ just use <playground run> command and search for sqlserver-microsoft-sink.sh in this folder
```

with SSL encryption:

```
$ just use <playground run> command and search for sqlserver-jtds-sink-ssl.sh in this folder

$ just use <playground run> command and search for sqlserver-microsoft-sink-ssl.sh in this folder
```

## Details of what the script is doing

### JTDS JDBC driver

Creating JDBC SQL Server (with JTDS) source connector

#### Without SSL

```bash
$ curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.confluent.connect.jdbc.JdbcSourceConnector",
                    "tasks.max": "1",
                    "connection.url": "jdbc:jtds:sqlserver://sqlserver:1433/testDB",
                    "connection.user": "sa",
                    "connection.password": "Password!",
                    "table.whitelist": "customers",
                    "mode": "incrementing",
                    "incrementing.column.name": "id",
                    "topic.prefix": "sqlserver-",
                    "validate.non.null":"false",
                    "errors.log.enable": "true",
                    "errors.log.include.messages": "true"
          }' \
     http://localhost:8083/connectors/sqlserver-source/config | jq .
```

#### with SSL encryption

Create a self-signed certificate:

```bash
$ openssl req -x509 -nodes -newkey rsa:2048 -subj '/CN=sqlserver' -keyout /tmp/mssql.key -out /tmp/mssql.pem -days 365
```

Creating JKS from pem files

```bash
$ keytool -importcert -alias MSSQLCACert -noprompt -file /tmp/mssql.pem -keystore /tmp/truststore.jks -storepass confluent
```

`mssql.conf` is set with:

```conf
[network]
tlscert = /tmp/mssql.pem
tlskey = /tmp/mssql.key
tlsprotocols = 1.2
forceencryption = 1
```

With volumes on `sqlserver`:

```yml
volumes:
     - ../../connect/connect-jdbc-sqlserver-sink/ssl/mssql.conf:/var/opt/mssql/mssql.conf
     - ../../connect/connect-jdbc-sqlserver-sink/ssl/mssql.pem:/tmp/mssql.pem
     - ../../connect/connect-jdbc-sqlserver-sink/ssl/mssql.key:/tmp/mssql.key
```

On `connect` container we have:

```yml
KAFKA_OPTS: -Djavax.net.ssl.trustStore=/tmp/truststore.jks
          -Djavax.net.ssl.trustStorePassword=confluent
```

```bash
$ curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.confluent.connect.jdbc.JdbcSinkConnector",
                    "tasks.max": "1",
                    "connection.url": "jdbc:jtds:sqlserver://sqlserver:1433;ssl=require",
                    "connection.user": "sa",
                    "connection.password": "Password!",
                    "topics": "orders",
                    "auto.create": "true"
          }' \
     http://localhost:8083/connectors/sqlserver-sink-ssl/config | jq .
```

### Microsoft JDBC driver

#### Without SSL

```bash
$ curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.confluent.connect.jdbc.JdbcSourceConnector",
                    "tasks.max": "1",
                    "connection.url": "jdbc:sqlserver://sqlserver:1433;databaseName=testDB;encrypt=false",
                    "connection.user": "sa",
                    "connection.password": "Password!",
                    "table.whitelist": "customers",
                    "mode": "incrementing",
                    "incrementing.column.name": "id",
                    "topic.prefix": "sqlserver-",
                    "validate.non.null":"false",
                    "errors.log.enable": "true",
                    "errors.log.include.messages": "true"
          }' \
     http://localhost:8083/connectors/sqlserver-source/config | jq .

```

#### with SSL encryption

```bash
$ curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.confluent.connect.jdbc.JdbcSinkConnector",
               "tasks.max": "1",
               "connection.url": "jdbc:sqlserver://sqlserver:1433;encrypt=true;trustServerCertificate=false;trustStore=/tmp/truststore.jks;trustStorePassword=confluent;",
               "connection.user": "sa",
               "connection.password": "Password!",
               "topics": "orders",
               "auto.create": "true"
          }' \
     http://localhost:8083/connectors/sqlserver-sink-ssl/config | jq .
```

Sending messages to topic orders

```bash
$ docker exec -i connect kafka-avro-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic orders --property value.schema='{"type":"record","name":"myrecord","fields":[{"name":"id","type":"int"},{"name":"product", "type": "string"}, {"name":"quantity", "type": "int"}, {"name":"price","type": "float"}]}' << EOF
{"id": 999, "product": "foo", "quantity": 100, "price": 50}
EOF
```

Show content of `orders` table:

```bash
$ ocker exec -i sqlserver /opt/mssql-tools/bin/sqlcmd -U sa -P Password! << EOF
select * from orders
GO
EOF
```


Results:

```
product                                                                                                                                                                                                                                                          quantity    price          id
---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- ----------- -------------- -----------
foo                                                                                                                                                                                                                                                                      100           50.0         999

(1 rows affected)
```


N.B: Control Center is reachable at [http://127.0.0.1:9021](http://127.0.0.1:9021])
