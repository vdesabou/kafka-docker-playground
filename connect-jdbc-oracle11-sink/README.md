# JDBC Oracle 11 Sink connector

## Objective

Quickly test [JDBC Sink](https://docs.confluent.io/current/connect/kafka-connect-jdbc/sink-connector/index.html#quick-start) connector with Oracle 11.

## Pre-requisites

* `docker-compose` (example `brew cask install docker`)
* `jq` (example `brew install jq`)

* Download Oracle Database 11g Release 2 (11.2.0.4) JDBC driver `ojdbc6.jar`from this [page](https://www.oracle.com/database/technologies/jdbcdriver-ucp-downloads.html) and place it in `./ojdbc6.jar`

## How to run

Simply run:

```
$ ./oracle11-sink.sh
```

## Details of what the script is doing

Create the sink connector with:

```bash
$ docker container exec connect \
     curl -X POST \
     -H "Content-Type: application/json" \
     --data '{
               "name": "oracle-sink2",
               "config": {
                    "connector.class": "io.confluent.connect.jdbc.JdbcSinkConnector",
                    "tasks.max": "1",
                    "connection.user": "myuser",
                    "connection.password": "mypassword",
                    "connection.url": "jdbc:oracle:thin:@oracle:1521/XE",
                    "topics": "ORDERS",
                    "auto.create": "true",
                    "insert.mode":"insert",
                    "auto.evolve":"true"
          }}' \
     http://localhost:8083/connectors | jq .
```

Sending messages to topic `ORDERS`:

```bash
$ docker container exec -i schema-registry kafka-avro-console-producer --broker-list broker:9092 --topic ORDERS --property value.schema='{"type":"record","name":"myrecord","fields":[{"name":"id","type":"int"},{"name":"product", "type": "string"}, {"name":"quantity", "type": "int"}, {"name":"price",
"type": "float"}]}' << EOF
{"id": 999, "product": "foo", "quantity": 100, "price": 50}
EOF
```

Show content of ORDERS table:

```bash
$ docker container exec oracle bash -c "export ORACLE_HOME=/u01/app/oracle/product/11.2.0/xe/;export ORACLE_SID=xe;echo 'select * from ORDERS;' | /u01/app/oracle/product/11.2.0/xe/bin/sqlplus myuser/mypassword@//localhost:1521/XE"
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
