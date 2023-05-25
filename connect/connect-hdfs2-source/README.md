# HDFS 2 Source connector



## Objective

Quickly test [HDFS 2 Source](https://docs.confluent.io/current/connect/kafka-connect-hdfs/hdfs2/source/index.html#kconnect-long-hdfs-2-source-connector-for-cp) connector.



## How to run

Simply run:

```
$ playground run -f hdfs2<tab>
```

## Details of what the script is doing


Steps from [connect-hdfs2-sink](../connect/connect-hdfs2-sink/README.md)


Creating HDFS Source connector:

```bash
$ curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
          "connector.class":"io.confluent.connect.hdfs2.Hdfs2SourceConnector",
          "tasks.max":"1",
          "store.url":"hdfs://namenode:8020",
          "hadoop.conf.dir":"/etc/hadoop/",
          "format.class" : "io.confluent.connect.hdfs2.format.avro.AvroFormat",
          "confluent.topic.bootstrap.servers": "broker:9092",
          "confluent.topic.replication.factor": "1",
          "transforms" : "AddPrefix",
          "transforms.AddPrefix.type" : "org.apache.kafka.connect.transforms.RegexRouter",
          "transforms.AddPrefix.regex" : ".*",
          "transforms.AddPrefix.replacement" : "copy_of_$0"
          }' \
     http://localhost:8083/connectors/hdfs2-source/config | jq .
```

Verifying topic `copy_of_test_hdfs`:

```bash
playground topic consume --topic copy_of_test_hdfs --min-expected-messages 9 --timeout 60
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
