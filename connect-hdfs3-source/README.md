# HDFS 3 Source connector

## Objective

Quickly test [HDFS 3 Source](https://docs.confluent.io/current/connect/kafka-connect-hdfs/hdfs3/source/index.html#kconnect-long-hdfs-3-source-connector) connector.

## Pre-requisites

* `docker-compose` (example `brew cask install docker`)
* `jq` (example `brew install jq`)
* `avro-tools` (example `brew install avro-tools`)


## How to run

Simply run:

```
$ ./hdfs3.sh
```

## Details of what the script is doing


Steps from [connect-hdfs3-sink](../connect-hdfs3-sink/README.md)


Creating HDFS Source connector:

```bash
$ docker exec connect \
     curl -X POST \
     -H "Content-Type: application/json" \
     --data '{
        "name": "hdfs3-source",
        "config": {
               "connector.class":"io.confluent.connect.hdfs3.Hdfs3SourceConnector",
               "tasks.max":"1",
               "hdfs.url":"hdfs://namenode:9000",
               "hadoop.conf.dir":"/etc/hadoop/",
               "hadoop.home":"/opt/hadoop-3.1.2/share/hadoop/common",
               "format.class" : "io.confluent.connect.hdfs3.format.avro.AvroFormat",
               "confluent.topic.bootstrap.servers": "broker:9092",
               "confluent.topic.replication.factor": "1",
               "transforms" : "AddPrefix",
               "transforms.AddPrefix.type" : "org.apache.kafka.connect.transforms.RegexRouter",
               "transforms.AddPrefix.regex" : ".*",
               "transforms.AddPrefix.replacement" : "copy_of_$0"
          }}' \
     http://localhost:8083/connectors | jq .
```

Verifying topic `copy_of_test_hdfs`:

```bash
$ docker exec schema-registry kafka-avro-console-consumer -bootstrap-server broker:9092 --topic copy_of_test_hdfs --from-beginning --max-messages 9
```

Results:

```
{"f1":"value1"}
{"f1":"value2"}
{"f1":"value3"}
{"f1":"value4"}
{"f1":"value5"}
{"f1":"value6"}
{"f1":"value7"}
{"f1":"value8"}
{"f1":"value9"}
```

N.B: Control Center is reachable at [http://127.0.0.1:9021](http://127.0.0.1:9021])
