# JDBC SQL Server source connector



## Objective

Quickly test [JDBC SQL Server](https://docs.confluent.io/current/connect/kafka-connect-jdbc/source-connector/index.html#kconnect-long-jdbc-source-connector) connector.




## How to run

Without SSL:

```
$ playground run -f sqlserver-jtds<use tab key to activate fzf completion (see https://kafka-docker-playground.io/#/cli?id=%e2%9a%a1-setup-completion), otherwise use full path, or relative path> (with [JTDS](http://jtds.sourceforge.net) driver)

$ playground run -f sqlserver-microsoft<use tab key to activate fzf completion (see https://kafka-docker-playground.io/#/cli?id=%e2%9a%a1-setup-completion), otherwise use full path, or relative path> (with [Microsoft](https://docs.microsoft.com/en-us/sql/connect/jdbc/microsoft-jdbc-driver-for-sql-server) driver)
```

with SSL encryption:

```
$ playground run -f sqlserver-jtds-ssl<use tab key to activate fzf completion (see https://kafka-docker-playground.io/#/cli?id=%e2%9a%a1-setup-completion), otherwise use full path, or relative path> (with [JTDS](http://jtds.sourceforge.net) driver)

$ playground run -f sqlserver-microsoft-ssl<use tab key to activate fzf completion (see https://kafka-docker-playground.io/#/cli?id=%e2%9a%a1-setup-completion), otherwise use full path, or relative path> (with [Microsoft](https://docs.microsoft.com/en-us/sql/connect/jdbc/microsoft-jdbc-driver-for-sql-server) driver)
```

## Details of what the script is doing

Load inventory.sql to SQL Server

```bash
$ cat ../../connect/connect-jdbc-sqlserver-source/inventory.sql | docker exec -i sqlserver bash -c '/opt/mssql-tools/bin/sqlcmd -U sa -P Password!'
```

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
                    "topic.prefix": "sqlserver-jtds-",
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
     - ../../connect/connect-jdbc-sqlserver-source/ssl/mssql.conf:/var/opt/mssql/mssql.conf
     - ../../connect/connect-jdbc-sqlserver-source/ssl/mssql.pem:/tmp/mssql.pem
     - ../../connect/connect-jdbc-sqlserver-source/ssl/mssql.key:/tmp/mssql.key
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
               "connector.class": "io.confluent.connect.jdbc.JdbcSourceConnector",
               "tasks.max": "1",
               "connection.url": "jdbc:jtds:sqlserver://sqlserver:1433/testDB;ssl=require",
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
     http://localhost:8083/connectors/sqlserver-source-ssl/config | jq .
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
               "connector.class": "io.confluent.connect.jdbc.JdbcSourceConnector",
               "tasks.max": "1",
               "connection.url": "jdbc:sqlserver://sqlserver:1433;databaseName=testDB;encrypt=true;trustServerCertificate=false;trustStore=/tmp/truststore.jks;trustStorePassword=confluent;",
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
     http://localhost:8083/connectors/sqlserver-source-ssl/config | jq .
```

Insert one more row:

```bash
$ docker exec -i sqlserver /opt/mssql-tools/bin/sqlcmd -U sa -P Password! << EOF
USE testDB;
INSERT INTO customers(first_name,last_name,email) VALUES ('Pam','Thomas','pam@office.com');
GO
EOF
```

Verifying topic `sqlserver-customers`


```bash
playground topic consume --topic sqlserver-customers --min-expected-messages 5 --timeout 60
```

Results:

```json
{"id":1001,"first_name":"Sally","last_name":"Thomas","email":"sally.thomas@acme.com"}
{"id":1002,"first_name":"George","last_name":"Bailey","email":"gbailey@foobar.com"}
{"id":1003,"first_name":"Edward","last_name":"Walker","email":"ed@walker.com"}
{"id":1004,"first_name":"Anne","last_name":"Kretchmar","email":"annek@noanswer.org"}
{"id":1005,"first_name":"Pam","last_name":"Thomas","email":"pam@office.com"}
```


N.B: Control Center is reachable at [http://127.0.0.1:9021](http://127.0.0.1:9021])
