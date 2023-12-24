# One to Many replication with offsets translation

## Objective

Verify how the offsets are translated is when replicating from one source cluster to many destinations.
In others words, verifying differents instances of replicators are not sharing a state.

## How to run

```
$ playground run -f start<use tab key to activate fzf completion (see https://kafka-docker-playground.io/#/cli?id=%e2%9a%a1-setup-completion), otherwise use full path, or correct relative path>
```

## Details of what the script is doing

Sending 20 records in Metrics cluster

```bash
$ seq -f "sale_%g ${RANDOM}" 20 | docker container exec -i connect-europe bash -c "kafka-console-producer --broker-list broker-metrics:9092 --topic sales"
```

Consumer with group my-consumer-group and the `ConsumerTimestampsInterceptor` interceptor reads 10 messages in Metrics cluster. The interceptor will create the `__consumer_timestamp` topic.

```bash
$ docker container exec -i connect-europe bash -c "kafka-console-consumer \
     --bootstrap-server broker-metrics:9092 \
     --topic 'sales' \
     --from-beginning \
     --max-messages 10 \
     --group my-consumer-group \
     --consumer-property interceptor.classes=io.confluent.connect.replicator.offsets.ConsumerTimestampsInterceptor \
     --consumer-property timestamps.topic.replication.factor=1"

```

Replicate from Metrics to Europe and US

```bash
$ docker container exec connect-europe \
playground connector create-or-update --connector replicate-metrics-to-europe  << EOF
{
          "connector.class":"io.confluent.connect.replicator.ReplicatorSourceConnector",
          "key.converter": "io.confluent.connect.replicator.util.ByteArrayConverter",
          "value.converter": "io.confluent.connect.replicator.util.ByteArrayConverter",
          "header.converter": "io.confluent.connect.replicator.util.ByteArrayConverter",
          "src.consumer.group.id": "replicate-metrics-to-europe",
          "src.kafka.bootstrap.servers": "broker-metrics:9092",
          "dest.kafka.bootstrap.servers": "broker-europe:9092",
          "confluent.topic.replication.factor": 1,
          "provenance.header.enable": true,
          "topic.whitelist": "sales",
          "offset.timestamps.commit": false,
          "offset.translator.batch.period.ms": 5000
          }
EOF

$ docker container exec connect-us \
playground connector create-or-update --connector replicate-metrics-to-us  << EOF
{
          "connector.class":"io.confluent.connect.replicator.ReplicatorSourceConnector",
          "key.converter": "io.confluent.connect.replicator.util.ByteArrayConverter",
          "value.converter": "io.confluent.connect.replicator.util.ByteArrayConverter",
          "header.converter": "io.confluent.connect.replicator.util.ByteArrayConverter",
          "src.consumer.group.id": "replicate-metrics-to-us",
          "src.kafka.bootstrap.servers": "broker-metrics:9092",
          "dest.kafka.bootstrap.servers": "broker-us:9092",
          "confluent.topic.replication.factor": 1,
          "provenance.header.enable": true,
          "topic.whitelist": "sales",
          "offset.timestamps.commit": false,
          "offset.translator.batch.period.ms": 5000
          }
EOF
```

Wait for data to be replicated

Consumer with group my-consumer-group on both Europe and US clusters. The consumer starts at offset 10 and reads the 10 last messages.
```bash
$ docker container exec -i connect-europe bash -c "kafka-console-consumer \
     --bootstrap-server broker-europe:9092 \
     --topic 'sales' \
     --max-messages 10  \
     --group my-consumer-group"

$ docker container exec -i connect-us bash -c "kafka-console-consumer \
     --bootstrap-server broker-us:9092 \
     --topic 'sales' \
     --max-messages 10  \
     --group my-consumer-group"
```

Output:

