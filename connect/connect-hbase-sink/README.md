# HBase Sink connector

![asciinema](https://github.com/vdesabou/gifs/blob/master/connect/connect-hbase-sink/asciinema.gif?raw=true)

## Objective

Quickly test [HBase Sink](https://docs.confluent.io/current/connect/kafka-connect-hbase/index.html#quick-start) connector.




## How to run

Simply run:

```
$ ./hbase-sink.sh
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

```
$ docker exec -it hbase /bin/bash entrypoint.sh
```

Then type `scan 'example_table'`

Results:

```bash
hbase(main):001:0> scan 'example_table'
ROW                       COLUMN+CELL
 key1                     column=hbase-test:KAFKA_VALUE, timestamp=1575994573539, value=value1
 key2                     column=hbase-test:KAFKA_VALUE, timestamp=1575994573545, value=value2
 key3                     column=hbase-test:KAFKA_VALUE, timestamp=1575994573551, value=value3
3 row(s) in 0.3860 seconds
```

Type `exit`to close the HBase shell.



N.B: Control Center is reachable at [http://127.0.0.1:9021](http://127.0.0.1:9021])
