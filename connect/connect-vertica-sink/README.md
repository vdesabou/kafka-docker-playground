# Vertica sink connector

![asciinema](asciinema.gif)

## Objective

Quickly test [Vertica](https://docs.confluent.io/current/connect/kafka-connect-vertica/sink/index.html#quick-start) connector.




## How to run

Simply run:

```
$ ./vertica-sink.sh
```

## Details of what the script is doing


Create the table and insert data.

```bash
$ docker exec -i vertica /opt/vertica/bin/vsql -hlocalhost -Udbadmin << EOF
create table mytable(f1 varchar(20));
EOF
```


Sending messages to topic mytable

```bash
$ seq -f "{\"f1\": \"value%g\"}" 10 | docker exec -i connect kafka-avro-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic mytable --property value.schema='{"type":"record","name":"myrecord","fields":[{"name":"f1","type":"string"}]}'
```

Creating Vertica sink connector

```bash
$ docker exec connect \
     curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class" : "io.confluent.vertica.VerticaSinkConnector",
                    "tasks.max" : "1",
                    "vertica.database": "docker",
                    "vertica.host": "vertica",
                    "vertica.port": "5433",
                    "vertica.username": "dbadmin",
                    "vertica.password": "",
                    "topics": "mytable",
                    "confluent.topic.bootstrap.servers": "broker:9092",
                    "confluent.topic.replication.factor": "1"
          }' \
     http://localhost:8083/connectors/vertica-sink/config | jq .
```


Check data is in Vertica

```bash
$ docker exec -i vertica /opt/vertica/bin/vsql -hlocalhost -Udbadmin << EOF
select * from mytable;
EOF
```

Results:

```
   f1
---------
 value10
 value1
 value5
 value3
 value8
 value6
 value9
 value4
 value7
 value2
(10 rows)
```

N.B: Control Center is reachable at [http://127.0.0.1:9021](http://127.0.0.1:9021])