```log
09:19:21 ℹ️ Sending 20 records in Metrics cluster
[2021-08-11 07:19:23,554] WARN [Producer clientId=console-producer] Error while fetching metadata with correlation id 1 : {sales=LEADER_NOT_AVAILABLE} (org.apache.kafka.clients.NetworkClient)
09:19:24 ℹ️ Consumer with group my-consumer-group reads 10 messages in Metrics cluster
[2021-08-11 07:19:25,868] WARN The configuration 'key.deserializer' was supplied but isn't a known config. (org.apache.kafka.clients.admin.AdminClientConfig)
[2021-08-11 07:19:25,869] WARN The configuration 'value.deserializer' was supplied but isn't a known config. (org.apache.kafka.clients.admin.AdminClientConfig)
[2021-08-11 07:19:25,869] WARN The configuration 'timestamps.topic.replication.factor' was supplied but isn't a known config. (org.apache.kafka.clients.admin.AdminClientConfig)
[2021-08-11 07:19:25,869] WARN The configuration 'isolation.level' was supplied but isn't a known config. (org.apache.kafka.clients.admin.AdminClientConfig)
[2021-08-11 07:19:25,869] WARN The configuration 'group.id' was supplied but isn't a known config. (org.apache.kafka.clients.admin.AdminClientConfig)
[2021-08-11 07:19:25,869] WARN The configuration 'interceptor.classes' was supplied but isn't a known config. (org.apache.kafka.clients.admin.AdminClientConfig)
[2021-08-11 07:19:25,869] WARN The configuration 'auto.offset.reset' was supplied but isn't a known config. (org.apache.kafka.clients.admin.AdminClientConfig)
[2021-08-11 07:19:26,899] WARN The configuration 'key.deserializer' was supplied but isn't a known config. (org.apache.kafka.clients.producer.ProducerConfig)
[2021-08-11 07:19:26,899] WARN The configuration 'value.deserializer' was supplied but isn't a known config. (org.apache.kafka.clients.producer.ProducerConfig)
[2021-08-11 07:19:26,899] WARN The configuration 'group.id' was supplied but isn't a known config. (org.apache.kafka.clients.producer.ProducerConfig)
[2021-08-11 07:19:26,899] WARN The configuration 'timestamps.topic.replication.factor' was supplied but isn't a known config. (org.apache.kafka.clients.producer.ProducerConfig)
[2021-08-11 07:19:26,899] WARN The configuration 'isolation.level' was supplied but isn't a known config. (org.apache.kafka.clients.producer.ProducerConfig)
[2021-08-11 07:19:26,899] WARN The configuration 'auto.offset.reset' was supplied but isn't a known config. (org.apache.kafka.clients.producer.ProducerConfig)
sale_1 6822
sale_2 6822
sale_3 6822
sale_4 6822
sale_5 6822
sale_6 6822
sale_7 6822
sale_8 6822
sale_9 6822
sale_10 6822
Processed a total of 10 messages
09:19:30 ℹ️ Replicate from Metrics to Europe
  % Total    % Received % Xferd  Average Speed   Time    Time     Time  Current
                                 Dload  Upload   Total   Spent    Left  Speed
100  1537  100   751  100   786   4723   4943 --:--:-- --:--:-- --:--:--  9666
{
  "name": "replicate-metrics-to-europe",
  "config": {
    "connector.class": "io.confluent.connect.replicator.ReplicatorSourceConnector",
    "key.converter": "io.confluent.connect.replicator.util.ByteArrayConverter",
    "value.converter": "io.confluent.connect.replicator.util.ByteArrayConverter",
    "header.converter": "io.confluent.connect.replicator.util.ByteArrayConverter",
    "src.consumer.group.id": "replicate-metrics-to-us",
    "src.kafka.bootstrap.servers": "broker-metrics:9092",
    "dest.kafka.bootstrap.servers": "broker-europe:9092",
    "confluent.topic.replication.factor": "1",
    "provenance.header.enable": "true",
    "topic.whitelist": "sales",
    "offset.timestamps.commit": "false",
    "offset.translator.batch.period.ms": "5000",
    "name": "replicate-metrics-to-europe"
  },
  "tasks": [],
  "type": "source"
}
09:19:31 ℹ️ Replicate from Metrics to US
  % Total    % Received % Xferd  Average Speed   Time    Time     Time  Current
                                 Dload  Upload   Total   Spent    Left  Speed
100  1520  100   739  100   781   4707   4974 --:--:-- --:--:-- --:--:--  9681
{
  "name": "replicate-metrics-to-us",
  "config": {
    "connector.class": "io.confluent.connect.replicator.ReplicatorSourceConnector",
    "key.converter": "io.confluent.connect.replicator.util.ByteArrayConverter",
    "value.converter": "io.confluent.connect.replicator.util.ByteArrayConverter",
    "header.converter": "io.confluent.connect.replicator.util.ByteArrayConverter",
    "src.consumer.group.id": "replicate-metrics-to-us",
    "src.kafka.bootstrap.servers": "broker-metrics:9092",
    "dest.kafka.bootstrap.servers": "broker-us:9092",
    "confluent.topic.replication.factor": "1",
    "provenance.header.enable": "true",
    "topic.whitelist": "sales",
    "offset.timestamps.commit": "false",
    "offset.translator.batch.period.ms": "5000",
    "name": "replicate-metrics-to-us"
  },
  "tasks": [],
  "type": "source"
}
09:19:31 ℹ️ Wait for data to be replicated
09:20:01 ℹ️ Consumer with group my-consumer-group reads 10 messages in Europe cluster, starting from offset 10
sale_11 6822
sale_12 6822
sale_13 6822
sale_14 6822
sale_15 6822
sale_16 6822
sale_17 6822
sale_18 6822
sale_19 6822
sale_20 6822
Processed a total of 10 messages
09:20:07 ℹ️ Consumer with group my-consumer-group reads 10 messages in US cluster, starting from offset 10
sale_11 6822
sale_12 6822
sale_13 6822
sale_14 6822
sale_15 6822
sale_16 6822
sale_17 6822
sale_18 6822
sale_19 6822
sale_20 6822
Processed a total of 10 messages
```
