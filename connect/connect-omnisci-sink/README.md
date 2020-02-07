# OmniSci Sink connector

![asciinema](asciinema.gif)

## Objective

Quickly test [OmniSci Sink](https://docs.confluent.io/current/connect/kafka-connect-omnisci/index.html#kconnect-long-omnisci-sink-connector)) connector.

## Pre-requisites

* `docker-compose` (example `brew cask install docker`)



## How to run

Simply run:

```
$ ./omnisci-sink.sh
```

## Details of what the script is doing

Sending messages to topic orders

```bash
$ docker exec -i connect kafka-avro-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic orders --property value.schema='{"type":"record","name":"myrecord","fields":[{"name":"id","type":"int"},{"name":"product", "type": "string"}, {"name":"quantity", "type": "int"}, {"name":"price",
 "type": "float"}]}' << EOF
{"id": 999, "product": "foo", "quantity": 100, "price": 50}
EOF
```

Creating OmniSci sink connector

```bash
$ docker exec connect \
     curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.confluent.connect.omnisci.OmnisciSinkConnector",
                    "tasks.max" : "1",
                    "topics": "orders",
                    "connection.database": "omnisci",
                    "connection.port": "6274",
                    "connection.host": "omnisci",
                    "connection.user": "admin",
                    "connection.password": "HyperInteractive",
                    "confluent.topic.bootstrap.servers": "broker:9092",
                    "confluent.topic.replication.factor": "1",
                    "auto.create": "true"
          }' \
     http://localhost:8083/connectors/omnisci-sink/config | jq .
```

Verify data is in OmniSci

```bash
$ docker exec -i omnisci /omnisci/bin/omnisql -p HyperInteractive << EOF
select * from orders;
EOF
```

Results:

```
User admin connected to database omnisci
product|quantity|price|id
foo|100|50|999
User admin disconnected from database omnisci
```

N.B: Control Center is reachable at [http://127.0.0.1:9021](http://127.0.0.1:9021])
