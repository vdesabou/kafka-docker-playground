# Testing log compaction

**Important:** `log.retention.check.interval.ms` should be reduced otherwise cleanup only happens after 5 minutes (default):

```yml
  broker:
    environment:
      KAFKA_LOG_RETENTION_CHECK_INTERVAL_MS: 30000
```

## How to run

Simply run:

```
$ ./repro-no-compaction-idle-topic.sh
```


## Details of what the script is doing

create a topic `testtopic` with 30 seconds `segment.ms`

```bash
$ docker exec broker kafka-topics --create --topic testtopic --partitions 1 --replication-factor 1 --zookeeper zookeeper:2181 --config segment.ms=30000 --config cleanup.policy=compact --config min.cleanable.dirty.ratio=0.0
```

Describe new topic `testtopic`

```bash
$ docker exec zookeeper kafka-topics --describe --topic testtopic --zookeeper zookeeper:2181
```

```
Topic: testtopic        PartitionCount: 1       ReplicationFactor: 1    Configs: cleanup.policy=compact,segment.ms=30000,min.cleanable.dirty.ratio=0.0
        Topic: testtopic        Partition: 0    Leader: 1       Replicas: 1     Isr: 1
```

```bash
i=0
while [ $i -le 4 ]
do
  Sending message key: <key$(($i % 2))> and value <value$i> to topic testtopic

docker exec -i broker kafka-console-producer --broker-list broker:9092 --topic testtopic --property parse.key=true --property key.separator=, << EOF
key$(($i % 2)),value$i
EOF
  sleep 1
  ((i++))
done
```

```
15:07:43 Sending message key: <key0> and value <value0> to topic testtopic
15:07:48 Sending message key: <key1> and value <value1> to topic testtopic
15:07:52 Sending message key: <key0> and value <value2> to topic testtopic
15:07:55 Sending message key: <key1> and value <value3> to topic testtopic
15:07:59 Sending message key: <key0> and value <value4> to topic testtopic
```

Check files on data dir: current log segment should be 0

```bash
$ docker exec broker ls -lrt /var/lib/kafka/data/testtopic-0/
```

```
total 8
-rw-r--r-- 1 root root 10485756 Mar  4 14:07 00000000000000000000.timeindex
-rw-r--r-- 1 root root 10485760 Mar  4 14:07 00000000000000000000.index
-rw-r--r-- 1 root root        8 Mar  4 14:07 leader-epoch-checkpoint
-rw-r--r-- 1 root root      390 Mar  4 14:08 00000000000000000000.log
```

Sleeping 40 seconds

```bash
$ sleep 40
```

Check files on data dir: current log segment is still 0 as idle

```bash
$ docker exec broker ls -lrt /var/lib/kafka/data/testtopic-0/
```

```
total 8
-rw-r--r-- 1 root root 10485756 Mar  4 14:07 00000000000000000000.timeindex
-rw-r--r-- 1 root root 10485760 Mar  4 14:07 00000000000000000000.index
-rw-r--r-- 1 root root        8 Mar  4 14:07 leader-epoch-checkpoint
-rw-r--r-- 1 root root      390 Mar  4 14:08 00000000000000000000.log
```

Compaction times: if no ouput, there was no compaction

```bash
$ docker container logs --tail=500 broker | grep kafka-log-cleaner-thread
```

*No Ouput*

Check data in topic: there was no compaction

```bash
$ timeout 10 docker exec broker kafka-console-consumer --bootstrap-server broker:9092 --topic testtopic --from-beginning --property print.key=true --property key.separator=,
```

```
key0,value0
key1,value1
key0,value2
key1,value3
key0,value4
```

Inject one more message

```bash
$ docker exec -i broker kafka-console-producer --broker-list broker:9092 --topic testtopic --property parse.key=true --property key.separator=, << EOF
key1,value5
EOF
```

Check files on data dir: log segment should be rolled

```bash
$ docker exec broker ls -lrt /var/lib/kafka/data/testtopic-0/
```

```
total 20
-rw-r--r-- 1 root root        8 Mar  4 14:07 leader-epoch-checkpoint
-rw-r--r-- 1 root root      390 Mar  4 14:08 00000000000000000000.log
-rw-r--r-- 1 root root       12 Mar  4 14:08 00000000000000000000.timeindex
-rw-r--r-- 1 root root        0 Mar  4 14:08 00000000000000000000.index
-rw-r--r-- 1 root root       10 Mar  4 14:08 00000000000000000005.snapshot
-rw-r--r-- 1 root root 10485756 Mar  4 14:08 00000000000000000005.timeindex
-rw-r--r-- 1 root root       78 Mar  4 14:08 00000000000000000005.log
-rw-r--r-- 1 root root 10485760 Mar  4 14:08 00000000000000000005.index
```

Sleeping 20 seconds

```bash
$ sleep 20
```

Compaction times: check that compaction happened

```bash
$ docker container logs --tail=500 broker | grep kafka-log-cleaner-thread
```

```
[2020-03-04 14:09:01,266] INFO [kafka-log-cleaner-thread-0]:
```

Check data in topic: there was compaction

```bash
$ timeout 10 docker exec broker kafka-console-consumer --bootstrap-server broker:9092 --topic testtopic --from-beginning --property print.key=true --property key.separator=,
```

```
key1,value3
key0,value4
key1,value5
```

N.B: Control Center is reachable at [http://127.0.0.1:9021](http://127.0.0.1:9021])
