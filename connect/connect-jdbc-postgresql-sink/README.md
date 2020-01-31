# JDBC PostgreSQL sink connector

## Objective

Quickly test [JDBC PostGreSQL](https://docs.confluent.io/current/connect/kafka-connect-jdbc/sink-connector/index.html#kconnect-long-jdbc-sink-connector) connector.

## Pre-requisites

* `docker-compose` (example `brew cask install docker`)



## How to run

Simply run:

```
$ ./postgres-sink.sh
```

## Details of what the script is doing

Creating JDBC PostgreSQL sink connector

```bash
$ docker exec connect \
     curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.confluent.connect.jdbc.JdbcSinkConnector",
                    "tasks.max": "1",
                    "connection.url": "jdbc:postgresql://postgres/postgres?user=postgres&password=postgres&ssl=false",
                    "topics": "orders",
                    "auto.create": "true"
          }' \
     http://localhost:8083/connectors/postgres-sink/config | jq .
```

Sending messages to topic orders

```bash
$ docker exec -i connect kafka-avro-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic orders --property value.schema='{"type":"record","name":"myrecord","fields":[{"name":"id","type":"int"},{"name":"product", "type": "string"}, {"name":"quantity", "type": "int"}, {"name":"price",
"type": "float"}]}' << EOF
{"id": 999, "product": "foo", "quantity": 100, "price": 50}
EOF
```

Show content of ORDERS table:

```bash
$ docker exec postgres bash -c "psql -U postgres -d postgres -c 'SELECT * FROM ORDERS'"
```

Results:

```
 product | quantity | price | id
---------+----------+-------+-----
 foo     |      100 |    50 | 999
 ```

N.B: Control Center is reachable at [http://127.0.0.1:9021](http://127.0.0.1:9021])
