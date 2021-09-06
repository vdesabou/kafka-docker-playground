# Results

Traffic is blocked at `11:32:33`:

```log
11:32:33 ℹ️ Blocking IP address 172.18.0.6 corresponding to kafkaJS client
11:32:33 ℹ️ Grepping for WARN|ERROR|Metadata|timed out
```

30 seconds later request timeout:

```log
[[11:33:04.669]] [LOG]   Producer request timed out at 1630927984668 {"broker":"broker1:9092","clientId":"my-kafkajs-producer","correlationId":17,"createdAt":1630927954687,"sentAt":1630927954687,"pendingDuration":0,"apiName":"Produce","apiKey":0,"apiVersion":5}
```

Then we see a `Connection error: read ETIMEDOUT`:

```log
[[11:33:29.928]] [ERROR] {"level":"ERROR","timestamp":"2021-09-06T11:33:29.928Z","logger":"kafkajs","message":"[Connection] Connection error: read ETIMEDOUT","broker":"broker1:9092","clientId":"my-kafkajs-producer","stack":"Error: read ETIMEDOUT\n    at TCP.onStreamRead (internal/stream_base_commons.js:209:20)"}
```

That triggers a [disconnect](https://github.com/tulios/kafkajs/blob/master/src/network/connection.js#L208):

```log
[[11:33:29.929]] [LOG]   {"level":"DEBUG","timestamp":"2021-09-06T11:33:29.929Z","logger":"kafkajs","message":"[Connection] disconnecting...","broker":"broker1:9092","clientId":"my-kafkajs-producer"}
[[11:33:29.930]] [LOG]   {"level":"DEBUG","timestamp":"2021-09-06T11:33:29.930Z","logger":"kafkajs","message":"[Connection] disconnected","broker":"broker1:9092","clientId":"my-kafkajs-producer"}
```

I do not see a re-connect, but requests are retried:

Retries:

```log
[[11:33:34.935]] [LOG]   Producer request timed out at 1630928014935 {"broker":"broker1:9092","clientId":"my-kafkajs-producer","correlationId":18,"createdAt":1630927984955,"sentAt":1630927984955,"pendingDuration":0,"apiName":"Produce","apiKey":0,"apiVersion":5}
[[11:34:05.382]] [LOG]   Producer request timed out at 1630928045381 {"broker":"broker1:9092","clientId":"my-kafkajs-producer","correlationId":19,"createdAt":1630928015401,"sentAt":1630928015401,"pendingDuration":0,"apiName":"Produce","apiKey":0,"apiVersion":5}
[[11:34:36.243]] [LOG]   Producer request timed out at 1630928076243 {"broker":"broker1:9092","clientId":"my-kafkajs-producer","correlationId":20,"createdAt":1630928046263,"sentAt":1630928046263,"pendingDuration":0,"apiName":"Produce","apiKey":0,"apiVersion":5}
[[11:35:07.880]] [LOG]   Producer request timed out at 1630928107880 {"broker":"broker1:9092","clientId":"my-kafkajs-producer","correlationId":21,"createdAt":1630928077900,"sentAt":1630928077900,"pendingDuration":0,"apiName":"Produce","apiKey":0,"apiVersion":5}
[[11:35:41.097]] [LOG]   Producer request timed out at 1630928141097 {"broker":"broker1:9092","clientId":"my-kafkajs-producer","correlationId":22,"createdAt":1630928111116,"sentAt":1630928111116,"pendingDuration":0,"apiName":"Produce","apiKey":0,"apiVersion":5}
[[11:35:41.098]] [ERROR] {"level":"ERROR","timestamp":"2021-09-06T11:35:41.098Z","logger":"kafkajs","message":"[Producer] Request Produce(key: 0, version: 5) timed out","retryCount":0,"retryTime":282}
[[11:35:41.099]] [LOG]   failed to send data KafkaJSRequestTimeoutError: Request Produce(key: 0, version: 5) timed out
```

```log
[[11:36:11.879]] [LOG]   Producer request timed out at 1630928171879 {"broker":"broker1:9092","clientId":"my-kafkajs-producer","correlationId":23,"createdAt":1630928141899,"sentAt":1630928141899,"pendingDuration":0,"apiName":"Produce","apiKey":0,"apiVersion":5}
[[11:36:42.178]] [LOG]   Producer request timed out at 1630928202178 {"broker":"broker1:9092","clientId":"my-kafkajs-producer","correlationId":24,"createdAt":1630928172198,"sentAt":1630928172198,"pendingDuration":0,"apiName":"Produce","apiKey":0,"apiVersion":5}
[[11:37:12.826]] [LOG]   Producer request timed out at 1630928232826 {"broker":"broker1:9092","clientId":"my-kafkajs-producer","correlationId":25,"createdAt":1630928202845,"sentAt":1630928202845,"pendingDuration":0,"apiName":"Produce","apiKey":0,"apiVersion":5}
[[11:37:43.965]] [LOG]   Producer request timed out at 1630928263965 {"broker":"broker1:9092","clientId":"my-kafkajs-producer","correlationId":26,"createdAt":1630928233984,"sentAt":1630928233984,"pendingDuration":0,"apiName":"Produce","apiKey":0,"apiVersion":5}
[[11:38:16.155]] [LOG]   Producer request timed out at 1630928296154 {"broker":"broker1:9092","clientId":"my-kafkajs-producer","correlationId":27,"createdAt":1630928266176,"sentAt":1630928266176,"pendingDuration":0,"apiName":"Produce","apiKey":0,"apiVersion":5}
[[11:38:51.223]] [LOG]   Producer request timed out at 1630928331223 {"broker":"broker1:9092","clientId":"my-kafkajs-producer","correlationId":28,"createdAt":1630928301243,"sentAt":1630928301243,"pendingDuration":0,"apiName":"Produce","apiKey":0,"apiVersion":5}
[[11:38:51.224]] [ERROR] {"level":"ERROR","timestamp":"2021-09-06T11:38:51.224Z","logger":"kafkajs","message":"[Producer] Request Produce(key: 0, version: 5) timed out","retryCount":0,"retryTime":320}
[[11:38:51.225]] [LOG]   failed to send data KafkaJSRequestTimeoutError: Request Produce(key: 0, version: 5) timed out
```

etc...

Note: Request metadata happening on broker3, broker1 is seen as ok as expected (because connection issue is only happening from broker1 to kakfaJS client):

```log
[[11:37:46.168]] [LOG]   {"level":"DEBUG","timestamp":"2021-09-06T11:37:46.167Z","logger":"kafkajs","message":"[Connection] Request Metadata(key: 3, version: 5)","broker":"broker3:9092","clientId":"my-kafkajs-producer","correlationId":17,"expectResponse":true,"size":47}
[[11:37:46.169]] [LOG]   {"level":"DEBUG","timestamp":"2021-09-06T11:37:46.169Z","logger":"kafkajs","message":"[Connection] Response Metadata(key: 3, version: 5)","broker":"broker3:9092","clientId":"my-kafkajs-producer","correlationId":17,"size":255,"data":{"throttleTime":0,"brokers":[{"nodeId":2,"host":"broker2","port":9092,"rack":null},{"nodeId":3,"host":"broker3","port":9092,"rack":null},{"nodeId":1,"host":"broker1","port":9092,"rack":null}],"clusterId":"_jMoVOJEQiS8ez1Eo1ucpQ","controllerId":2,"topicMetadata":[{"topicErrorCode":0,"topic":"kafkajs","isInternal":false,"partitionMetadata":[{"partitionErrorCode":0,"partitionId":0,"leader":2,"replicas":[2,3,1],"isr":[2,3,1],"offlineReplicas":[]},{"partitionErrorCode":0,"partitionId":1,"leader":3,"replicas":[3,1,2],"isr":[3,1,2],"offlineReplicas":[]},{"partitionErrorCode":0,"partitionId":2,"leader":1,"replicas":[1,2,3],"isr":[1,2,3],"offlineReplicas":[]}]}]}}
```

At `11:42:33` the iptables rule is removed:

```log
11:42:33 ℹ️ Unblocking IP address 172.18.0.6 corresponding to kafkaJS client
```

We see a disconnection, probably because broker disconnected for good the client (due to `connections.max.idle.ms` which is 10 minutes by default). This time we have `Kafka server has closed connection` followed by `Connecting`:

```log
[[11:42:34.388]] [LOG]   {"level":"DEBUG","timestamp":"2021-09-06T11:42:34.387Z","logger":"kafkajs","message":"[Connection] disconnecting...","broker":"broker1:9092","clientId":"my-kafkajs-producer"}
[[11:42:34.388]] [LOG]   {"level":"DEBUG","timestamp":"2021-09-06T11:42:34.388Z","logger":"kafkajs","message":"[Connection] disconnected","broker":"broker1:9092","clientId":"my-kafkajs-producer"}
[[11:42:34.388]] [LOG]   {"level":"DEBUG","timestamp":"2021-09-06T11:42:34.388Z","logger":"kafkajs","message":"[Connection] Kafka server has closed connection","broker":"broker1:9092","clientId":"my-kafkajs-producer"}
[[11:42:34.394]] [ERROR] {"level":"ERROR","timestamp":"2021-09-06T11:42:34.394Z","logger":"kafkajs","message":"[Connection] Connection error: write EPIPE","broker":"broker1:9092","clientId":"my-kafkajs-producer","stack":"Error: write EPIPE\n    at WriteWrap.onWriteComplete [as oncomplete] (internal/stream_base_commons.js:94:16)"}
[[11:42:34.855]] [LOG]   {"level":"DEBUG","timestamp":"2021-09-06T11:42:34.855Z","logger":"kafkajs","message":"[Connection] Connecting","broker":"broker1:9092","clientId":"my-kafkajs-producer","ssl":false,"sasl":false}
```

Full logs are [here](https://github.com/vdesabou/kafka-docker-playground/blob/master/other/client-kafkajs/repro-timeout/producer.log.zip?raw=true)