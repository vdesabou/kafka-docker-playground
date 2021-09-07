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

The producer [code](https://github.com/vdesabou/kafka-docker-playground/blob/master/other/client-kafkajs/repro-timeout-63874/client/producer.js) is waiting for all promises to return before sending next batch (using a `lock` attribute):

```js
function deQueueBatch() {
  if  (!lock) {
    lock = true
    const now = new Date();
    const used = process.memoryUsage().heapUsed / 1024 / 1024;
    console.log(`Memory: ${Math.round(used * 100) / 100} MB`);
    console.log(`Queue size: ${batch.length}`)

    var batches = splitQueue(batch)
    var promises = batches.map(function (events) {
        return sendData(events)
          .catch(function(result) {
              console.log(`Error in sending data`)
              return result
          }).then(function(result) {
              console.log(`Success in sending data`)
              return result
          })
    })

    Promise.allSettled(promises).then(function(results) {
        lock = false
        console.log('lock released', {duration: new Date() - now});
        //results.forEach((result) => console.log(result))
    })
  }
}
```

When queue is more than 500 batches, we start discarding events:

```js
function addDataToQueue() {
    if (batch.length < 500) {
        batch.push({value: bigString})
    } else {
        console.log(`ERROR: Discarding events !!!!`)
    }
}
```

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

### Test with locking

In normal scenario the lock takes between 70 to 250ms.

Example:

```log
[[12:57:41.393]] [LOG]   lock released { duration: 155 }
```

Traffic is blocked at `12:57:50`:

```log
12:57:50 ℹ️ Simulate a 45 seconds network issue with broker1 by blocking output traffic from broker1 to kafkaJS producer container
```

We can see that we are discarding events 6 seconds later only:

```log
[[12:57:56.453]] [LOG]   ERROR: Discarding events !!!!
```

30 seconds after we see the timeouts

```log
[[12:58:21.306]] [LOG]   Producer request timed out at 1631019501305 {"broker":"broker1:9092","clientId":"my-kafkajs-producer","correlationId":266,"createdAt":1631019471245,"sentAt":1631019471245,"pendingDuration":0,"apiName":"Produce","apiKey":0,"apiVersion":7}
[[12:58:21.307]] [LOG]   Producer request timed out at 1631019501306 {"broker":"broker1:9092","clientId":"my-kafkajs-producer","correlationId":267,"createdAt":1631019471248,"sentAt":1631019471248,"pendingDuration":0,"apiName":"Produce","apiKey":0,"apiVersion":7}
[[12:58:21.307]] [LOG]   Producer request timed out at 1631019501307 {"broker":"broker1:9092","clientId":"my-kafkajs-producer","correlationId":268,"createdAt":1631019471249,"sentAt":1631019471250,"pendingDuration":1,"apiName":"Produce","apiKey":0,"apiVersion":7}

...

[[12:58:21.314]] [ERROR] {"level":"ERROR","timestamp":"2021-09-07T12:58:21.314Z","logger":"kafkajs","message":"[Producer] Request Produce(key: 0, version: 7) timed out","retryCount":0,"retryTime":258}
[[12:58:21.315]] [ERROR] {"level":"ERROR","timestamp":"2021-09-07T12:58:21.315Z","logger":"kafkajs","message":"[Producer] Request Produce(key: 0, version: 7) timed out","retryCount":0,"retryTime":312}
[[12:58:21.315]] [ERROR] {"level":"ERROR","timestamp":"2021-09-07T12:58:21.315Z","logger":"kafkajs","message":"[Producer] Request Produce(key: 0, version: 7) timed out","retryCount":0,"retryTime":338}
[[12:58:21.315]] [ERROR] {"level":"ERROR","timestamp":"2021-09-07T12:58:21.315Z","logger":"kafkajs","message":"[Producer] Request Produce(key: 0, version: 7) timed out","retryCount":0,"retryTime":250}
[[12:58:21.316]] [ERROR] {"level":"ERROR","timestamp":"2021-09-07T12:58:21.315Z","logger":"kafkajs","message":"[Producer] Request Produce(key: 0, version: 7) timed out","retryCount":0,"retryTime":318}
[[12:58:21.316]] [ERROR] {"level":"ERROR","timestamp":"2021-09-07T12:58:21.316Z","logger":"kafkajs","message":"[Producer] Request Produce(key: 0, version: 7) timed out","retryCount":0,"retryTime":274}
```

Then traffic is unblocked at `12:58:36`

```log
12:58:36 ℹ️ Setting back traffic to normal
```

```log
[[12:58:44.568]] [LOG]   ERROR: Discarding events !!!!
[[12:58:44.578]] [WARN]  {"level":"WARN","timestamp":"2021-09-07T12:58:44.578Z","logger":"kafkajs","message":"[RequestQueue] Response without match","clientId":"my-kafkajs-producer","broker":"broker1:9092","correlationId":266}
[[12:58:44.579]] [WARN]  {"level":"WARN","timestamp":"2021-09-07T12:58:44.579Z","logger":"kafkajs","message":"[RequestQueue] Response without match","clientId":"my-kafkajs-producer","broker":"broker1:9092","correlationId":267}
[[12:58:44.580]] [WARN]  {"level":"WARN","timestamp":"2021-09-07T12:58:44.579Z","logger":"kafkajs","message":"[RequestQueue] Response without match","clientId":"my-kafkajs-producer","broker":"broker1:9092","correlationId":268}
[[12:58:44.580]] [WARN]  {"level":"WARN","timestamp":"2021-09-07T12:58:44.580Z","logger":"kafkajs","message":"[RequestQueue] Response without match","clientId":"my-kafkajs-producer","broker":"broker1:9092","correlationId":269}
[[12:58:44.580]] [WARN]  {"level":"WARN","timestamp":"2021-09-07T12:58:44.580Z","logger":"kafkajs","message":"[RequestQueue] Response without match","clientId":"my-kafkajs-producer","broker":"broker1:9092","correlationId":270}
[[12:58:44.581]] [WARN]  {"level":"WARN","timestamp":"2021-09-07T12:58:44.581Z","logger":"kafkajs","message":"[RequestQueue] Response without match","clientId":"my-kafkajs-producer","broker":"broker1:9092","correlationId":271}
[[12:58:44.581]] [WARN]  {"level":"WARN","timestamp":"2021-09-07T12:58:44.581Z","logger":"kafkajs","message":"[RequestQueue] Response without match","clientId":"my-kafkajs-producer","broker":"broker1:9092","correlationId":272}
[[12:58:44.582]] [WARN]  {"level":"WARN","timestamp":"2021-09-07T12:58:44.581Z","logger":"kafkajs","message":"[RequestQueue] Response without match","clientId":"my-kafkajs-producer","broker":"broker1:9092","correlationId":273}
[[12:58:44.582]] [WARN]  {"level":"WARN","timestamp":"2021-09-07T12:58:44.582Z","logger":"kafkajs","message":"[RequestQueue] Response without match","clientId":"my-kafkajs-producer","broker":"broker1:9092","correlationId":274}
[[12:58:44.582]] [WARN]  {"level":"WARN","timestamp":"2021-09-07T12:58:44.582Z","logger":"kafkajs","message":"[RequestQueue] Response without match","clientId":"my-kafkajs-producer","broker":"broker1:9092","correlationId":275}
[[12:58:44.583]] [WARN]  {"level":"WARN","timestamp":"2021-09-07T12:58:44.583Z","logger":"kafkajs","message":"[RequestQueue] Response without match","clientId":"my-kafkajs-producer","broker":"broker1:9092","correlationId":276}
[[12:58:44.583]] [WARN]  {"level":"WARN","timestamp":"2021-09-07T12:58:44.583Z","logger":"kafkajs","message":"[RequestQueue] Response without match","clientId":"my-kafkajs-producer","broker":"broker1:9092","correlationId":277}
[[12:58:44.583]] [WARN]  {"level":"WARN","timestamp":"2021-09-07T12:58:44.583Z","logger":"kafkajs","message":"[RequestQueue] Response without match","clientId":"my-kafkajs-producer","broker":"broker1:9092","correlationId":278}
[[12:58:44.584]] [WARN]  {"level":"WARN","timestamp":"2021-09-07T12:58:44.584Z","logger":"kafkajs","message":"[RequestQueue] Response without match","clientId":"my-kafkajs-producer","broker":"broker1:9092","correlationId":279}
[[12:58:44.584]] [WARN]  {"level":"WARN","timestamp":"2021-09-07T12:58:44.584Z","logger":"kafkajs","message":"[RequestQueue] Response without match","clientId":"my-kafkajs-producer","broker":"broker1:9092","correlationId":280}
[[12:58:44.584]] [WARN]  {"level":"WARN","timestamp":"2021-09-07T12:58:44.584Z","logger":"kafkajs","message":"[RequestQueue] Response without match","clientId":"my-kafkajs-producer","broker":"broker1:9092","correlationId":281}
[[12:58:44.585]] [WARN]  {"level":"WARN","timestamp":"2021-09-07T12:58:44.585Z","logger":"kafkajs","message":"[RequestQueue] Response without match","clientId":"my-kafkajs-producer","broker":"broker1:9092","correlationId":282}
[[12:58:44.585]] [WARN]  {"level":"WARN","timestamp":"2021-09-07T12:58:44.585Z","logger":"kafkajs","message":"[RequestQueue] Response without match","clientId":"my-kafkajs-producer","broker":"broker1:9092","correlationId":283}
[[12:58:44.585]] [WARN]  {"level":"WARN","timestamp":"2021-09-07T12:58:44.585Z","logger":"kafkajs","message":"[RequestQueue] Response without match","clientId":"my-kafkajs-producer","broker":"broker1:9092","correlationId":284}
[[12:58:44.586]] [LOG]   ERROR: Discarding events !!!!
[[12:58:44.587]] [LOG]   Success in sending data
[[12:58:44.587]] [LOG]   Success in sending data
[[12:58:44.587]] [LOG]   Success in sending data
[[12:58:44.587]] [LOG]   Success in sending data
[[12:58:44.588]] [LOG]   Success in sending data
[[12:58:44.589]] [LOG]   Success in sending data
[[12:58:44.590]] [LOG]   Success in sending data
[[12:58:44.592]] [LOG]   Success in sending data
[[12:58:44.593]] [LOG]   Success in sending data
[[12:58:44.594]] [LOG]   Success in sending data
[[12:58:44.595]] [LOG]   Success in sending data
[[12:58:44.595]] [LOG]   ERROR: Discarding events !!!!
[[12:58:44.597]] [LOG]   Success in sending data
[[12:58:44.598]] [LOG]   Success in sending data
[[12:58:44.600]] [LOG]   Success in sending data
[[12:58:44.601]] [LOG]   Success in sending data
[[12:58:44.601]] [LOG]   Success in sending data
[[12:58:44.603]] [LOG]   Success in sending data
[[12:58:44.604]] [LOG]   Success in sending data
[[12:58:44.605]] [LOG]   Success in sending data
[[12:58:44.605]] [LOG]   lock released { duration: 53363 }
```

**We can see that lock duration lasted 53 seconds, only for one broker having connectivity issue !!**

Then `broker1` is stopped:

```log
12:59:36 ℹ️ Stop broker1
```

We get a bunch of `This server is not the leader for that topic-partition` errors, which is expected, then the producer refreshes its metadata and successfully send the requests. The lock took 603ms:

```log
[[12:59:37.174]] [ERROR] {"level":"ERROR","timestamp":"2021-09-07T12:59:37.173Z","logger":"kafkajs","message":"[Connection] Response Produce(key: 0, version: 7)","broker":"broker1:9092","clientId":"my-kafkajs-producer","error":"This server is not the leader for that topic-partition","correlationId":1367,"size":55}
[[12:59:37.175]] [ERROR] {"level":"ERROR","timestamp":"2021-09-07T12:59:37.175Z","logger":"kafkajs","message":"[Producer] Failed to send messages: This server is not the leader for that topic-partition","retryCount":0,"retryTime":343}
[[12:59:37.178]] [ERROR] {"level":"ERROR","timestamp":"2021-09-07T12:59:37.178Z","logger":"kafkajs","message":"[Connection] Response Produce(key: 0, version: 7)","broker":"broker1:9092","clientId":"my-kafkajs-producer","error":"This server is not the leader for that topic-partition","correlationId":1368,"size":55}
[[12:59:37.178]] [ERROR] {"level":"ERROR","timestamp":"2021-09-07T12:59:37.178Z","logger":"kafkajs","message":"[Producer] Failed to send messages: This server is not the leader for that topic-partition","retryCount":0,"retryTime":283}
[[12:59:37.199]] [ERROR] {"level":"ERROR","timestamp":"2021-09-07T12:59:37.199Z","logger":"kafkajs","message":"[Connection] Response Produce(key: 0, version: 7)","broker":"broker1:9092","clientId":"my-kafkajs-producer","error":"This server is not the leader for that topic-partition","correlationId":1369,"size":55}
[[12:59:37.199]] [ERROR] {"level":"ERROR","timestamp":"2021-09-07T12:59:37.199Z","logger":"kafkajs","message":"[Producer] Failed to send messages: This server is not the leader for that topic-partition","retryCount":0,"retryTime":321}
[[12:59:37.210]] [ERROR] {"level":"ERROR","timestamp":"2021-09-07T12:59:37.210Z","logger":"kafkajs","message":"[Connection] Response Produce(key: 0, version: 7)","broker":"broker1:9092","clientId":"my-kafkajs-producer","error":"This server is not the leader for that topic-partition","correlationId":1370,"size":55}
[[12:59:37.211]] [ERROR] {"level":"ERROR","timestamp":"2021-09-07T12:59:37.210Z","logger":"kafkajs","message":"[Producer] Failed to send messages: This server is not the leader for that topic-partition","retryCount":0,"retryTime":245}
[[12:59:37.215]] [ERROR] {"level":"ERROR","timestamp":"2021-09-07T12:59:37.215Z","logger":"kafkajs","message":"[Connection] Response Produce(key: 0, version: 7)","broker":"broker1:9092","clientId":"my-kafkajs-producer","error":"This server is not the leader for that topic-partition","correlationId":1371,"size":55}
[[12:59:37.216]] [ERROR] {"level":"ERROR","timestamp":"2021-09-07T12:59:37.216Z","logger":"kafkajs","message":"[Producer] Failed to send messages: This server is not the leader for that topic-partition","retryCount":0,"retryTime":343}
[[12:59:37.219]] [ERROR] {"level":"ERROR","timestamp":"2021-09-07T12:59:37.219Z","logger":"kafkajs","message":"[Connection] Response Produce(key: 0, version: 7)","broker":"broker1:9092","clientId":"my-kafkajs-producer","error":"This server is not the leader for that topic-partition","correlationId":1372,"size":55}
[[12:59:37.219]] [ERROR] {"level":"ERROR","timestamp":"2021-09-07T12:59:37.219Z","logger":"kafkajs","message":"[Producer] Failed to send messages: This server is not the leader for that topic-partition","retryCount":0,"retryTime":277}
[[12:59:37.224]] [ERROR] {"level":"ERROR","timestamp":"2021-09-07T12:59:37.224Z","logger":"kafkajs","message":"[Connection] Response Produce(key: 0, version: 7)","broker":"broker1:9092","clientId":"my-kafkajs-producer","error":"This server is not the leader for that topic-partition","correlationId":1373,"size":55}
[[12:59:37.224]] [ERROR] {"level":"ERROR","timestamp":"2021-09-07T12:59:37.224Z","logger":"kafkajs","message":"[Producer] Failed to send messages: This server is not the leader for that topic-partition","retryCount":0,"retryTime":338}
[[12:59:37.230]] [ERROR] {"level":"ERROR","timestamp":"2021-09-07T12:59:37.230Z","logger":"kafkajs","message":"[Connection] Response Produce(key: 0, version: 7)","broker":"broker1:9092","clientId":"my-kafkajs-producer","error":"This server is not the leader for that topic-partition","correlationId":1374,"size":55}
[[12:59:37.230]] [ERROR] {"level":"ERROR","timestamp":"2021-09-07T12:59:37.230Z","logger":"kafkajs","message":"[Producer] Failed to send messages: This server is not the leader for that topic-partition","retryCount":0,"retryTime":302}
[[12:59:37.247]] [ERROR] {"level":"ERROR","timestamp":"2021-09-07T12:59:37.247Z","logger":"kafkajs","message":"[Connection] Response Produce(key: 0, version: 7)","broker":"broker1:9092","clientId":"my-kafkajs-producer","error":"This server is not the leader for that topic-partition","correlationId":1375,"size":55}
[[12:59:37.247]] [ERROR] {"level":"ERROR","timestamp":"2021-09-07T12:59:37.247Z","logger":"kafkajs","message":"[Producer] Failed to send messages: This server is not the leader for that topic-partition","retryCount":0,"retryTime":273}
[[12:59:37.252]] [ERROR] {"level":"ERROR","timestamp":"2021-09-07T12:59:37.252Z","logger":"kafkajs","message":"[Connection] Response Produce(key: 0, version: 7)","broker":"broker1:9092","clientId":"my-kafkajs-producer","error":"This server is not the leader for that topic-partition","correlationId":1376,"size":55}
[[12:59:37.252]] [ERROR] {"level":"ERROR","timestamp":"2021-09-07T12:59:37.252Z","logger":"kafkajs","message":"[Producer] Failed to send messages: This server is not the leader for that topic-partition","retryCount":0,"retryTime":345}
[[12:59:37.286]] [ERROR] {"level":"ERROR","timestamp":"2021-09-07T12:59:37.286Z","logger":"kafkajs","message":"[Connection] Response Produce(key: 0, version: 7)","broker":"broker1:9092","clientId":"my-kafkajs-producer","error":"This server is not the leader for that topic-partition","correlationId":1377,"size":55}
[[12:59:37.286]] [ERROR] {"level":"ERROR","timestamp":"2021-09-07T12:59:37.286Z","logger":"kafkajs","message":"[Producer] Failed to send messages: This server is not the leader for that topic-partition","retryCount":0,"retryTime":272}
[[12:59:37.289]] [ERROR] {"level":"ERROR","timestamp":"2021-09-07T12:59:37.289Z","logger":"kafkajs","message":"[Connection] Response Produce(key: 0, version: 7)","broker":"broker1:9092","clientId":"my-kafkajs-producer","error":"This server is not the leader for that topic-partition","correlationId":1378,"size":55}
[[12:59:37.290]] [ERROR] {"level":"ERROR","timestamp":"2021-09-07T12:59:37.289Z","logger":"kafkajs","message":"[Producer] Failed to send messages: This server is not the leader for that topic-partition","retryCount":0,"retryTime":346}
[[12:59:37.311]] [ERROR] {"level":"ERROR","timestamp":"2021-09-07T12:59:37.311Z","logger":"kafkajs","message":"[Connection] Response Produce(key: 0, version: 7)","broker":"broker1:9092","clientId":"my-kafkajs-producer","error":"This server is not the leader for that topic-partition","correlationId":1379,"size":55}
[[12:59:37.312]] [ERROR] {"level":"ERROR","timestamp":"2021-09-07T12:59:37.311Z","logger":"kafkajs","message":"[Producer] Failed to send messages: This server is not the leader for that topic-partition","retryCount":0,"retryTime":264}
[[12:59:37.314]] [ERROR] {"level":"ERROR","timestamp":"2021-09-07T12:59:37.314Z","logger":"kafkajs","message":"[Connection] Response Produce(key: 0, version: 7)","broker":"broker1:9092","clientId":"my-kafkajs-producer","error":"This server is not the leader for that topic-partition","correlationId":1380,"size":55}
[[12:59:37.315]] [ERROR] {"level":"ERROR","timestamp":"2021-09-07T12:59:37.315Z","logger":"kafkajs","message":"[Producer] Failed to send messages: This server is not the leader for that topic-partition","retryCount":0,"retryTime":359}
[[12:59:37.321]] [ERROR] {"level":"ERROR","timestamp":"2021-09-07T12:59:37.321Z","logger":"kafkajs","message":"[Connection] Response Produce(key: 0, version: 7)","broker":"broker1:9092","clientId":"my-kafkajs-producer","error":"This server is not the leader for that topic-partition","correlationId":1381,"size":55}
[[12:59:37.322]] [ERROR] {"level":"ERROR","timestamp":"2021-09-07T12:59:37.322Z","logger":"kafkajs","message":"[Producer] Failed to send messages: This server is not the leader for that topic-partition","retryCount":0,"retryTime":355}
[[12:59:37.327]] [ERROR] {"level":"ERROR","timestamp":"2021-09-07T12:59:37.327Z","logger":"kafkajs","message":"[Connection] Response Produce(key: 0, version: 7)","broker":"broker1:9092","clientId":"my-kafkajs-producer","error":"This server is not the leader for that topic-partition","correlationId":1382,"size":55}
[[12:59:37.327]] [ERROR] {"level":"ERROR","timestamp":"2021-09-07T12:59:37.327Z","logger":"kafkajs","message":"[Producer] Failed to send messages: This server is not the leader for that topic-partition","retryCount":0,"retryTime":355}
[[12:59:37.344]] [ERROR] {"level":"ERROR","timestamp":"2021-09-07T12:59:37.344Z","logger":"kafkajs","message":"[Connection] Response Produce(key: 0, version: 7)","broker":"broker1:9092","clientId":"my-kafkajs-producer","error":"This server is not the leader for that topic-partition","correlationId":1383,"size":55}
[[12:59:37.344]] [ERROR] {"level":"ERROR","timestamp":"2021-09-07T12:59:37.344Z","logger":"kafkajs","message":"[Producer] Failed to send messages: This server is not the leader for that topic-partition","retryCount":0,"retryTime":284}
[[12:59:37.350]] [ERROR] {"level":"ERROR","timestamp":"2021-09-07T12:59:37.350Z","logger":"kafkajs","message":"[Connection] Response Produce(key: 0, version: 7)","broker":"broker1:9092","clientId":"my-kafkajs-producer","error":"This server is not the leader for that topic-partition","correlationId":1384,"size":55}
[[12:59:37.350]] [ERROR] {"level":"ERROR","timestamp":"2021-09-07T12:59:37.350Z","logger":"kafkajs","message":"[Producer] Failed to send messages: This server is not the leader for that topic-partition","retryCount":0,"retryTime":305}
[[12:59:37.355]] [ERROR] {"level":"ERROR","timestamp":"2021-09-07T12:59:37.355Z","logger":"kafkajs","message":"[Connection] Response Produce(key: 0, version: 7)","broker":"broker1:9092","clientId":"my-kafkajs-producer","error":"This server is not the leader for that topic-partition","correlationId":1385,"size":55}
[[12:59:37.356]] [ERROR] {"level":"ERROR","timestamp":"2021-09-07T12:59:37.356Z","logger":"kafkajs","message":"[Producer] Failed to send messages: This server is not the leader for that topic-partition","retryCount":0,"retryTime":266}
[[12:59:37.526]] [LOG]   Success in sending data
[[12:59:37.535]] [LOG]   Success in sending data
[[12:59:37.549]] [LOG]   Success in sending data
[[12:59:37.575]] [LOG]   Success in sending data
[[12:59:37.603]] [LOG]   Success in sending data
[[12:59:37.604]] [LOG]   Success in sending data
[[12:59:37.625]] [LOG]   Success in sending data
[[12:59:37.626]] [LOG]   Success in sending data
[[12:59:37.655]] [LOG]   Success in sending data
[[12:59:37.657]] [LOG]   Success in sending data
[[12:59:37.660]] [LOG]   Success in sending data
[[12:59:37.660]] [LOG]   Success in sending data
[[12:59:37.674]] [LOG]   Success in sending data
[[12:59:37.684]] [LOG]   Success in sending data
[[12:59:37.691]] [LOG]   Success in sending data
[[12:59:37.696]] [LOG]   Success in sending data
[[12:59:37.719]] [LOG]   Success in sending data
[[12:59:37.733]] [LOG]   Success in sending data
[[12:59:37.750]] [LOG]   Success in sending data
[[12:59:37.750]] [LOG]   lock released { duration: 603 }
```

After that broker1 is started, at the end there is leader re-election and we do see a bunch of `This server is not the leader for that topic-partition` (again, perfectly fine and correctly handled by kafkaJS). Lock time was 476ms

```log
[[13:01:53.099]] [LOG]   lock released { duration: 33 }
[[13:01:54.066]] [LOG]   Memory: 21.26 MB
[[13:01:54.066]] [LOG]   Queue size: 94
[[13:01:54.078]] [ERROR] {"level":"ERROR","timestamp":"2021-09-07T13:01:54.078Z","logger":"kafkajs","message":"[Connection] Response Produce(key: 0, version: 7)","broker":"broker2:9092","clientId":"my-kafkajs-producer","error":"This server is not the leader for that topic-partition","correlationId":4019,"size":85}
[[13:01:54.079]] [ERROR] {"level":"ERROR","timestamp":"2021-09-07T13:01:54.079Z","logger":"kafkajs","message":"[Producer] Failed to send messages: This server is not the leader for that topic-partition","retryCount":0,"retryTime":312}
[[13:01:54.081]] [ERROR] {"level":"ERROR","timestamp":"2021-09-07T13:01:54.081Z","logger":"kafkajs","message":"[Connection] Response Produce(key: 0, version: 7)","broker":"broker2:9092","clientId":"my-kafkajs-producer","error":"This server is not the leader for that topic-partition","correlationId":4020,"size":85}
[[13:01:54.082]] [ERROR] {"level":"ERROR","timestamp":"2021-09-07T13:01:54.081Z","logger":"kafkajs","message":"[Connection] Response Produce(key: 0, version: 7)","broker":"broker2:9092","clientId":"my-kafkajs-producer","error":"This server is not the leader for that topic-partition","correlationId":4021,"size":85}
[[13:01:54.082]] [ERROR] {"level":"ERROR","timestamp":"2021-09-07T13:01:54.082Z","logger":"kafkajs","message":"[Producer] Failed to send messages: This server is not the leader for that topic-partition","retryCount":0,"retryTime":336}
[[13:01:54.082]] [ERROR] {"level":"ERROR","timestamp":"2021-09-07T13:01:54.082Z","logger":"kafkajs","message":"[Producer] Failed to send messages: This server is not the leader for that topic-partition","retryCount":0,"retryTime":309}
[[13:01:54.083]] [ERROR] {"level":"ERROR","timestamp":"2021-09-07T13:01:54.083Z","logger":"kafkajs","message":"[Connection] Response Produce(key: 0, version: 7)","broker":"broker2:9092","clientId":"my-kafkajs-producer","error":"This server is not the leader for that topic-partition","correlationId":4022,"size":85}
[[13:01:54.084]] [ERROR] {"level":"ERROR","timestamp":"2021-09-07T13:01:54.084Z","logger":"kafkajs","message":"[Producer] Failed to send messages: This server is not the leader for that topic-partition","retryCount":0,"retryTime":257}
[[13:01:54.084]] [ERROR] {"level":"ERROR","timestamp":"2021-09-07T13:01:54.084Z","logger":"kafkajs","message":"[Connection] Response Produce(key: 0, version: 7)","broker":"broker2:9092","clientId":"my-kafkajs-producer","error":"This server is not the leader for that topic-partition","correlationId":4023,"size":85}
[[13:01:54.084]] [ERROR] {"level":"ERROR","timestamp":"2021-09-07T13:01:54.084Z","logger":"kafkajs","message":"[Producer] Failed to send messages: This server is not the leader for that topic-partition","retryCount":0,"retryTime":262}
[[13:01:54.086]] [ERROR] {"level":"ERROR","timestamp":"2021-09-07T13:01:54.086Z","logger":"kafkajs","message":"[Connection] Response Produce(key: 0, version: 7)","broker":"broker2:9092","clientId":"my-kafkajs-producer","error":"This server is not the leader for that topic-partition","correlationId":4024,"size":85}
[[13:01:54.086]] [ERROR] {"level":"ERROR","timestamp":"2021-09-07T13:01:54.086Z","logger":"kafkajs","message":"[Producer] Failed to send messages: This server is not the leader for that topic-partition","retryCount":0,"retryTime":278}
[[13:01:54.088]] [ERROR] {"level":"ERROR","timestamp":"2021-09-07T13:01:54.088Z","logger":"kafkajs","message":"[Connection] Response Produce(key: 0, version: 7)","broker":"broker2:9092","clientId":"my-kafkajs-producer","error":"This server is not the leader for that topic-partition","correlationId":4025,"size":85}
[[13:01:54.089]] [ERROR] {"level":"ERROR","timestamp":"2021-09-07T13:01:54.089Z","logger":"kafkajs","message":"[Producer] Failed to send messages: This server is not the leader for that topic-partition","retryCount":0,"retryTime":298}
[[13:01:54.091]] [ERROR] {"level":"ERROR","timestamp":"2021-09-07T13:01:54.091Z","logger":"kafkajs","message":"[Connection] Response Produce(key: 0, version: 7)","broker":"broker2:9092","clientId":"my-kafkajs-producer","error":"This server is not the leader for that topic-partition","correlationId":4026,"size":85}
[[13:01:54.092]] [ERROR] {"level":"ERROR","timestamp":"2021-09-07T13:01:54.092Z","logger":"kafkajs","message":"[Producer] Failed to send messages: This server is not the leader for that topic-partition","retryCount":0,"retryTime":287}
[[13:01:54.094]] [ERROR] {"level":"ERROR","timestamp":"2021-09-07T13:01:54.094Z","logger":"kafkajs","message":"[Connection] Response Produce(key: 0, version: 7)","broker":"broker2:9092","clientId":"my-kafkajs-producer","error":"This server is not the leader for that topic-partition","correlationId":4027,"size":85}
[[13:01:54.096]] [ERROR] {"level":"ERROR","timestamp":"2021-09-07T13:01:54.096Z","logger":"kafkajs","message":"[Connection] Response Produce(key: 0, version: 7)","broker":"broker2:9092","clientId":"my-kafkajs-producer","error":"This server is not the leader for that topic-partition","correlationId":4028,"size":85}
[[13:01:54.096]] [ERROR] {"level":"ERROR","timestamp":"2021-09-07T13:01:54.096Z","logger":"kafkajs","message":"[Producer] Failed to send messages: This server is not the leader for that topic-partition","retryCount":0,"retryTime":324}
[[13:01:54.096]] [ERROR] {"level":"ERROR","timestamp":"2021-09-07T13:01:54.096Z","logger":"kafkajs","message":"[Producer] Failed to send messages: This server is not the leader for that topic-partition","retryCount":0,"retryTime":311}
[[13:01:54.097]] [ERROR] {"level":"ERROR","timestamp":"2021-09-07T13:01:54.097Z","logger":"kafkajs","message":"[Connection] Response Produce(key: 0, version: 7)","broker":"broker2:9092","clientId":"my-kafkajs-producer","error":"This server is not the leader for that topic-partition","correlationId":4029,"size":85}
[[13:01:54.098]] [ERROR] {"level":"ERROR","timestamp":"2021-09-07T13:01:54.098Z","logger":"kafkajs","message":"[Producer] Failed to send messages: This server is not the leader for that topic-partition","retryCount":0,"retryTime":295}
[[13:01:54.098]] [ERROR] {"level":"ERROR","timestamp":"2021-09-07T13:01:54.098Z","logger":"kafkajs","message":"[Connection] Response Produce(key: 0, version: 7)","broker":"broker2:9092","clientId":"my-kafkajs-producer","error":"This server is not the leader for that topic-partition","correlationId":4030,"size":85}
[[13:01:54.099]] [ERROR] {"level":"ERROR","timestamp":"2021-09-07T13:01:54.099Z","logger":"kafkajs","message":"[Producer] Failed to send messages: This server is not the leader for that topic-partition","retryCount":0,"retryTime":319}
[[13:01:54.100]] [ERROR] {"level":"ERROR","timestamp":"2021-09-07T13:01:54.099Z","logger":"kafkajs","message":"[Connection] Response Produce(key: 0, version: 7)","broker":"broker2:9092","clientId":"my-kafkajs-producer","error":"This server is not the leader for that topic-partition","correlationId":4031,"size":85}
[[13:01:54.100]] [ERROR] {"level":"ERROR","timestamp":"2021-09-07T13:01:54.100Z","logger":"kafkajs","message":"[Producer] Failed to send messages: This server is not the leader for that topic-partition","retryCount":0,"retryTime":310}
[[13:01:54.100]] [ERROR] {"level":"ERROR","timestamp":"2021-09-07T13:01:54.100Z","logger":"kafkajs","message":"[Connection] Response Produce(key: 0, version: 7)","broker":"broker2:9092","clientId":"my-kafkajs-producer","error":"This server is not the leader for that topic-partition","correlationId":4032,"size":85}
[[13:01:54.101]] [ERROR] {"level":"ERROR","timestamp":"2021-09-07T13:01:54.101Z","logger":"kafkajs","message":"[Producer] Failed to send messages: This server is not the leader for that topic-partition","retryCount":0,"retryTime":346}
[[13:01:54.103]] [ERROR] {"level":"ERROR","timestamp":"2021-09-07T13:01:54.102Z","logger":"kafkajs","message":"[Connection] Response Produce(key: 0, version: 7)","broker":"broker2:9092","clientId":"my-kafkajs-producer","error":"This server is not the leader for that topic-partition","correlationId":4033,"size":85}
[[13:01:54.103]] [ERROR] {"level":"ERROR","timestamp":"2021-09-07T13:01:54.103Z","logger":"kafkajs","message":"[Producer] Failed to send messages: This server is not the leader for that topic-partition","retryCount":0,"retryTime":287}
[[13:01:54.103]] [ERROR] {"level":"ERROR","timestamp":"2021-09-07T13:01:54.103Z","logger":"kafkajs","message":"[Connection] Response Produce(key: 0, version: 7)","broker":"broker2:9092","clientId":"my-kafkajs-producer","error":"This server is not the leader for that topic-partition","correlationId":4034,"size":85}
[[13:01:54.103]] [ERROR] {"level":"ERROR","timestamp":"2021-09-07T13:01:54.103Z","logger":"kafkajs","message":"[Producer] Failed to send messages: This server is not the leader for that topic-partition","retryCount":0,"retryTime":333}
[[13:01:54.108]] [ERROR] {"level":"ERROR","timestamp":"2021-09-07T13:01:54.108Z","logger":"kafkajs","message":"[Connection] Response Produce(key: 0, version: 7)","broker":"broker2:9092","clientId":"my-kafkajs-producer","error":"This server is not the leader for that topic-partition","correlationId":4035,"size":85}
[[13:01:54.108]] [ERROR] {"level":"ERROR","timestamp":"2021-09-07T13:01:54.108Z","logger":"kafkajs","message":"[Connection] Response Produce(key: 0, version: 7)","broker":"broker2:9092","clientId":"my-kafkajs-producer","error":"This server is not the leader for that topic-partition","correlationId":4036,"size":85}
[[13:01:54.109]] [ERROR] {"level":"ERROR","timestamp":"2021-09-07T13:01:54.109Z","logger":"kafkajs","message":"[Producer] Failed to send messages: This server is not the leader for that topic-partition","retryCount":0,"retryTime":340}
[[13:01:54.109]] [ERROR] {"level":"ERROR","timestamp":"2021-09-07T13:01:54.109Z","logger":"kafkajs","message":"[Producer] Failed to send messages: This server is not the leader for that topic-partition","retryCount":0,"retryTime":303}
[[13:01:54.110]] [ERROR] {"level":"ERROR","timestamp":"2021-09-07T13:01:54.110Z","logger":"kafkajs","message":"[Connection] Response Produce(key: 0, version: 7)","broker":"broker2:9092","clientId":"my-kafkajs-producer","error":"This server is not the leader for that topic-partition","correlationId":4037,"size":85}
[[13:01:54.111]] [ERROR] {"level":"ERROR","timestamp":"2021-09-07T13:01:54.111Z","logger":"kafkajs","message":"[Producer] Failed to send messages: This server is not the leader for that topic-partition","retryCount":0,"retryTime":277}
[[13:01:54.433]] [LOG]   Success in sending data
[[13:01:54.433]] [LOG]   Success in sending data
[[13:01:54.444]] [LOG]   Success in sending data
[[13:01:54.453]] [LOG]   Success in sending data
[[13:01:54.454]] [LOG]   Success in sending data
[[13:01:54.461]] [LOG]   Success in sending data
[[13:01:54.462]] [LOG]   Success in sending data
[[13:01:54.464]] [LOG]   Success in sending data
[[13:01:54.475]] [LOG]   Success in sending data
[[13:01:54.477]] [LOG]   Success in sending data
[[13:01:54.478]] [LOG]   Success in sending data
[[13:01:54.480]] [LOG]   Success in sending data
[[13:01:54.483]] [LOG]   Success in sending data
[[13:01:54.487]] [LOG]   Success in sending data
[[13:01:54.492]] [LOG]   Success in sending data
[[13:01:54.502]] [LOG]   Success in sending data
[[13:01:54.504]] [LOG]   Success in sending data
[[13:01:54.531]] [LOG]   Success in sending data
[[13:01:54.541]] [LOG]   Success in sending data
[[13:01:54.541]] [LOG]   lock released { duration: 476 }
```

