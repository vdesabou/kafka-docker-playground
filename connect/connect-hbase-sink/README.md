# HBase Sink connector



## Objective

Quickly test [HBase Sink](https://docs.confluent.io/current/connect/kafka-connect-hbase/index.html#quick-start) connector.

## How to run

Simply run:

```
$ playground run -f hbase-sink-1.2.0<use tab key to activate fzf completion (see https://kafka-docker-playground.io/#/cli?id=%e2%9a%a1-setup-completion), otherwise use full path, or correct relative path>
```

or

```
$ playground run -f hbase-sink-2.2.4<use tab key to activate fzf completion (see https://kafka-docker-playground.io/#/cli?id=%e2%9a%a1-setup-completion), otherwise use full path, or correct relative path>
```

## Details of what the script is doing

Sending messages to topic hbase-test

```bash
$ docker exec -i broker kafka-console-producer --broker-list broker:9092 --topic hbase-test --property parse.key=true --property key.separator=, << EOF
key1,value1
key2,value2
key3,value3
EOF
```

Creating HBase sink connector

```bash
$ curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.confluent.connect.hbase.HBaseSinkConnector",
               "tasks.max": "1",
               "key.converter":"org.apache.kafka.connect.storage.StringConverter",
               "value.converter":"org.apache.kafka.connect.storage.StringConverter",
               "confluent.topic.bootstrap.servers": "broker:9092",
               "confluent.topic.replication.factor":1,
               "hbase.zookeeper.quorum": "hbase",
               "hbase.zookeeper.property.clientPort": "2181",
               "auto.create.tables": "true",
               "auto.create.column.families": "true",
               "table.name.format": "example_table",
               "topics": "hbase-test"
          }' \
     http://localhost:8083/connectors/hbase-sink/config | jq .
```

Verify data is in HBase:

```bash
docker exec -i hbase hbase shell > /tmp/result.log  2>&1 <<-EOF
scan 'example_table'
EOF
cat /tmp/result.log
```

Results:

```bash
HBase Shell; enter 'help<RETURN>' for list of supported commands.
Type "exit<RETURN>" to leave the HBase Shell
Version 1.3.1, r930b9a55528fe45d8edce7af42fef2d35e77677a, Thu Apr  6 19:36:54 PDT 2017

scan 'example_table'
ROW  COLUMN+CELL
 key1 column=hbase-test:KAFKA_VALUE, timestamp=1618586660024, value=value1
 key2 column=hbase-test:KAFKA_VALUE, timestamp=1618586660029, value=value2
 key3 column=hbase-test:KAFKA_VALUE, timestamp=1618586660031, value=value3
3 row(s) in 0.2020 seconds
```


N.B: Control Center is reachable at [http://127.0.0.1:9021](http://127.0.0.1:9021])
