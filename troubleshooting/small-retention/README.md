<!-- omit in toc -->
# Test with very small retention (30 seconds)

- [Objective](#objective)
- [TL;DR](#tldr)
- [TESTING](#testing)
  - [Test with no activity on topic](#test-with-no-activity-on-topic)
  - [Test with activity on topic](#test-with-activity-on-topic)
  - [Test with activity on topic and segment.ms=15000](#test-with-activity-on-topic-and-segmentms15000)
  - [Impact of message timestamp](#impact-of-message-timestamp)

## Objective

Better understand what the link between topic configuration `retention.ms` and `segment.ms`

Definitive guide says:

```
The segment we are currently writing to is called an active segment.
The active segment is never deleted, so if you set log retention to only store a day
of data but each segment contains five days of data, you will really keep
data for five days because we can’t delete the data before the segment is closed.
```

## TL;DR

The definitive guide is correct, you need to have `segment.ms` lower than `retention.ms` otherwise cleanup will not happen before `segment.ms` is reached.
But there is one exception: if all the messages in the segment are *expired*, i.e they are older than the `retention.ms`. In that case, when the log cleaner is triggered, then the `retention.ms` will take precedence over the `segment.ms`, and the segment will be marked for deletion (and removed after `log.segment.delete.delay.ms` (default 60000))

Message timestamps are used in order to check if it is *expired*, so a producer sending old timestamps can have an impact on retention, see [Impact of message timestamp](#impact-of-message-timestamp)

## TESTING

**Important:** `log.retention.check.interval.ms` should be reduced otherwise cleanup only happens after 5 minutes (default):

```yml
  broker:
    environment:
      KAFKA_LOG_RETENTION_CHECK_INTERVAL_MS: 30000
```

### Test with no activity on topic

Simply run:

```
$ ./no-activity.sh
```

Create a topic `testtopic` with 30 seconds retention:

```bash
$ docker exec broker kafka-topics --create --topic testtopic --partitions 1 --replication-factor 1 --zookeeper zookeeper:2181 --config retention.ms=30000
```

Sending message to topic testtopic

```bash
$ docker exec -i broker kafka-console-producer --broker-list broker:9092 --topic testtopic << EOF
This is my message
EOF
```

```bash
$ docker exec broker ls -lrt /var/lib/kafka/data/testtopic-0/
```

Result:

```
12:24:55 Sending message to topic testtopic
>>total 8
-rw-r--r-- 1 root root 10485756 Feb 21 11:24 00000000000000000000.timeindex
-rw-r--r-- 1 root root 10485760 Feb 21 11:24 00000000000000000000.index
-rw-r--r-- 1 root root        8 Feb 21 11:24 leader-epoch-checkpoint
-rw-r--r-- 1 root root       86 Feb 21 11:24 00000000000000000000.log
```

sleep 60


Sending message to topic testtopic

```bash
docker exec -i broker kafka-console-producer --broker-list broker:9092 --topic testtopic << EOF
This is my message 2
EOF
```

```bash
docker exec broker ls -lrt /var/lib/kafka/data/testtopic-0/
```

Result: **CLEANUP**

```
12:25:57 Sending message to topic testtopic
>>total 20
-rw-r--r-- 1 root root       86 Feb 21 11:24 00000000000000000000.log.deleted
-rw-r--r-- 1 root root        0 Feb 21 11:25 00000000000000000000.index.deleted
-rw-r--r-- 1 root root       12 Feb 21 11:25 00000000000000000000.timeindex.deleted
-rw-r--r-- 1 root root       10 Feb 21 11:25 00000000000000000001.snapshot
-rw-r--r-- 1 root root        8 Feb 21 11:25 leader-epoch-checkpoint
-rw-r--r-- 1 root root 10485756 Feb 21 11:26 00000000000000000001.timeindex
-rw-r--r-- 1 root root 10485760 Feb 21 11:26 00000000000000000001.index
-rw-r--r-- 1 root root       88 Feb 21 11:26 00000000000000000001.log
```


### Test with activity on topic

Simply run:

```
$ ./activity.sh
```

Create a topic `testtopic` with 30 seconds retention:

```bash
$ docker exec broker kafka-topics --create --topic testtopic --partitions 1 --replication-factor 1 --zookeeper zookeeper:2181 --config retention.ms=30000
```

Sending message to topic testtopic every second for 50 seconds

```bash
$ i=0
while [ $i -le 50 ]
do
  Sending message $i to topic testtopic
docker exec -i broker kafka-console-producer --broker-list broker:9092 --topic testtopic << EOF
This is my message
EOF
  sleep 1
  ((i++))
done
```

```bash
$ docker exec broker ls -lrt /var/lib/kafka/data/testtopic-0/
```

Result: **NO CLEANUP**

```
-rw-r--r-- 1 root root        8 Feb 21 11:46 leader-epoch-checkpoint
-rw-r--r-- 1 root root 10485756 Feb 21 11:49 00000000000000000000.timeindex
-rw-r--r-- 1 root root 10485760 Feb 21 11:49 00000000000000000000.index
-rw-r--r-- 1 root root     4386 Feb 21 11:49 00000000000000000000.log
```

One minute after last message (no activity), cleanup is done:

```
-rw-r--r-- 1 root root     4386 Feb 21 11:49 00000000000000000000.log.deleted
-rw-r--r-- 1 root root        8 Feb 21 11:50 00000000000000000000.index.deleted
-rw-r--r-- 1 root root       24 Feb 21 11:50 00000000000000000000.timeindex.deleted
-rw-r--r-- 1 root root       10 Feb 21 11:50 00000000000000000051.snapshot
-rw-r--r-- 1 root root        0 Feb 21 11:50 00000000000000000051.log
-rw-r--r-- 1 root root        9 Feb 21 11:50 leader-epoch-checkpoint
-rw-r--r-- 1 root root 10485756 Feb 21 11:51 00000000000000000051.timeindex
```

### Test with activity on topic and segment.ms=15000

Simply run:

```
$ ./activity-small-segment-ms.sh
```

Create a topic `testtopic` with 30 seconds retention and `segment.ms` 15000:

```bash
$ docker exec broker kafka-topics --create --topic testtopic --partitions 1 --replication-factor 1 --zookeeper zookeeper:2181 --config retention.ms=30000 --config segment.ms=15000
```

Sending message to topic testtopic every second for 50 seconds

```bash
$ i=0
while [ $i -le 50 ]
do
  Sending message $i to topic testtopic
docker exec -i broker kafka-console-producer --broker-list broker:9092 --topic testtopic << EOF
This is my message
EOF
  sleep 1
  ((i++))
done
```

```bash
$ docker exec broker ls -lrt /var/lib/kafka/data/testtopic-0/
```

Result: **CLEANUP**

```
-rw-r--r-- 1 root root      344 Feb 21 12:02 00000000000000000030.log.deleted
-rw-r--r-- 1 root root       12 Feb 21 12:02 00000000000000000030.timeindex.deleted
-rw-r--r-- 1 root root        0 Feb 21 12:02 00000000000000000030.index.deleted
-rw-r--r-- 1 root root      344 Feb 21 12:02 00000000000000000034.log.deleted
-rw-r--r-- 1 root root       12 Feb 21 12:02 00000000000000000034.timeindex.deleted
-rw-r--r-- 1 root root        0 Feb 21 12:02 00000000000000000034.index.deleted
-rw-r--r-- 1 root root      344 Feb 21 12:02 00000000000000000038.log.deleted
-rw-r--r-- 1 root root       12 Feb 21 12:02 00000000000000000038.timeindex.deleted
-rw-r--r-- 1 root root        0 Feb 21 12:02 00000000000000000038.index.deleted
-rw-r--r-- 1 root root       10 Feb 21 12:02 00000000000000000042.snapshot
-rw-r--r-- 1 root root      344 Feb 21 12:03 00000000000000000042.log
-rw-r--r-- 1 root root       12 Feb 21 12:03 00000000000000000042.timeindex
-rw-r--r-- 1 root root        0 Feb 21 12:03 00000000000000000042.index
-rw-r--r-- 1 root root       10 Feb 21 12:03 00000000000000000046.snapshot
-rw-r--r-- 1 root root      344 Feb 21 12:03 00000000000000000046.log
-rw-r--r-- 1 root root       10 Feb 21 12:03 00000000000000000050.snapshot
-rw-r--r-- 1 root root       86 Feb 21 12:03 00000000000000000050.log
-rw-r--r-- 1 root root 10485760 Feb 21 12:03 00000000000000000050.index
-rw-r--r-- 1 root root       12 Feb 21 12:03 00000000000000000046.timeindex
-rw-r--r-- 1 root root        0 Feb 21 12:03 00000000000000000046.index
-rw-r--r-- 1 root root 10485756 Feb 21 12:03 00000000000000000050.timeindex
-rw-r--r-- 1 root root        9 Feb 21 12:03 leader-epoch-checkpoint
```

### Impact of message timestamp

In order to detect "activity", the log cleaner is looking at message timestamps.
If you have a producer that is sending messages with old timestamps, then the log cleaner will remove the segments as it will consider the segment as inactive (due to old timestamps).

If you can't fix the producer timestamps, you can set at topic level the config `message.timestamp.type=LogAppendTime` (by default it is `CreateTime`).

If you want to test, simply run:

```
$ ./old-timestamp.sh
```

* Test with `message.timestamp.type=CreateTime` (default)

Create a topic testtopic with 30 seconds retention

```bash
docker exec broker kafka-topics --create --topic testtopic --partitions 1 --replication-factor 1 --zookeeper zookeeper:2181 --config retention.ms=30000
```

Run a Java producer, it sends one request per second and uses old timestamps

```bash
docker exec producer bash -c "java -jar producer-1.0.0-jar-with-dependencies.jar" > producer.log 2>&1 &
```

sleep 60

```bash
docker exec broker ls -lrt /var/lib/kafka/data/testtopic-0/
```

Result: **CLEANUP**

```
-rw-r--r-- 1 root root     2370 Feb 21 12:53 00000000000000000258.log.deleted
-rw-r--r-- 1 root root       12 Feb 21 12:53 00000000000000000258.timeindex.deleted
-rw-r--r-- 1 root root        0 Feb 21 12:53 00000000000000000258.index.deleted
-rw-r--r-- 1 root root     2370 Feb 21 12:53 00000000000000000288.log.deleted
-rw-r--r-- 1 root root        0 Feb 21 12:53 00000000000000000288.index.deleted
-rw-r--r-- 1 root root       10 Feb 21 12:53 00000000000000000318.snapshot
-rw-r--r-- 1 root root       12 Feb 21 12:53 00000000000000000288.timeindex.deleted
-rw-r--r-- 1 root root       10 Feb 21 12:53 leader-epoch-checkpoint
-rw-r--r-- 1 root root 10485756 Feb 21 12:53 00000000000000000318.timeindex
-rw-r--r-- 1 root root 10485760 Feb 21 12:53 00000000000000000318.index
-rw-r--r-- 1 root root     1659 Feb 21 12:54 00000000000000000318.log
```

* Test with `message.timestamp.type=LogAppendTime`

Create a topic testtopic with 30 seconds retention and message.timestamp.type=LogAppendTime

```bash
docker exec broker kafka-topics --create --topic testtopic --partitions 1 --replication-factor 1 --zookeeper zookeeper:2181 --config retention.ms=30000 --config message.timestamp.type=LogAppendTime
```

Result: **NO CLEANUP**

```
-rw-r--r-- 1 root root        8 Feb 21 12:55 leader-epoch-checkpoint
-rw-r--r-- 1 root root 10485756 Feb 21 12:56 00000000000000000000.timeindex
-rw-r--r-- 1 root root 10485760 Feb 21 12:56 00000000000000000000.index
-rw-r--r-- 1 root root     4514 Feb 21 12:56 00000000000000000000.log
```

N.B: Control Center is reachable at [http://127.0.0.1:9021](http://127.0.0.1:9021])
