# JDBC Sybase sink connector

## Objective

Quickly test [JDBC Sybase](https://docs.confluent.io/current/connect/kafka-connect-jdbc/sink-connector/index.html#kconnect-long-jdbc-sink-connector) sink connector.


## How to run

Simply run:

```
$ playground run -f sybase-sink<tab>
```

## Details of what the script is doing

Create JDBC Sybase sink connector

```bash
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.confluent.connect.jdbc.JdbcSinkConnector",
               "tasks.max": "1",
               "connection.url": "jdbc:jtds:sybase://sybase:5000",
               "connection.user": "sa",
               "connection.password": "password",
               "topics": "orders",
               "auto.create": "true"
          }' \
     http://localhost:8083/connectors/sybase-sink/config | jq .
````

Sending messages to topic orders

```bash
docker exec -i connect kafka-avro-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic orders --property value.schema='{"type":"record","name":"myrecord","fields":[{"name":"id","type":"int"},{"name":"product", "type": "string"}, {"name":"quantity", "type": "int"}, {"name":"price","type": "float"}]}' << EOF
{"id": 999, "product": "foo", "quantity": 100, "price": 50}
EOF
```

Show content of orders table:

```bash
docker exec -i sybase /sybase/isql -S -Usa -Ppassword << EOF
select * from orders
GO
EOF
```

```
 id         
         product                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                         
         quantity    price                       
 -----------
         --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
         ----------- --------------------------- 
         999
         foo                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                             
                 100                   50.000000 

(1 row affected)
```

N.B: Control Center is reachable at [http://127.0.0.1:9021](http://127.0.0.1:9021])
