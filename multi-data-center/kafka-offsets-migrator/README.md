# kafka-offsets-migrator

## Objective

Quickly test [kafka-offsets-migrator](https://github.com/bb01100100/kafka-offsets-migrator)

## How to run

```
$ playground run -f start<tab>
```

## Details of what the script is doing

Sending 20 records in Europe cluster

```bash
$ seq -f "european_sale_%g ${RANDOM}" 20 | docker container exec -i connect-europe bash -c "kafka-console-producer --broker-list broker-europe:9092 --topic sales_EUROPE --producer-property interceptor.classes=io.confluent.monitoring.clients.interceptor.MonitoringProducerInterceptor --producer-property confluent.monitoring.interceptor.bootstrap.servers=broker-metrics:9092"
```

Consumer with group my-consumer-group reads 10 messages in Europe cluster

```bash
$ docker container exec -i connect-europe bash -c "kafka-console-consumer --bootstrap-server broker-europe:9092 --whitelist 'sales_EUROPE' --from-beginning --max-messages 10 --consumer-property interceptor.classes=io.confluent.monitoring.clients.interceptor.MonitoringConsumerInterceptor --consumer-property confluent.monitoring.interceptor.bootstrap.servers=broker-metrics:9092 --consumer-property group.id=my-consumer-group"
```

Replicate from Europe to US

```bash
$ docker container exec connect-us \
playground connector create-or-update --connector replicate-europe-to-us << EOF
{
          "connector.class":"io.confluent.connect.replicator.ReplicatorSourceConnector",
          "key.converter": "io.confluent.connect.replicator.util.ByteArrayConverter",
          "value.converter": "io.confluent.connect.replicator.util.ByteArrayConverter",
          "header.converter": "io.confluent.connect.replicator.util.ByteArrayConverter",
          "src.consumer.group.id": "replicate-europe-to-us",
          "src.consumer.interceptor.classes": "io.confluent.monitoring.clients.interceptor.MonitoringConsumerInterceptor",
          "src.consumer.confluent.monitoring.interceptor.bootstrap.servers": "broker-metrics:9092",
          "src.kafka.bootstrap.servers": "broker-europe:9092",
          "dest.kafka.bootstrap.servers": "broker-us:9092",
          "confluent.topic.replication.factor": 1,
          "provenance.header.enable": true,
          "topic.whitelist": "sales_EUROPE"
          }
EOF
```

Wait for data to be replicated

Calling kafka-offsets-migrator

```bash
$ docker container exec -i connect-us bash -c "pip3 install -U -r /tmp/requirements.txt && python /tmp/offset_translator.py --source-broker broker-europe:9092 --dest-broker broker-us:9092 --group my-consumer-group --topic sales_EUROPE"
```

Output:

```log
2021-06-29T14:46:17 UTC [INFO ]
2021-06-29T14:46:17 UTC [INFO ]
2021-06-29T14:46:17 UTC [INFO ]  ================================================================================
2021-06-29T14:46:17 UTC [INFO ]  Starting Offset translator.
2021-06-29T14:46:17 UTC [INFO ]  Args passed in are: Namespace(dst_broker='broker-us:9092', group='my-consumer-group', src_broker='broker-europe:9092', topic='sales_EUROPE')
2021-06-29T14:46:17 UTC [INFO ]  Offset Translator object instantiated.
2021-06-29T14:46:17 UTC [INFO ]    Source bootstrap servers: broker-europe:9092
2021-06-29T14:46:17 UTC [INFO ]    Destination  bootstrap servers: broker-europe:9092
2021-06-29T14:46:17 UTC [INFO ]    Consumer group: my-consumer-group
2021-06-29T14:46:17 UTC [INFO ]  Finding topics associated with my-consumer-group...
/usr/bin/kafka-consumer-groups
2021-06-29T14:46:17 UTC [INFO ]  Running kafka-consumer-groups --bootstrap-server broker-europe:9092 --describe --group my-consumer-group  2>/dev/null| grep my-consumer-group | grep -v 'Error: Consumer group '| awk '{print $2}' | sort -u
2021-06-29T14:46:18 UTC [INFO ]  Overriding topic list from CG tool with supplied topic.
2021-06-29T14:46:18 UTC [INFO ]  Returning ['sales_EUROPE']...
2021-06-29T14:46:18 UTC [INFO ]  Getting consumer group offsets for 1 topics...
2021-06-29T14:46:18 UTC [INFO ]  Getting TPOs for 1 topics via admin API...
2021-06-29T14:46:18 UTC [INFO ]  Found 1 TPOs for 1 topics.
2021-06-29T14:46:18 UTC [INFO ]    Decrementing offsets so that we can inspect the last message consumed (for hashing, timestamps, etc)
2021-06-29T14:46:18 UTC [INFO ]  Found offsets for 1 topic partitions.
2021-06-29T14:46:18 UTC [INFO ]  Building metadata map...
2021-06-29T14:46:18 UTC [INFO ]  Built metadata for 1 TPOs
2021-06-29T14:46:18 UTC [INFO ]  topic: sales_EUROPE:
2021-06-29T14:46:18 UTC [INFO ]    p[0]
2021-06-29T14:46:18 UTC [INFO ]       source       last message offset (9), timestamp(           0), hash(None)
2021-06-29T14:46:18 UTC [INFO ]       destination  last message offset ( ), timestamp(            ), hash(None)
2021-06-29T14:46:18 UTC [INFO ]  Inspecting 1 TPOs in source cluster.
2021-06-29T14:46:19 UTC [INFO ]  Returning metadata for 1 TPOs
2021-06-29T14:46:19 UTC [INFO ]  Updating metadata...
2021-06-29T14:46:19 UTC [INFO ]  1 updates to metadata from source cluster.
2021-06-29T14:46:19 UTC [INFO ]  Getting offsets from timestamps for 1 metadata entries..
2021-06-29T14:46:19 UTC [INFO ]  Returning 1 offsets from destination cluster.
2021-06-29T14:46:19 UTC [INFO ]  Inspecting 1 TPOs in destination cluster.
2021-06-29T14:46:19 UTC [INFO ]  Returning metadata for 1 TPOs
2021-06-29T14:46:19 UTC [INFO ]  Updating metadata...
2021-06-29T14:46:19 UTC [INFO ]  1 updates to metadata from destination cluster.
2021-06-29T14:46:19 UTC [INFO ]  Comparing offsets between source and destination cluster...
2021-06-29T14:46:19 UTC [INFO ]  Searching for destination messages that match via message hash...
2021-06-29T14:46:19 UTC [INFO ]    Working with TopicPartition(sales_EUROPE,0,9) @ 1624977932340
2021-06-29T14:46:19 UTC [INFO ]     NOT FOUND:  TopicPartition(sales_EUROPE,0,6) @ 1624977932340 does not have same hash.
2021-06-29T14:46:19 UTC [INFO ]     will traverse messages and attempt to find a match.
2021-06-29T14:46:19 UTC [INFO ]  Found 0 matching offsets and 1 that don't match.
2021-06-29T14:46:19 UTC [INFO ]  Working on unmatched offsets...
2021-06-29T14:46:19 UTC [INFO ]  Find the start/end offsets to iterate over to find a match based on message value hash.
2021-06-29T14:46:19 UTC [INFO ]  Shifting timestamp by 1ms, from 1624977932340 to 1624977932341
2021-06-29T14:46:19 UTC [INFO ]                             yields an offset of TopicPartition{topic=sales_EUROPE,partition=0,offset=17,error=None}
2021-06-29T14:46:19 UTC [INFO ]  Starting offset for scan is 6 (inclusive)
2021-06-29T14:46:19 UTC [INFO ]  Ending   offset for scan is 17 (exclusive)
2021-06-29T14:46:19 UTC [INFO ]  Inspecting destination cluster message at offset 6...
2021-06-29T14:46:19 UTC [INFO ]  Inspecting 1 TPOs in destination cluster.
2021-06-29T14:46:20 UTC [INFO ]  Returning metadata for 1 TPOs
2021-06-29T14:46:20 UTC [INFO ]  Inspecting destination cluster message at offset 7...
2021-06-29T14:46:20 UTC [INFO ]  Inspecting 1 TPOs in destination cluster.
2021-06-29T14:46:20 UTC [INFO ]  Returning metadata for 1 TPOs
2021-06-29T14:46:20 UTC [INFO ]  Inspecting destination cluster message at offset 8...
2021-06-29T14:46:20 UTC [INFO ]  Inspecting 1 TPOs in destination cluster.
2021-06-29T14:46:21 UTC [INFO ]  Returning metadata for 1 TPOs
2021-06-29T14:46:21 UTC [INFO ]  Inspecting destination cluster message at offset 9...
2021-06-29T14:46:21 UTC [INFO ]  Inspecting 1 TPOs in destination cluster.
2021-06-29T14:46:21 UTC [INFO ]  Returning metadata for 1 TPOs
2021-06-29T14:46:21 UTC [INFO ]     FOUND matching record:
2021-06-29T14:46:21 UTC [INFO ]                           source hash was fe65fc7fa7633cc25fef530cd2dd566bef759319d8d071bcfc371aa5d08bb4f8, and
2021-06-29T14:46:21 UTC [INFO ]                           dest_hash is    fe65fc7fa7633cc25fef530cd2dd566bef759319d8d071bcfc371aa5d08bb4f8
2021-06-29T14:46:21 UTC [INFO ]  .                        destination     TopicPartition{topic=sales_EUROPE,partition=0,offset=9,error=None}
2021-06-29T14:46:21 UTC [INFO ]  Found 1 out of 1 unmatched objects.
2021-06-29T14:46:21 UTC [INFO ]  Checking that all metadata records were matched in the destination cluster...
2021-06-29T14:46:21 UTC [INFO ]  All metadata was matched.
2021-06-29T14:46:21 UTC [INFO ]  Committing offsets for supplied TPOs...
2021-06-29T14:46:21 UTC [INFO ]   TPO offsets are incremented by one so that next message consumed is correct.
2021-06-29T14:46:21 UTC [INFO ]   Calling commit() for 1 topic/partitions to destination cluster.
2021-06-29T14:46:21 UTC [INFO ]  Offsets committed successfully to destination cluster
>>>>>>['sales_EUROPE']>>>>>
Getting committed offsets for my-consumer-group on topic sales_EUROPE
Building an initial (empty) metadata map of topic/partitions and their CG offsets
Printing metadata...
Inspecting TPO messages...
Updating metadata...
Getting destionatin cluster TPOs via source cluster message timestamps...
Inspecting destination cluster messages (hashing, etc)...
Updating metadata...
Generating list of translated offsets...
defaultdict(<class 'dict'>,
            {   'sales_EUROPE::0': {   'dest_hash': '20b1bb2f8d9f3497af5a4b6f62d86a4cd35c91e096619419de2bd3f55044de50',
                                       'dest_message': <cimpl.Message object at 0x7fc302590cc8>,
                                       'dest_offset': 6,
                                       'dest_timestamp': 1624977932340,
                                       'dest_tpo': TopicPartition{topic=sales_EUROPE,partition=0,offset=6,error=None},
                                       'src_hash': 'fe65fc7fa7633cc25fef530cd2dd566bef759319d8d071bcfc371aa5d08bb4f8',
                                       'src_message': <cimpl.Message object at 0x7fc302590c48>,
                                       'src_offset': 9,
                                       'src_timestamp': 1624977932340,
                                       'src_tpo': TopicPartition{topic=sales_EUROPE,partition=0,offset=9,error=None}}})
Offsets to be commited in destination cluster are:
  topic: sales_EUROPE, partition 0, offset 9
```

Consumer with group my-consumer-group reads 10 messages in US cluster, it should start from previous offset

```bash
$ docker container exec -i connect-europe bash -c "kafka-console-consumer --bootstrap-server broker-us:9092 --whitelist 'sales_EUROPE' --max-messages 10 --consumer-property interceptor.classes=io.confluent.monitoring.clients.interceptor.MonitoringConsumerInterceptor --consumer-property confluent.monitoring.interceptor.bootstrap.servers=broker-metrics:9092 --consumer-property group.id=my-consumer-group"
```