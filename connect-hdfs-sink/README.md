# HDFS 2 Sink connector

## Objective

Quickly test [HDFS 2 Sink](https://docs.confluent.io/current/connect/kafka-connect-hdfs/index.html) connector.

## How to run

Simply run:

```
$ ./hdfs.sh
```

## Details

The connector is created with:

```
docker-compose exec connect \
     curl -X POST \
     -H "Content-Type: application/json" \
     --data '{
        "name": "hdfs-sink",
        "config": {
               "connector.class":"io.confluent.connect.hdfs.HdfsSinkConnector",
               "tasks.max":"1",
               "topics":"test_hdfs",
               "hdfs.url":"hdfs://hadoop:9000",
               "flush.size":"3",
               "hadoop.conf.dir":"/usr/local/hadoop-2.7.1/etc/hadoop/",
               "partitioner.class":"io.confluent.connect.hdfs.partitioner.FieldPartitioner",
               "partition.field.name":"f1",
               "rotate.interval.ms":"120000",
               "hadoop.home":"/usr/local/hadoop-2.7.1/share/hadoop/common/",
               "logs.dir":"/tmp",
               "schema.compatibility":"BACKWARD"
          }}' \
     http://localhost:8083/connectors | jq .
```

Messages are sent to `test_hdfs` topic using:

```
seq -f "{\"f1\": \"value%g\"}" 10 | docker container exec -i schema-registry kafka-avro-console-producer --broker-list broker:9092 --topic test_hdfs --property value.schema='{"type":"record","name":"myrecord","fields":[{"name":"f1","type":"string"}]}'
```

Control Center is reachable at `http://localhost:9021`
