# JDBC Oracle 11 Sink connector

![asciinema](https://github.com/vdesabou/gifs/blob/master/connect/connect-jdbc-oracle11-sink/asciinema.gif?raw=true)

## Objective

Quickly test [JDBC Sink](https://docs.confluent.io/current/connect/kafka-connect-jdbc/sink-connector/index.html#quick-start) connector with Oracle 11.



* If you're using a JDBC connector version before `10.0.0`, you need to download Oracle Database 11g Release 2 (11.2.0.4) JDBC driver `ojdbc6.jar`from this [page](https://www.oracle.com/database/technologies/jdbcdriver-ucp-downloads.html) and place it in `./ojdbc6.jar`

## How to run

Simply run:

```
$ ./oracle11-sink.sh
```

## Details of what the script is doing

Create the sink connector with:

```bash
$ curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.confluent.connect.jdbc.JdbcSinkConnector",
                    "tasks.max": "1",
                    "connection.user": "myuser",
                    "connection.password": "mypassword",
                    "connection.url": "jdbc:oracle:thin:@oracle:1521/XE",
                    "topics": "ORDERS",
                    "auto.create": "true",
                    "insert.mode":"insert",
                    "auto.evolve":"true"
          }' \
     http://localhost:8083/connectors/oracle-sink/config | jq .
```

Sending messages to topic `ORDERS`:

```bash
$ docker exec -i connect kafka-avro-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic ORDERS --property value.schema='{"type":"record","name":"myrecord","fields":[{"name":"id","type":"int"},{"name":"product", "type": "string"}, {"name":"quantity", "type": "int"}, {"name":"price",
"type": "float"}]}' << EOF
{"id": 999, "product": "foo", "quantity": 100, "price": 50}
EOF
```

Show content of `ORDERS` table:

```bash
$ docker exec oracle bash -c "export ORACLE_HOME=/u01/app/oracle/product/11.2.0/xe/;export ORACLE_SID=xe;echo 'select * from ORDERS;' | /u01/app/oracle/product/11.2.0/xe/bin/sqlplus myuser/mypassword@//localhost:1521/XE"
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

N.B: Control Center is reachable at [http://127.0.0.1:9021](http://127.0.0.1:9021])
