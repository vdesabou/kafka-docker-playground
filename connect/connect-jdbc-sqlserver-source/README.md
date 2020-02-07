# JDBC SQL Server source connector

![asciinema](asciinema.gif)

## Objective

Quickly test [JDBC SQL Server](https://docs.confluent.io/current/connect/kafka-connect-jdbc/source-connector/index.html#kconnect-long-jdbc-source-connector) connector.




## How to run

Simply run:

```
$ ./sqlserver-jtds.sh (with [JTDS](http://jtds.sourceforge.net) driver)

$ ./sqlserver-microsoft.sh (with [Microsoft](https://docs.microsoft.com/en-us/sql/connect/jdbc/microsoft-jdbc-driver-for-sql-server) driver)
```

## Details of what the script is doing

Load inventory.sql to SQL Server

```bash
$ cat inventory.sql | docker exec -i sqlserver bash -c '/opt/mssql-tools/bin/sqlcmd -U sa -P Password!'
```

### JTDS JDBC driver

Creating JDBC SQL Server (with JTDS) source connector

```bash
$ docker exec connect \
     curl -X PUT \
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

### Microsoft JDBC driver

```bash
$ docker exec connect \
     curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.confluent.connect.jdbc.JdbcSourceConnector",
                    "tasks.max": "1",
                    "connection.url": "jdbc:sqlserver://sqlserver:1433;databaseName=testDB",
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
$ docker exec connect kafka-avro-console-consumer -bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic sqlserver-customers --from-beginning --max-messages 5
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
