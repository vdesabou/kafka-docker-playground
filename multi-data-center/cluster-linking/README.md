# Cluster Linking

## Objective

Quickly test [Cluster Linking](https://docs.confluent.io/platform/current/multi-dc-deployments/cluster-linking/tutorial.html#cluster-linking-tutorial).

## How to run

Simply run:

```
$ just use <playground run> command and search for start-plaintext.sh in this folder
```

or with SASL_PLAINTEXT and ACLs:

```
$ just use <playground run> command and search for start-sasl-plain-acl.sh in this folder
```
## Details of what the script is doing

`US`cluster is source and `EUROPE` cluster is destination

`broker-europe` has cluster linking enabled:

```yml
  broker-europe:
      environment:
        KAFKA_CONFLUENT_CLUSTER_LINK_ENABLE : "true"
```

Create topic demo

```bash
docker exec broker-europe kafka-topics --create --topic demo --bootstrap-server broker-us:9092 --replication-factor 1 --partitions 1
```

Sending 20 messages in US cluster

```bash
seq -f "us_sale_%g ${RANDOM}" 20 | docker container exec -i connect-us bash -c "kafka-console-producer --bootstrap-server broker-us:9092 --topic demo"
```

Verify we have received the data in source cluster using consumer group id my-consumer-group, we read only 5 messages

```bash
playground topic consume --topic demo --min-expected-messages 5 --timeout 60
```

```
us_sale_1 3669
us_sale_2 3669
us_sale_3 3669
us_sale_4 3669
us_sale_5 3669
Processed a total of 5 messages
```

Create the cluster link on the destination cluster (with `metadata.max.age.ms=5 seconds` + `consumer.offset.sync.enable=true` + `consumer.offset.sync.ms=3000` + `consumer.offset.sync.json` set to all consumer groups)
```bash
docker exec broker-europe kafka-cluster-links --bootstrap-server broker-europe:9092 --create --link demo-link --config bootstrap.servers=broker-us:9092,metadata.max.age.ms=5000,consumer.offset.sync.enable=true,consumer.offset.sync.ms=3000 --consumer-group-filters-json-file /tmp/consumer.offset.sync.json
```

Initialize the topic mirror for topic demo

```bash
docker exec broker-europe kafka-topics --create --topic demo --mirror-topic demo --link demo-link --bootstrap-server broker-europe:9092
```

Created topic demo.


Check the replica status on the destination

```bash
docker exec broker-europe kafka-replica-status --topics demo --include-linked --bootstrap-server broker-europe:9092
```

```
Topic Partition Replica ClusterLink IsLeader IsObserver IsIsrEligible IsInIsr IsCaughtUp LastCaughtUpLagMs LastFetchLagMs LogStartOffset LogEndOffset
demo  0         1       -           true     false      true          true    true       0                 0              0              20
demo  0         2       demo-link   true     false      true          true    true       -8                -8             0              20
```

Wait 6 seconds for consumer.offset sync to happen (2 times `consumer.offset.sync.ms=3000`)

Verify that current offset is consistent in source and destination

Describe consumer group my-consumer-group at Source cluster
```bash
docker exec broker-europe kafka-consumer-groups --bootstrap-server broker-us:9092 --describe --group my-consumer-group
```

```
Consumer group 'my-consumer-group' has no active members.

GROUP             TOPIC           PARTITION  CURRENT-OFFSET  LOG-END-OFFSET  LAG             CONSUMER-ID     HOST            CLIENT-ID
my-consumer-group demo            0          5               20              15              -               -               -
```

Describe consumer group my-consumer-group at Destination cluster
```bash
docker exec broker-europe kafka-consumer-groups --bootstrap-server broker-europe:9092 --describe --group my-consumer-group
```

```
Consumer group 'my-consumer-group' has no active members.

GROUP             TOPIC           PARTITION  CURRENT-OFFSET  LOG-END-OFFSET  LAG             CONSUMER-ID     HOST            CLIENT-ID
my-consumer-group demo            0          5               20              15              -               -               -
```


Consume from the mirror topic on the destination cluster and verify consumer offset is working, it should start at 6
```bash

playground topic consume --topic demo --min-expected-messages 5 --timeout 60
```

```
us_sale_6 3669
us_sale_7 3669
us_sale_8 3669
us_sale_9 3669
us_sale_10 3669
Processed a total of 5 messages
```

Describe consumer group my-consumer-group at Destination cluster.

```bash
docker exec broker-europe kafka-consumer-groups --bootstrap-server broker-europe:9092 --describe --group my-consumer-group
```

```
Consumer group 'my-consumer-group' has no active members.

GROUP             TOPIC           PARTITION  CURRENT-OFFSET  LOG-END-OFFSET  LAG             CONSUMER-ID     HOST            CLIENT-ID
my-consumer-group demo            0          5               20              15              -               -               -
```

sleep 6 seconds

Describe consumer group my-consumer-group at Destination cluster.

❗ Note: the current-offset has been overwritten due to the consumer offset sync

```bash
docker exec broker-europe kafka-consumer-groups --bootstrap-server broker-europe:9092 --describe --group my-consumer-group
```

```
Consumer group 'my-consumer-group' has no active members.

GROUP             TOPIC           PARTITION  CURRENT-OFFSET  LOG-END-OFFSET  LAG             CONSUMER-ID     HOST            CLIENT-ID
my-consumer-group demo            0          5               20              15              -               -               -
```

Stop consumer offset sync for consumer group my-consumer-group

```bash
echo "consumer.offset.group.filters={\"groupFilters\": [ \
  { \
    \"name\": \"*\", \
    \"patternType\": \"LITERAL\", \
    \"filterType\": \"INCLUDE\" \
  }, \
  { \
    \"name\": \"my-consumer-group\", \
    \"patternType\": \"LITERAL\", \
    \"filterType\": \"EXCLUDE\" \
  } \
]}" > newFilters.properties
docker cp newFilters.properties broker-europe:/tmp/newFilters.properties
docker exec broker-europe kafka-configs --bootstrap-server broker-europe:9092 --alter --cluster-link demo-link --add-config-file /tmp/newFilters.properties
```

Consume from the source cluster another 10 messages, up to 15

```bash
playground topic consume --topic demo --min-expected-messages 10 --timeout 60
```

```
us_sale_6 3669
us_sale_7 3669
us_sale_8 3669
us_sale_9 3669
us_sale_10 3669
us_sale_11 3669
us_sale_12 3669
us_sale_13 3669
us_sale_14 3669
us_sale_15 3669
Processed a total of 10 messages
```

Consume from the destination cluster, it will continue from it's last offset 10

```bash
playground topic consume --topic demo --min-expected-messages 5 --timeout 60
```

```
us_sale_6 3669
us_sale_7 3669
us_sale_8 3669
us_sale_9 3669
us_sale_10 3669
Processed a total of 5 messages
```

Verify that the topic mirror is read-only

```bash
seq -f "europe_sale_%g ${RANDOM}" 10 | docker container exec -i connect-us bash -c "kafka-console-producer --bootstrap-server broker-europe:9092 --topic demo"
```

```
>>>>>>>>>>>[2021-05-04 12:21:56,445] ERROR Error when sending message to topic demo with key: null, value: 18 bytes with error: (org.apache.kafka.clients.producer.internals.ErrorLoggingCallback)
org.apache.kafka.common.errors.InvalidRequestException: Cannot append records to read-only mirror topic 'demo'
[2021-05-04 12:21:56,447] ERROR Error when sending message to topic demo with key: null, value: 18 bytes with error: (org.apache.kafka.clients.producer.internals.ErrorLoggingCallback)
org.apache.kafka.common.errors.InvalidRequestException: Cannot append records to read-only mirror topic 'demo'
[2021-05-04 12:21:56,448] ERROR Error when sending message to topic demo with key: null, value: 18 bytes with error: (org.apache.kafka.clients.producer.internals.ErrorLoggingCallback)
org.apache.kafka.common.errors.InvalidRequestException: Cannot append records to read-only mirror topic 'demo'
[2021-05-04 12:21:56,448] ERROR Error when sending message to topic demo with key: null, value: 18 bytes with error: (org.apache.kafka.clients.producer.internals.ErrorLoggingCallback)
org.apache.kafka.common.errors.InvalidRequestException: Cannot append records to read-only mirror topic 'demo'
[2021-05-04 12:21:56,448] ERROR Error when sending message to topic demo with key: null, value: 18 bytes with error: (org.apache.kafka.clients.producer.internals.ErrorLoggingCallback)
org.apache.kafka.common.errors.InvalidRequestException: Cannot append records to read-only mirror topic 'demo'
[2021-05-04 12:21:56,448] ERROR Error when sending message to topic demo with key: null, value: 18 bytes with error: (org.apache.kafka.clients.producer.internals.ErrorLoggingCallback)
org.apache.kafka.common.errors.InvalidRequestException: Cannot append records to read-only mirror topic 'demo'
[2021-05-04 12:21:56,448] ERROR Error when sending message to topic demo with key: null, value: 18 bytes with error: (org.apache.kafka.clients.producer.internals.ErrorLoggingCallback)
org.apache.kafka.common.errors.InvalidRequestException: Cannot append records to read-only mirror topic 'demo'
[2021-05-04 12:21:56,448] ERROR Error when sending message to topic demo with key: null, value: 18 bytes with error: (org.apache.kafka.clients.producer.internals.ErrorLoggingCallback)
org.apache.kafka.common.errors.InvalidRequestException: Cannot append records to read-only mirror topic 'demo'
[2021-05-04 12:21:56,448] ERROR Error when sending message to topic demo with key: null, value: 18 bytes with error: (org.apache.kafka.clients.producer.internals.ErrorLoggingCallback)
org.apache.kafka.common.errors.InvalidRequestException: Cannot append records to read-only mirror topic 'demo'
[2021-05-04 12:21:56,449] ERROR Error when sending message to topic demo with key: null, value: 19 bytes with error: (org.apache.kafka.clients.producer.internals.ErrorLoggingCallback)
org.apache.kafka.common.errors.InvalidRequestException: Cannot append records to read-only mirror topic 'demo'
```

Modify the source topic config, set retention.ms

```bash
docker container exec -i connect-us kafka-configs --alter --topic demo --add-config retention.ms=123456890 --bootstrap-server broker-us:9092
```

Check the Source Topic Configuration

```bash
docker container exec -i connect-us kafka-configs --describe --topic demo --bootstrap-server broker-us:9092
```

```
Dynamic configs for topic demo are:
  retention.ms=123456890 sensitive=false synonyms={DYNAMIC_TOPIC_CONFIG:retention.ms=123456890}
```

Wait 6 seconds (default is 5 minutes for `metadata.max.age.ms`, but we modified it to 5 seconds)

Check the Destination Topic Configuration

```bash
docker container exec -i connect-us kafka-configs --describe --topic demo --bootstrap-server broker-europe:9092
```

```
Dynamic configs for topic demo are:
  compression.type=producer sensitive=false synonyms={DYNAMIC_TOPIC_CONFIG:compression.type=producer, DEFAULT_CONFIG:compression.type=producer}
  cleanup.policy=delete sensitive=false synonyms={DYNAMIC_TOPIC_CONFIG:cleanup.policy=delete, DEFAULT_CONFIG:log.cleanup.policy=delete}
  retention.ms=123456890 sensitive=false synonyms={DYNAMIC_TOPIC_CONFIG:retention.ms=123456890}
  max.message.bytes=1048588 sensitive=false synonyms={DYNAMIC_TOPIC_CONFIG:max.message.bytes=1048588, DEFAULT_CONFIG:message.max.bytes=1048588}
```

Alter the number of partitions on the source topic

```bash
docker container exec -i connect-us kafka-topics --alter --topic demo --partitions 8 --bootstrap-server broker-us:9092
```
Verify the change on the source topic

```bash
docker container exec -i connect-us kafka-topics --describe --topic demo --bootstrap-server broker-us:9092
```

```
Topic: demo     PartitionCount: 8       ReplicationFactor: 1    Configs: retention.ms=123456890
        Topic: demo     Partition: 0    Leader: 2       Replicas: 2     Isr: 2  Offline:
        Topic: demo     Partition: 1    Leader: 2       Replicas: 2     Isr: 2  Offline:
        Topic: demo     Partition: 2    Leader: 2       Replicas: 2     Isr: 2  Offline:
        Topic: demo     Partition: 3    Leader: 2       Replicas: 2     Isr: 2  Offline:
        Topic: demo     Partition: 4    Leader: 2       Replicas: 2     Isr: 2  Offline:
        Topic: demo     Partition: 5    Leader: 2       Replicas: 2     Isr: 2  Offline:
        Topic: demo     Partition: 6    Leader: 2       Replicas: 2     Isr: 2  Offline:
        Topic: demo     Partition: 7    Leader: 2       Replicas: 2     Isr: 2  Offline:
```

Wait 6 seconds (default is 5 minutes `metadata.max.age.ms`, but we modified it to 5 seconds)

Verify the change on the destination topic

```bash
docker container exec -i connect-us kafka-topics --describe --topic demo --bootstrap-server broker-europe:9092
```

```
Topic: demo     PartitionCount: 8       ReplicationFactor: 1    Configs: compression.type=producer,cleanup.policy=delete,retention.ms=123456890,max.message.bytes=1048588
        Topic: demo     Partition: 0    Leader: 1       Replicas: 1     Isr: 1  Offline:
        Topic: demo     Partition: 1    Leader: 1       Replicas: 1     Isr: 1  Offline:
        Topic: demo     Partition: 2    Leader: 1       Replicas: 1     Isr: 1  Offline:
        Topic: demo     Partition: 3    Leader: 1       Replicas: 1     Isr: 1  Offline:
        Topic: demo     Partition: 4    Leader: 1       Replicas: 1     Isr: 1  Offline:
        Topic: demo     Partition: 5    Leader: 1       Replicas: 1     Isr: 1  Offline:
        Topic: demo     Partition: 6    Leader: 1       Replicas: 1     Isr: 1  Offline:
        Topic: demo     Partition: 7    Leader: 1       Replicas: 1     Isr: 1  Offline:
```

List mirror topics

```bash
docker container exec -i connect-us kafka-cluster-links --list --link demo-link --include-topics --bootstrap-server broker-europe:9092
```

```
Link name: 'demo-link', link ID: '49d143a1-846b-4ef2-9819-2dee26d0ea99', cluster ID: 'wwl36JrlQounS_4nGuvg6A', topics: [demo]
```


Cut over the mirror topic to make it writable

```bash
docker container exec -i connect-us kafka-mirrors --failover --topics demo --bootstrap-server broker-europe:9092
```

Produce to both topics to verify divergence


Sending data again in US cluster

```bash
seq -f "us_sale_%g ${RANDOM}" 10 | docker container exec -i connect-us bash -c "kafka-console-producer --bootstrap-server broker-us:9092 --topic demo"
```
Sending data in EUROPE cluster

```bash
seq -f "europe_sale_%g ${RANDOM}" 10 | docker container exec -i connect-us bash -c "kafka-console-producer --bootstrap-server broker-europe:9092 --topic demo"
```

Delete the cluster link

```bash
docker container exec -i connect-us kafka-cluster-links --bootstrap-server broker-europe:9092 --delete --link demo-link
```

```
Cluster link 'demo-link' deletion successfully completed.
```

N.B: Control Center is reachable at [http://127.0.0.1:9021](http://127.0.0.1:9021]), use `superUser`/`superUser`to login.

