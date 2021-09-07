# Reproduction model


## Test description

### Environment:

KafkaJS version 1.15.0
Kafka version 2.8 (Confluent Platform 6.2.0)
NodeJS version from `node:lts-alpine` image

### How to run

Just run the script [`start-repro-timeout-63874.sh`](https://github.com/vdesabou/kafka-docker-playground/blob/master/other/client-kafkajs/start-repro-timeout-63874.sh)

### What the script does

It starts a zookeeper + 3 brokers + control-center

The producer [code](https://github.com/vdesabou/kafka-docker-playground/blob/master/other/client-kafkajs/repro-timeout-63874/client/producer.js) is waiting for all promises to return before sending next batch.

Config used is:

```js
const kafka = new Kafka({
  clientId: 'my-kafkajs-producer',
  brokers: ['broker1:9092','broker2:9092','broker3:9092'],
  enforceRequestTimeout: true,
  logLevel: logLevel.DEBUG,
  acks:1,
  connectionTimeout: 20000,
})
```

Create a topic kafkajs:

```
docker exec broker1 kafka-topics --create --topic kafkajs --partitions 3 --replication-factor 3 --zookeeper zookeeper:2181
```

Starting consumer. Logs are in consumer.log.

```
docker exec -i client-kafkajs node /usr/src/app/consumer.js > consumer.log 2>&1 &
```

Starting producer. Logs are in producer.log.

```
docker exec -i client-kafkajs node /usr/src/app/producer.js > producer.log 2>&1 &
```

Simulate a 45 seconds network issue with broker1 by blocking output traffic from broker1 to kafkaJS producer container:

```
ip=$(docker inspect -f '{{.Name}} - {{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $(docker ps -aq) | grep client-kafkajs | cut -d " " -f 3)
docker exec -e ip=$ip --privileged --user root broker1 sh -c "iptables -A OUTPUT -p tcp -d $ip -j DROP"
sleep 45
```

Setting back traffic to normal:

```
docker exec -e ip=$ip --privileged --user root broker1 sh -c "iptables -D OUTPUT -p tcp -d $ip -j DROP"
```

let the test run 3 minutes


## Results

### Test with 10 minutes connection error

Traffic is blocked at `12:13:25`:

```log
12:13:25 ℹ️ Simulate a 45 seconds network issue with broker1 by blocking output traffic from broker1 to kafkaJS producer container
```

We can see that we are discarding events 6 seconds later only:

```
[[12:13:31.188]] [LOG]   ERROR: Discarding events !!!!
```

30 seconds after we see the timeouts

```log
[[12:13:55.620]] [LOG]   Producer request timed out at 1631016835620 {"broker":"broker1:9092","clientId":"my-kafkajs-producer","correlationId":264,"createdAt":1631016805603,"sentAt":1631016805603,"pendingDuration":0,"apiName":"Produce","apiKey":0,"apiVersion":7}
[[12:13:55.621]] [LOG]   Producer request timed out at 1631016835621 {"broker":"broker1:9092","clientId":"my-kafkajs-producer","correlationId":265,"createdAt":1631016805604,"sentAt":1631016805604,"pendingDuration":0,"apiName":"Produce","apiKey":0,"apiVersion":7}
[[12:13:55.621]] [LOG]   Producer request timed out at 1631016835621 {"broker":"broker1:9092","clientId":"my-kafkajs-producer","correlationId":266,"createdAt":1631016805604,"sentAt":1631016805604,"pendingDuration":0,"apiName":"Produce","apiKey":0,"apiVersion":7}
[[12:13:55.621]] [LOG]   Producer request timed out at 1631016835621 {"broker":"broker1:9092","clientId":"my-kafkajs-producer","correlationId":267,"createdAt":1631016805607,"sentAt":1631016805607,"pendingDuration":0,"apiName":"Produce","apiKey":0,"apiVersion":7}
[[12:13:55.622]] [LOG]   Producer request timed out at 1631016835621 {"broker":"broker1:9092","clientId":"my-kafkajs-producer","correlationId":268,"createdAt":1631016805608,"sentAt":1631016805608,"pendingDuration":0,"apiName":"Produce","apiKey":0,"apiVersion":7}
[[12:13:55.622]] [LOG]   Producer request timed out at 1631016835622 {"broker":"broker1:9092","clientId":"my-kafkajs-producer","correlationId":269,"createdAt":1631016805608,"sentAt":1631016805609,"pendingDuration":1,"apiName":"Produce","apiKey":0,"apiVersion":7}

...

[[12:13:55.627]] [ERROR] {"level":"ERROR","timestamp":"2021-09-07T12:13:55.627Z","logger":"kafkajs","message":"[Producer] Request Produce(key: 0, version: 7) timed out","retryCount":0,"retryTime":272}
[[12:13:55.628]] [ERROR] {"level":"ERROR","timestamp":"2021-09-07T12:13:55.628Z","logger":"kafkajs","message":"[Producer] Request Produce(key: 0, version: 7) timed out","retryCount":0,"retryTime":292}
[[12:13:55.629]] [ERROR] {"level":"ERROR","timestamp":"2021-09-07T12:13:55.629Z","logger":"kafkajs","message":"[Producer] Request Produce(key: 0, version: 7) timed out","retryCount":0,"retryTime":242}
[[12:13:55.629]] [ERROR] {"level":"ERROR","timestamp":"2021-09-07T12:13:55.629Z","logger":"kafkajs","message":"[Producer] Request Produce(key: 0, version: 7) timed out","retryCount":0,"retryTime":344}
[[12:13:55.629]] [ERROR] {"level":"ERROR","timestamp":"2021-09-07T12:13:55.629Z","logger":"kafkajs","message":"[Producer] Request Produce(key: 0, version: 7) timed out","retryCount":0,"retryTime":339}
[[12:13:55.629]] [ERROR] {"level":"ERROR","timestamp":"2021-09-07T12:13:55.629Z","logger":"kafkajs","message":"[Producer] Request Produce(key: 0, version: 7) timed out","retryCount":0,"retryTime":349}
[[12:13:55.630]] [ERROR] {"level":"ERROR","timestamp":"2021-09-07T12:13:55.630Z","logger":"kafkajs","message":"[Producer] Request Produce(key: 0, version: 7) timed out","retryCount":0,"retryTime":289}
[[12:13:55.630]] [ERROR] {"level":"ERROR","timestamp":"2021-09-07T12:13:55.630Z","logger":"kafkajs","message":"[Producer] Request Produce(key: 0, version: 7) timed out","retryCount":0,"retryTime":327}
```

Then traffic is unblocked at `12:14:10`

```log
[[12:14:18.040]] [LOG]   ERROR: Discarding events !!!!
[[12:14:18.042]] [WARN]  {"level":"WARN","timestamp":"2021-09-07T12:14:18.042Z","logger":"kafkajs","message":"[RequestQueue] Response without match","clientId":"my-kafkajs-producer","broker":"broker1:9092","correlationId":264}
[[12:14:18.042]] [WARN]  {"level":"WARN","timestamp":"2021-09-07T12:14:18.042Z","logger":"kafkajs","message":"[RequestQueue] Response without match","clientId":"my-kafkajs-producer","broker":"broker1:9092","correlationId":265}
[[12:14:18.042]] [WARN]  {"level":"WARN","timestamp":"2021-09-07T12:14:18.042Z","logger":"kafkajs","message":"[RequestQueue] Response without match","clientId":"my-kafkajs-producer","broker":"broker1:9092","correlationId":266}
[[12:14:18.042]] [WARN]  {"level":"WARN","timestamp":"2021-09-07T12:14:18.042Z","logger":"kafkajs","message":"[RequestQueue] Response without match","clientId":"my-kafkajs-producer","broker":"broker1:9092","correlationId":267}
[[12:14:18.043]] [WARN]  {"level":"WARN","timestamp":"2021-09-07T12:14:18.043Z","logger":"kafkajs","message":"[RequestQueue] Response without match","clientId":"my-kafkajs-producer","broker":"broker1:9092","correlationId":268}
[[12:14:18.043]] [WARN]  {"level":"WARN","timestamp":"2021-09-07T12:14:18.043Z","logger":"kafkajs","message":"[RequestQueue] Response without match","clientId":"my-kafkajs-producer","broker":"broker1:9092","correlationId":269}
[[12:14:18.043]] [WARN]  {"level":"WARN","timestamp":"2021-09-07T12:14:18.043Z","logger":"kafkajs","message":"[RequestQueue] Response without match","clientId":"my-kafkajs-producer","broker":"broker1:9092","correlationId":270}
[[12:14:18.043]] [WARN]  {"level":"WARN","timestamp":"2021-09-07T12:14:18.043Z","logger":"kafkajs","message":"[RequestQueue] Response without match","clientId":"my-kafkajs-producer","broker":"broker1:9092","correlationId":271}
[[12:14:18.044]] [WARN]  {"level":"WARN","timestamp":"2021-09-07T12:14:18.043Z","logger":"kafkajs","message":"[RequestQueue] Response without match","clientId":"my-kafkajs-producer","broker":"broker1:9092","correlationId":272}
[[12:14:18.044]] [WARN]  {"level":"WARN","timestamp":"2021-09-07T12:14:18.044Z","logger":"kafkajs","message":"[RequestQueue] Response without match","clientId":"my-kafkajs-producer","broker":"broker1:9092","correlationId":273}
[[12:14:18.044]] [WARN]  {"level":"WARN","timestamp":"2021-09-07T12:14:18.044Z","logger":"kafkajs","message":"[RequestQueue] Response without match","clientId":"my-kafkajs-producer","broker":"broker1:9092","correlationId":274}
[[12:14:18.044]] [WARN]  {"level":"WARN","timestamp":"2021-09-07T12:14:18.044Z","logger":"kafkajs","message":"[RequestQueue] Response without match","clientId":"my-kafkajs-producer","broker":"broker1:9092","correlationId":275}
[[12:14:18.045]] [WARN]  {"level":"WARN","timestamp":"2021-09-07T12:14:18.044Z","logger":"kafkajs","message":"[RequestQueue] Response without match","clientId":"my-kafkajs-producer","broker":"broker1:9092","correlationId":276}
[[12:14:18.045]] [WARN]  {"level":"WARN","timestamp":"2021-09-07T12:14:18.045Z","logger":"kafkajs","message":"[RequestQueue] Response without match","clientId":"my-kafkajs-producer","broker":"broker1:9092","correlationId":277}
[[12:14:18.045]] [WARN]  {"level":"WARN","timestamp":"2021-09-07T12:14:18.045Z","logger":"kafkajs","message":"[RequestQueue] Response without match","clientId":"my-kafkajs-producer","broker":"broker1:9092","correlationId":278}
[[12:14:18.045]] [WARN]  {"level":"WARN","timestamp":"2021-09-07T12:14:18.045Z","logger":"kafkajs","message":"[RequestQueue] Response without match","clientId":"my-kafkajs-producer","broker":"broker1:9092","correlationId":279}
[[12:14:18.045]] [WARN]  {"level":"WARN","timestamp":"2021-09-07T12:14:18.045Z","logger":"kafkajs","message":"[RequestQueue] Response without match","clientId":"my-kafkajs-producer","broker":"broker1:9092","correlationId":280}
[[12:14:18.046]] [WARN]  {"level":"WARN","timestamp":"2021-09-07T12:14:18.046Z","logger":"kafkajs","message":"[RequestQueue] Response without match","clientId":"my-kafkajs-producer","broker":"broker1:9092","correlationId":281}
[[12:14:18.046]] [WARN]  {"level":"WARN","timestamp":"2021-09-07T12:14:18.046Z","logger":"kafkajs","message":"[RequestQueue] Response without match","clientId":"my-kafkajs-producer","broker":"broker1:9092","correlationId":282}
[[12:14:18.046]] [LOG]   Success in sending data
[[12:14:18.047]] [LOG]   Success in sending data
[[12:14:18.047]] [LOG]   Success in sending data
[[12:14:18.048]] [LOG]   Success in sending data
[[12:14:18.050]] [LOG]   Success in sending data
[[12:14:18.050]] [LOG]   ERROR: Discarding events !!!!
[[12:14:18.051]] [LOG]   Success in sending data
[[12:14:18.052]] [LOG]   Success in sending data
[[12:14:18.053]] [LOG]   Success in sending data
[[12:14:18.054]] [LOG]   Success in sending data
[[12:14:18.055]] [LOG]   Success in sending data
[[12:14:18.056]] [LOG]   Success in sending data
[[12:14:18.056]] [LOG]   Success in sending data
[[12:14:18.057]] [LOG]   Success in sending data
[[12:14:18.058]] [LOG]   Success in sending data
[[12:14:18.059]] [LOG]   Success in sending data
[[12:14:18.059]] [LOG]   Success in sending data
[[12:14:18.060]] [LOG]   Success in sending data
[[12:14:18.060]] [LOG]   ERROR: Discarding events !!!!
[[12:14:18.061]] [LOG]   Success in sending data
[[12:14:18.062]] [LOG]   Success in sending data
[[12:14:18.062]] [LOG]   lock released { duration: 52462 }
```

We can see that lock duration lasted 52 seconds, only for one broker having connectivity issue.
