# Kudu Sink connector

## Objective

Quickly test [Kudu Sink](https://docs.confluent.io/current/connect/kafka-connect-kudu/sink-connector/index.html#quick-start) connector.

## Pre-requisites

* `docker-compose` (example `brew cask install docker`)
* `jq` (example `brew install jq`)
* Download Impala JDBC Driver `ImpalaJDBC42.jar`from this [page](https://www.oracle.com/technetwork/java/javase/jdbc/index.html) and place it in `./ImpalaJDBC42.jar`

## How to run

Simply run:

```
$ ./kudu-sink.sh
```

## Details of what the script is doing

Create Database test in kudu:

```bash
$ docker exec -i kudu impala-shell -i localhost:21000 -l -u kudu --ldap_password_cmd="echo -n secret" --auth_creds_ok_in_clear << EOF
CREATE DATABASE test;
EOF
```

The connector is created with:

```bash
$ docker exec connect \
     curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
                    "connector.class": "io.confluent.connect.kudu.KuduSinkConnector",
                    "tasks.max": "1",
                    "topics": "orders",
                    "impala.server": "kudu",
                    "impala.port": "21050",
                    "kudu.database": "test",
                    "auto.create": "true",
                    "pk.mode":"record_value",
                    "pk.fields":"id",
                    "key.converter": "io.confluent.connect.avro.AvroConverter",
                    "key.converter.schema.registry.url": "http://schema-registry:8081",
                    "value.converter": "io.confluent.connect.avro.AvroConverter",
                    "value.converter.schema.registry.url": "http://schema-registry:8081",
                    "impala.ldap.password": "secret",
                    "impala.ldap.user": "kudu",
                    "kudu.tablet.replicas": "1",
                    "confluent.license": "",
                    "confluent.topic.bootstrap.servers": "broker:9092",
                    "confluent.topic.replication.factor": "1"
          }' \
     http://localhost:8083/connectors/kudu-sink/config | jq .
```

Sending messages to topic orders:

```bash
$ docker exec -i schema-registry kafka-avro-console-producer --broker-list broker:9092 --topic orders --property value.schema='{"type":"record","name":"myrecord","fields":[{"name":"id","type":"int"},{"name":"product", "type": "string"}, {"name":"quantity", "type": "int"}, {"name":"price",
"type": "float"}]}' << EOF
{"id": 999, "product": "foo", "quantity": 100, "price": 50}
EOF
```


Verify data is in kudu `orders` table:

```bash
$ docker exec -i kudu impala-shell -i localhost:21000 -l -u kudu --ldap_password_cmd="echo -n secret" --auth_creds_ok_in_clear << EOF
USE test;
SELECT * from orders;
EOF
```

Results:

```
+-----+---------+----------+-------+
| id  | product | quantity | price |
+-----+---------+----------+-------+
| 999 | foo     | 100      | 50    |
+-----+---------+----------+-------+
Fetched 1 row(s) in 1.10s
```

N.B: Control Center is reachable at [http://127.0.0.1:9021](http://127.0.0.1:9021])
