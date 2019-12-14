# Kudu Source connector

## Objective

Quickly test [Kudu Source](https://docs.confluent.io/current/connect/kafka-connect-kudu/source-connector/index.html#quick-start) connector.

## Pre-requisites

* `docker-compose` (example `brew cask install docker`)
* `jq` (example `brew install jq`)
* Download Impala JDBC Driver `ImpalaJDBC42.jar`from this [page](https://www.oracle.com/technetwork/java/javase/jdbc/index.html) and place it in `./ImpalaJDBC42.jar`

## How to run

Simply run:

```
$ ./kudu-source.sh
```

## Details of what the script is doing

Create Database test and table accounts in kudu

```bash
$ docker exec -i kudu impala-shell -i localhost:21000 -l -u kudu --ldap_password_cmd="echo -n secret" --auth_creds_ok_in_clear << EOF
CREATE DATABASE test;
USE test;
CREATE TABLE accounts (
     id BIGINT,
     name STRING,
     PRIMARY KEY(id)
     ) PARTITION BY HASH PARTITIONS 16 STORED AS KUDU TBLPROPERTIES ("kudu.master_addresses" = "127.0.0.1","kudu.num_tablet_replicas" = "1");
INSERT INTO accounts (id, name) VALUES (1, 'alice');
INSERT INTO accounts (id, name) VALUES (2, 'bob');
EOF
```

The connector is created with:

```bash
$ docker exec connect \
     curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
                    "connector.class": "io.confluent.connect.kudu.KuduSourceConnector",
                    "tasks.max": "1",
                    "impala.server": "kudu",
                    "impala.port": "21050",
                    "kudu.database": "test",
                    "mode": "incrementing",
                    "incrementing.column.name": "id",
                    "topic.prefix": "test-kudu-",
                    "table.whitelist": "accounts",
                    "key.converter": "io.confluent.connect.avro.AvroConverter",
                    "key.converter.schema.registry.url": "http://schema-registry:8081",
                    "value.converter": "io.confluent.connect.avro.AvroConverter",
                    "value.converter.schema.registry.url": "http://schema-registry:8081",
                    "impala.ldap.password": "secret",
                    "impala.ldap.user": "kudu",
                    "confluent.license": "",
                    "confluent.topic.bootstrap.servers": "broker:9092",
                    "confluent.topic.replication.factor": "1"
          }' \
     http://localhost:8083/connectors/kudu-source/config | jq .
```

Verify we have received the data in `test-kudu-accounts` topic:

```bash
$ docker exec schema-registry kafka-avro-console-consumer -bootstrap-server broker:9092 --topic test-kudu-accounts --from-beginning --max-messages 2
```

Results:

```json
{"id":{"long":1},"name":{"string":"alice"}}
{"id":{"long":2},"name":{"string":"bob"}}
```

N.B: Control Center is reachable at [http://127.0.0.1:9021](http://127.0.0.1:9021])
