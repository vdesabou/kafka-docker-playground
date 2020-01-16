# JDBC Vertica sink connector

## Objective

Quickly test [JDBC Sink](https://docs.confluent.io/current/connect/kafka-connect-jdbc/sink-connector/index.html#jdbc-sink-connector-for-cp) connector with Vertica.

## Pre-requisites

* `docker-compose` (example `brew cask install docker`)



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
$ seq -f "{\"f1\": \"value%g\"}" 10 | docker exec -i schema-registry kafka-avro-console-producer --broker-list broker:9092 --topic mytable --property value.schema='{"type":"record","name":"myrecord","fields":[{"name":"f1","type":"string"}]}'
```

Creating JDBC Vertica sink connector

```bash
$ docker exec connect \
     curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class" : "io.confluent.connect.jdbc.JdbcSinkConnector",
                    "tasks.max" : "1",
                    "connection.url": "jdbc:vertica://vertica:5433/docker?user=dbadmin&password=",
                    "auto.create": "true",
                    "topics": "mytable"
          }' \
     http://localhost:8083/connectors/jdbc-vertica-sink/config | jq_docker_cli .
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
