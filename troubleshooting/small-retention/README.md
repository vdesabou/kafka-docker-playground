# Test with very small retention (30 seconds)


## Objective


Producer --> topic testtopic --> Consumer (with Producer) --> topic outputtesttopic


## How to run

Simply run:

```
$ ./start.sh
```

## Details of what the script is doing

**The issue does not happen with CP 5.4.0**

The producer is using old timestamp. In our case hard-coded to `02/13/2020 @ 8:38am (UTC)`. It is configured with acks=all and enable.idempotence=true.

Create a topic `testtopic` with 30 seconds retention and 15 seconds segment:

```bash
$ docker exec broker kafka-topics --create --topic testtopic --partitions 1 --replication-factor 1 --zookeeper zookeeper:2181 --config segment.ms=15000 --config retention.ms=30000 --config message.timestamp.type=CreateTime
```

Note: `message.timestamp.type`=`CreateTime` is default.


With 5.3.1, we get errors in broker:

```log
[2020-02-13 16:10:24,167] ERROR [ReplicaManager broker=1] Error processing append operation on partition outputtesttopic-0 (kafka.server.ReplicaManager)
org.apache.kafka.common.errors.UnknownProducerIdException: Found no record of producerId=0 on the broker at offset 57in partition outputtesttopic-0. It is possible that the last message with the producerId=0 has been removed due to hitting the retention limit.
```

and in producer:

```log
Processing key null value message 57
[2020-02-13 16:10:24,168] INFO [Producer clientId=producer-1] Resetting sequence number of batch with current sequence 30 for partition outputtesttopic-0 to 0 (org.apache.kafka.clients.producer.internals.TransactionManager)
[2020-02-13 16:10:24,168] WARN [Producer clientId=producer-1] Got error produce response with correlation id 63 on topic-partition outputtesttopic-0, retrying (2147483646 attempts left). Error: UNKNOWN_PRODUCER_ID (org.apache.kafka.clients.producer.internals.Sender)
Produced record to topic outputtesttopic partition [0] @ offset 57
 and timestamp 1581583089003
```

But no duplicate in topic

To fix these errors, we can set `message.timestamp.type`=`LogAppendTime`at topic level


N.B: Control Center is reachable at [http://127.0.0.1:9021](http://127.0.0.1:9021])
