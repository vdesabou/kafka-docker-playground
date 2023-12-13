# HDFS 3 Sink connector



## Objective

Quickly test [HDFS 3 Sink](https://docs.confluent.io/current/connect/kafka-connect-hdfs/hdfs3/index.html#kconnect-long-hdfs-3-sink-connector) connector.

Note: HIVE integration is only available when using CP < 6.x or a non UBI8 image, because otherwise images are using JDK 11 which is not supported by HADOOP. The connector would fail with:

```
[2021-05-26 15:47:45,399] ERROR Got exception: java.lang.ClassCastException class [Ljava.lang.Object; cannot be cast to class [Ljava.net.URI; ([Ljava.lang.Object; and [Ljava.net.URI; are in module java.base of loader 'bootstrap') (org.apache.hadoop.hive.metastore.utils.MetaStoreUtils)
java.lang.ClassCastException: class [Ljava.lang.Object; cannot be cast to class [Ljava.net.URI; ([Ljava.lang.Object; and [Ljava.net.URI; are in module java.base of loader 'bootstrap')
```

## How to run

Simply run:

```
$ playground run -f hdfs3-sink<use tab key to activate fzf completion (see https://kafka-docker-playground.io/#/cli?id=%e2%9a%a1-setup-completion), otherwise use full path, or correct relative path>
```

or with Kerberos:

```
$ playground run -f hdfs2-sink-kerberos<use tab key to activate fzf completion (see https://kafka-docker-playground.io/#/cli?id=%e2%9a%a1-setup-completion), otherwise use full path, or correct relative path> (without Hive support)
```

## Details of what the script is doing

Note in this simple example, if you get into an issue with permissions at the local HDFS level, it may be easiest to unlock the permissions unless you want to debug that more.

```bash
$ docker exec namenode bash -c "/opt/hadoop-3.1.3/bin/hdfs dfs -chmod 777  /"
```

The connector is created with:

###  without Hive integration (not supported with JDK 11)

```bash
$ curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class":"io.confluent.connect.hdfs3.Hdfs3SinkConnector",
               "tasks.max":"1",
               "topics":"test_hdfs",
               "store.url":"hdfs://namenode:9000",
               "flush.size":"3",
               "hadoop.conf.dir":"/etc/hadoop/",
               "partitioner.class":"io.confluent.connect.storage.partitioner.FieldPartitioner",
               "partition.field.name":"f1",
               "rotate.interval.ms":"120000",
               "hadoop.home":"/opt/hadoop-3.1.3/share/hadoop/common",
               "logs.dir":"/tmp",
               "confluent.license": "",
               "confluent.topic.bootstrap.servers": "broker:9092",
               "confluent.topic.replication.factor": "1",
               "key.converter":"org.apache.kafka.connect.storage.StringConverter",
               "value.converter":"io.confluent.connect.avro.AvroConverter",
               "value.converter.schema.registry.url":"http://schema-registry:8081",
               "schema.compatibility":"BACKWARD"
          }' \
     http://localhost:8083/connectors/hdfs3-sink/config | jq .
```

###  with Hive integration

```bash
$ curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class":"io.confluent.connect.hdfs3.Hdfs3SinkConnector",
               "tasks.max":"1",
               "topics":"test_hdfs",
               "store.url":"hdfs://namenode:9000",
               "flush.size":"3",
               "hadoop.conf.dir":"/etc/hadoop/",
               "partitioner.class":"io.confluent.connect.storage.partitioner.FieldPartitioner",
               "partition.field.name":"f1",
               "rotate.interval.ms":"120000",
               "hadoop.home":"/opt/hadoop-3.1.3/share/hadoop/common",
               "logs.dir":"/tmp",
               "hive.integration": "true",
               "hive.metastore.uris": "thrift://hive-metastore:9083",
               "hive.database": "testhive",
               "confluent.license": "",
               "confluent.topic.bootstrap.servers": "broker:9092",
               "confluent.topic.replication.factor": "1",
               "key.converter":"org.apache.kafka.connect.storage.StringConverter",
               "value.converter":"io.confluent.connect.avro.AvroConverter",
               "value.converter.schema.registry.url":"http://schema-registry:8081",
               "schema.compatibility":"BACKWARD"
          }' \
     http://localhost:8083/connectors/hdfs3-sink/config | jq .
```

Messages are sent to `test_hdfs` topic using:

```
$ playground topic produce -t test_hdfs --nb-messages 10 --forced-value '{"f1":"value%g"}' << 'EOF'
{
  "type": "record",
  "name": "myrecord",
  "fields": [
    {
      "name": "f1",
      "type": "string"
    }
  ]
}
EOF
```

After a few seconds, HDFS should contain files in /topics/test_hdfs:

```
$ docker exec namenode bash -c "/opt/hadoop-3.1.3/bin/hdfs dfs -ls /topics/test_hdfs"

drwxr-xr-x   - root supergroup          0 2019-10-25 08:19 /topics/test_hdfs/f1=value1
drwxr-xr-x   - root supergroup          0 2019-10-25 08:19 /topics/test_hdfs/f1=value2
drwxr-xr-x   - root supergroup          0 2019-10-25 08:19 /topics/test_hdfs/f1=value3
drwxr-xr-x   - root supergroup          0 2019-10-25 08:19 /topics/test_hdfs/f1=value4
drwxr-xr-x   - root supergroup          0 2019-10-25 08:19 /topics/test_hdfs/f1=value5
drwxr-xr-x   - root supergroup          0 2019-10-25 08:19 /topics/test_hdfs/f1=value6
drwxr-xr-x   - root supergroup          0 2019-10-25 08:19 /topics/test_hdfs/f1=value7
drwxr-xr-x   - root supergroup          0 2019-10-25 08:19 /topics/test_hdfs/f1=value8
drwxr-xr-x   - root supergroup          0 2019-10-25 08:19 /topics/test_hdfs/f1=value9
```

Check data with beeline:

```
$ docker exec -i hive-server beeline << EOF
!connect jdbc:hive2://hive-server:10000/testhive
hive
hive
show create table test_hdfs;
select * from test_hdfs;
EOF
```

Results:

```
SLF4J: Class path contains multiple SLF4J bindings.
SLF4J: Found binding in [jar:file:/opt/hive/lib/log4j-slf4j-impl-2.10.0.jar!/org/slf4j/impl/StaticLoggerBinder.class]
SLF4J: Found binding in [jar:file:/opt/hadoop-3.1.2/share/hadoop/common/lib/slf4j-log4j12-1.7.25.jar!/org/slf4j/impl/StaticLoggerBinder.class]
SLF4J: See http://www.slf4j.org/codes.html#multiple_bindings for an explanation.
SLF4J: Actual binding is of type [org.apache.logging.slf4j.Log4jLoggerFactory]
Beeline version 3.1.2 by Apache Hive
beeline> !connect jdbc:hive2://hive-server:10000/testhive
Connecting to jdbc:hive2://hive-server:10000/testhive
Enter username for jdbc:hive2://hive-server:10000/testhive: hive
Enter password for jdbc:hive2://hive-server:10000/testhive: ****
Connected to: Apache Hive (version 3.1.2)
Driver: Hive JDBC (version 3.1.2)
Transaction isolation: TRANSACTION_REPEATABLE_READ
0: jdbc:hive2://hive-server:10000/testhive> show create table test_hdfs;
INFO  : Compiling command(queryId=root_20210526150123_6c048ef2-8793-4759-b0b2-7b601eac0bce): show create table test_hdfs
INFO  : Concurrency mode is disabled, not creating a lock manager
INFO  : Semantic Analysis Completed (retrial = false)
INFO  : Returning Hive schema: Schema(fieldSchemas:[FieldSchema(name:createtab_stmt, type:string, comment:from deserializer)], properties:null)
INFO  : Completed compiling command(queryId=root_20210526150123_6c048ef2-8793-4759-b0b2-7b601eac0bce); Time taken: 1.098 seconds
INFO  : Concurrency mode is disabled, not creating a lock manager
INFO  : Executing command(queryId=root_20210526150123_6c048ef2-8793-4759-b0b2-7b601eac0bce): show create table test_hdfs
INFO  : Starting task [Stage-0:DDL] in serial mode
INFO  : Completed executing command(queryId=root_20210526150123_6c048ef2-8793-4759-b0b2-7b601eac0bce); Time taken: 0.149 seconds
INFO  : OK
INFO  : Concurrency mode is disabled, not creating a lock manager
+----------------------------------------------------+
|                   createtab_stmt                   |
+----------------------------------------------------+
| CREATE EXTERNAL TABLE `test_hdfs`(                 |
|   `f1` string COMMENT '')                          |
| PARTITIONED BY (                                   |
|   `f1` string COMMENT '')                          |
| ROW FORMAT SERDE                                   |
|   'org.apache.hadoop.hive.serde2.avro.AvroSerDe'   |
| STORED AS INPUTFORMAT                              |
|   'org.apache.hadoop.hive.ql.io.avro.AvroContainerInputFormat'  |
| OUTPUTFORMAT                                       |
|   'org.apache.hadoop.hive.ql.io.avro.AvroContainerOutputFormat' |
| LOCATION                                           |
|   'hdfs://namenode:9000/topics/test_hdfs'          |
| TBLPROPERTIES (                                    |
|   'avro.schema.literal'='{"type":"record","name":"myrecord","fields":[{"name":"f1","type":"string"}],"connect.version":1,"connect.name":"myrecord"}',  |
|   'bucketing_version'='2',                         |
|   'transient_lastDdlTime'='1622041066')            |
+----------------------------------------------------+
16 rows selected (1.718 seconds)
0: jdbc:hive2://hive-server:10000/testhive> select * from test_hdfs;
INFO  : Compiling command(queryId=root_20210526150125_8f544310-a760-46b9-8484-feb72318e383): select * from test_hdfs
INFO  : Concurrency mode is disabled, not creating a lock manager
INFO  : Semantic Analysis Completed (retrial = false)
INFO  : Returning Hive schema: Schema(fieldSchemas:[FieldSchema(name:test_hdfs.f1, type:string, comment:null)], properties:null)
INFO  : Completed compiling command(queryId=root_20210526150125_8f544310-a760-46b9-8484-feb72318e383); Time taken: 1.894 seconds
INFO  : Concurrency mode is disabled, not creating a lock manager
INFO  : Executing command(queryId=root_20210526150125_8f544310-a760-46b9-8484-feb72318e383): select * from test_hdfs
INFO  : Completed executing command(queryId=root_20210526150125_8f544310-a760-46b9-8484-feb72318e383); Time taken: 0.001 seconds
INFO  : OK
INFO  : Concurrency mode is disabled, not creating a lock manager
+---------------+
| test_hdfs.f1  |
+---------------+
| value1        |
| value10       |
| value2        |
| value3        |
| value4        |
| value5        |
| value6        |
| value7        |
| value8        |
| value9        |
+---------------+
10 rows selected (2.415 seconds)
0: jdbc:hive2://hive-server:10000/testhive> Closing: 0: jdbc:hive2://hive-server:10000/testhive
```

N.B: Control Center is reachable at [http://127.0.0.1:9021](http://127.0.0.1:9021])
