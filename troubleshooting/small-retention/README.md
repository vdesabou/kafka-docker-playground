# Test with very small retention (30 seconds)


## Objective

Better understand what the link between `retention.ms` and `segment.ms`


Important: `log.retention.check.interval.ms` should be reduced otherwise cleanup only happens after 5 minutes (default):

```yml
  broker:
    environment:
      KAFKA_LOG_RETENTION_CHECK_INTERVAL_MS: 30000
```

## Test with no activity on topic

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

Result (cleanup):

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


## Test with activity on topic

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
  log "Sending message $i to topic testtopic"
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

Result (no cleanup):

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

## Test with activity on topic and segment.ms=15000

Simply run:

```
$ ./activity.sh
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
  log "Sending message $i to topic testtopic"
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

Result (cleanup):

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

N.B: Control Center is reachable at [http://127.0.0.1:9021](http://127.0.0.1:9021])
