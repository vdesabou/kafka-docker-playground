# Singlestore sink connector

## Objective

Quickly test [Singlestore](https://github.com/memsql/singlestore-kafka-connector) connector.


## How to run

Simply run:

```
$ playground run -f singlestore-sink<use tab key to activate fzf completion (see https://kafka-docker-playground.io/#/cli?id=%e2%9a%a1-setup-completion), otherwise use full path, or correct relative path>
```

## Details of what the script is doing


Creating 'test' SingleStore database...

```bash
docker exec singlestore memsql -u root -proot -e "create database if not exists test;"
```

Sending messages to topic mytable

```bash
seq -f "{\"f1\": \"value%g\"}" 10 | docker exec -i connect kafka-avro-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic mytable --property value.schema='{"type":"record","name":"myrecord","fields":[{"name":"f1","type":"string"}]}'
```

Creating Singlestore sink connector

```bash
playground connector create-or-update --connector singlestore-sink  << EOF
{
               "connector.class":"com.singlestore.kafka.SingleStoreSinkConnector",
               "tasks.max":"1",
               "topics":"mytable",
               "connection.ddlEndpoint" : "singlestore:3306",
               "connection.database" : "test",
               "connection.user" : "root",
               "connection.password" : "root"
          }
EOF
```

sleep 10

Check data is in Singlestore

```bash
docker exec -i singlestore memsql -u root -proot > /tmp/result.log  2>&1 <<-EOF
use test;
show tables;
select * from mytable;
EOF
```

Results:

```
singlestore-client: [Warning] Using a password on the command line interface can be insecure.
Tables_in_test
kafka_connect_transaction_metadata
mytable
f1
value1
value10
value2
value3
value4
value5
value6
value7
value8
value9
value1
value10
```

N.B: Control Center is reachable at [http://127.0.0.1:9021](http://127.0.0.1:9021])
