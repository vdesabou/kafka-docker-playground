# Redis Sink connector

## Objective

Quickly test [Redis Sink](https://docs.confluent.io/current/connect/kafka-connect-hbase/index.html#quick-start) connector.

## Pre-requisites

* `docker-compose` (example `brew cask install docker`)



## How to run

Simply run:

```
$ ./redis-sink.sh
```

## Details of what the script is doing

Sending messages to topic users

```bash
$ docker exec -i broker kafka-console-producer --broker-list broker:9092 --topic users --property parse.key=true --property key.separator=, << EOF
key1,value1
key2,value2
key3,value3
EOF
```

Creating Redis sink connector

```bash
$ docker exec connect \
     curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "com.github.jcustenborder.kafka.connect.redis.RedisSinkConnector",
                    "redis.hosts": "redis:6379",
                    "tasks.max": "1",
                    "key.converter":"org.apache.kafka.connect.storage.StringConverter",
                    "value.converter":"org.apache.kafka.connect.storage.StringConverter",
                    "topics": "users"
          }' \
     http://localhost:8083/connectors/redis-sink/config | jq .
```

Verify data is in Redis:

```
$ docker exec -it redis redis-cli COMMAND GETKEYS "MSET" "key1" "value1" "key2" "value2" "key3" "value3"
```

Results:

```bash
1) "key1"
2) "key2"
3) "key3"
```

```
$ $ docker exec -it redis redis-cli COMMAND GETKEYS "MSET" "__kafka.offset.users.0" "{\"topic\":\"users\",\"partition\":0,\"offset\":2}"
```

Results:

```bash
1) "__kafka.offset.users.0"
```




N.B: Control Center is reachable at [http://127.0.0.1:9021](http://127.0.0.1:9021])
