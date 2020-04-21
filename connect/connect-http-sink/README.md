# HTTP Sink connector

![asciinema](https://github.com/vdesabou/gifs/blob/master/connect/connect-http-sink/asciinema.gif?raw=true)

## Objective

Quickly test [HTTP Sink](https://docs.confluent.io/current/connect/kafka-connect-http/index.html#kconnect-long-http-sink-connector) connector.

This is based on [Kafka Connect HTTP Connector Quick Start](https://docs.confluent.io/current/connect/kafka-connect-http/index.html#kconnect-long-http-connector-quick-start)

The HTTP service is using [Kafka Connect HTTP Sink Demo App](https://github.com/confluentinc/kafka-connect-http-demo)



## How to run


### Simple (No) Authentication

```bash
$ ./http_simple_auth.sh
```

### Basic Authentication

```bash
$ ./http_basic_auth.sh
```

### Oauth2 Authentication

```bash
$ ./http_oauth2_auth.sh
```

### SSL Authentication

```bash
$ ./http_ssl_auth.sh
```

### JSON Converter Example

```bash
$ ./http_json_basic_auth.sh
```

Sending using:

```
docker exec -i broker kafka-console-producer --broker-list broker:9092 --topic json-topic << EOF
{"customer_name":"Ed", "complaint_type":"Dirty car", "trip_cost": 29.10, "new_customer": false, "number_of_rides": 22}
EOF
```

Json data:

```json
{
    "customer_name": "Ed",
    "complaint_type": "Dirty car",
    "trip_cost": 29.1,
    "new_customer": false,
    "number_of_rides": 22
}
```

Getting:

```bash
curl admin:password@localhost:9083/api/messages | jq .
[
  {
    "id": 1,
    "message": "{complaint_type=Dirty car, new_customer=false, trip_cost=29.1, customer_name=Ed, number_of_rides=22}"
  }
]
```

**FIXTHIS** output message is not valid JSON

### JSON Converter Example with HTTP error 204 (NO_CONTENT)

This is to reproduce NPE seen during testing.
The HTTP server is returning 204 error.

```bash
$ ./http_json_basic_auth_error_204.sh
```


Getting:

```bash
curl admin:password@localhost:9081/api/messages | jq .
[
  {
    "id": 1,
    "message": "{complaint_type=Dirty car, new_customer=false, trip_cost=29.1, customer_name=Ed, number_of_rides=22}"
  },
  {
    "id": 2,
    "message": "{complaint_type=Dirty car, new_customer=false, trip_cost=29.1, customer_name=Ed, number_of_rides=22}"
  },
  {
    "id": 3,
    "message": "{complaint_type=Dirty car, new_customer=false, trip_cost=29.1, customer_name=Ed, number_of_rides=22}"
  },
  {
    "id": 4,
    "message": "{complaint_type=Dirty car, new_customer=false, trip_cost=29.1, customer_name=Ed, number_of_rides=22}"
  },
  {
    "id": 5,
    "message": "{complaint_type=Dirty car, new_customer=false, trip_cost=29.1, customer_name=Ed, number_of_rides=22}"
  },
  {
    "id": 6,
    "message": "{complaint_type=Dirty car, new_customer=false, trip_cost=29.1, customer_name=Ed, number_of_rides=22}"
  },
  {
    "id": 7,
    "message": "{complaint_type=Dirty car, new_customer=false, trip_cost=29.1, customer_name=Ed, number_of_rides=22}"
  },
  {
    "id": 8,
    "message": "{complaint_type=Dirty car, new_customer=false, trip_cost=29.1, customer_name=Ed, number_of_rides=22}"
  },
  {
    "id": 9,
    "message": "{complaint_type=Dirty car, new_customer=false, trip_cost=29.1, customer_name=Ed, number_of_rides=22}"
  },
  {
    "id": 10,
    "message": "{complaint_type=Dirty car, new_customer=false, trip_cost=29.1, customer_name=Ed, number_of_rides=22}"
  },
  {
    "id": 11,
    "message": "{complaint_type=Dirty car, new_customer=false, trip_cost=29.1, customer_name=Ed, number_of_rides=22}"
  }
]
```

These are duplicate sent requests as only one message was sent.

In the logs we have:

```
connect                        | [2019-10-01 06:58:37,127] WARN Write of 1 records failed, remainingRetries=10 (io.confluent.connect.http.HttpSinkTask)
connect                        | java.lang.NullPointerException
connect                        |        at io.confluent.connect.http.writer.HttpWriterImpl.sendBatch(HttpWriterImpl.java:180)
connect                        |        at io.confluent.connect.http.writer.HttpWriterImpl.write(HttpWriterImpl.java:117)
connect                        |        at io.confluent.connect.http.HttpSinkTask.put(HttpSinkTask.java:62)
connect                        |        at org.apache.kafka.connect.runtime.WorkerSinkTask.deliverMessages(WorkerSinkTask.java:538)
connect                        |        at org.apache.kafka.connect.runtime.WorkerSinkTask.poll(WorkerSinkTask.java:321)
connect                        |        at org.apache.kafka.connect.runtime.WorkerSinkTask.iteration(WorkerSinkTask.java:224)
connect                        |        at org.apache.kafka.connect.runtime.WorkerSinkTask.execute(WorkerSinkTask.java:192)
connect                        |        at org.apache.kafka.connect.runtime.WorkerTask.doRun(WorkerTask.java:177)
connect                        |        at org.apache.kafka.connect.runtime.WorkerTask.run(WorkerTask.java:227)
connect                        |        at java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:511)
connect                        |        at java.util.concurrent.FutureTask.run(FutureTask.java:266)
connect                        |        at java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1149)
connect                        |        at java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:624)
connect                        |        at java.lang.Thread.run(Thread.java:748)
connect                        | [2019-10-01 06:58:37,131] ERROR WorkerSinkTask{id=http-sink-0} RetriableException from SinkTask: (org.apache.kafka.connect.runtime.WorkerSinkTask)
connect                        | org.apache.kafka.connect.errors.RetriableException: java.lang.NullPointerException
connect                        |        at io.confluent.connect.http.HttpSinkTask.put(HttpSinkTask.java:79)
connect                        |        at org.apache.kafka.connect.runtime.WorkerSinkTask.deliverMessages(WorkerSinkTask.java:538)
connect                        |        at org.apache.kafka.connect.runtime.WorkerSinkTask.poll(WorkerSinkTask.java:321)
connect                        |        at org.apache.kafka.connect.runtime.WorkerSinkTask.iteration(WorkerSinkTask.java:224)
connect                        |        at org.apache.kafka.connect.runtime.WorkerSinkTask.execute(WorkerSinkTask.java:192)
connect                        |        at org.apache.kafka.connect.runtime.WorkerTask.doRun(WorkerTask.java:177)
connect                        |        at org.apache.kafka.connect.runtime.WorkerTask.run(WorkerTask.java:227)
connect                        |        at java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:511)
connect                        |        at java.util.concurrent.FutureTask.run(FutureTask.java:266)
connect                        |        at java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1149)
connect                        |        at java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:624)
connect                        |        at java.lang.Thread.run(Thread.java:748)
connect                        | Caused by: java.lang.NullPointerException
connect                        |        at io.confluent.connect.http.writer.HttpWriterImpl.sendBatch(HttpWriterImpl.java:180)
connect                        |        at io.confluent.connect.http.writer.HttpWriterImpl.write(HttpWriterImpl.java:117)
connect                        |        at io.confluent.connect.http.HttpSinkTask.put(HttpSinkTask.java:62)
connect                        |        ... 11 more
connect                        | [2019-10-01 06:58:40,155] WARN Write of 1 records failed, remainingRetries=9 (io.confluent.connect.http.HttpSinkTask)
connect                        | java.lang.NullPointerException
connect                        |        at io.confluent.connect.http.writer.HttpWriterImpl.sendBatch(HttpWriterImpl.java:180)
connect                        |        at io.confluent.connect.http.writer.HttpWriterImpl.write(HttpWriterImpl.java:117)
connect                        |        at io.confluent.connect.http.HttpSinkTask.put(HttpSinkTask.java:62)
connect                        |        at org.apache.kafka.connect.runtime.WorkerSinkTask.deliverMessages(WorkerSinkTask.java:538)
connect                        |        at org.apache.kafka.connect.runtime.WorkerSinkTask.poll(WorkerSinkTask.java:321)
connect                        |        at org.apache.kafka.connect.runtime.WorkerSinkTask.iteration(WorkerSinkTask.java:224)
connect                        |        at org.apache.kafka.connect.runtime.WorkerSinkTask.execute(WorkerSinkTask.java:192)
connect                        |        at org.apache.kafka.connect.runtime.WorkerTask.doRun(WorkerTask.java:177)
connect                        |        at org.apache.kafka.connect.runtime.WorkerTask.run(WorkerTask.java:227)
connect                        |        at java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:511)
connect                        |        at java.util.concurrent.FutureTask.run(FutureTask.java:266)
connect                        |        at java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1149)
connect                        |        at java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:624)
connect                        |        at java.lang.Thread.run(Thread.java:748)
connect                        | [2019-10-01 06:58:40,156] ERROR WorkerSinkTask{id=http-sink-0} RetriableException from SinkTask: (org.apache.kafka.connect.runtime.WorkerSinkTask)
connect                        | org.apache.kafka.connect.errors.RetriableException: java.lang.NullPointerException
connect                        |        at io.confluent.connect.http.HttpSinkTask.put(HttpSinkTask.java:79)
connect                        |        at org.apache.kafka.connect.runtime.WorkerSinkTask.deliverMessages(WorkerSinkTask.java:538)
connect                        |        at org.apache.kafka.connect.runtime.WorkerSinkTask.poll(WorkerSinkTask.java:321)
connect                        |        at org.apache.kafka.connect.runtime.WorkerSinkTask.iteration(WorkerSinkTask.java:224)
connect                        |        at org.apache.kafka.connect.runtime.WorkerSinkTask.execute(WorkerSinkTask.java:192)
connect                        |        at org.apache.kafka.connect.runtime.WorkerTask.doRun(WorkerTask.java:177)
connect                        |        at org.apache.kafka.connect.runtime.WorkerTask.run(WorkerTask.java:227)
connect                        |        at java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:511)
connect                        |        at java.util.concurrent.FutureTask.run(FutureTask.java:266)
connect                        |        at java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1149)
connect                        |        at java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:624)
connect                        |        at java.lang.Thread.run(Thread.java:748)
connect                        | Caused by: java.lang.NullPointerException
connect                        |        at io.confluent.connect.http.writer.HttpWriterImpl.sendBatch(HttpWriterImpl.java:180)
connect                        |        at io.confluent.connect.http.writer.HttpWriterImpl.write(HttpWriterImpl.java:117)
connect                        |        at io.confluent.connect.http.HttpSinkTask.put(HttpSinkTask.java:62)
connect                        |        ... 11 more
connect                        | [2019-10-01 06:58:43,168] WARN Write of 1 records failed, remainingRetries=8 (io.confluent.connect.http.HttpSinkTask)
connect                        | java.lang.NullPointerException
connect                        |        at io.confluent.connect.http.writer.HttpWriterImpl.sendBatch(HttpWriterImpl.java:180)
connect                        |        at io.confluent.connect.http.writer.HttpWriterImpl.write(HttpWriterImpl.java:117)
connect                        |        at io.confluent.connect.http.HttpSinkTask.put(HttpSinkTask.java:62)
connect                        |        at org.apache.kafka.connect.runtime.WorkerSinkTask.deliverMessages(WorkerSinkTask.java:538)
connect                        |        at org.apache.kafka.connect.runtime.WorkerSinkTask.poll(WorkerSinkTask.java:321)
connect                        |        at org.apache.kafka.connect.runtime.WorkerSinkTask.iteration(WorkerSinkTask.java:224)
connect                        |        at org.apache.kafka.connect.runtime.WorkerSinkTask.execute(WorkerSinkTask.java:192)
connect                        |        at org.apache.kafka.connect.runtime.WorkerTask.doRun(WorkerTask.java:177)
connect                        |        at org.apache.kafka.connect.runtime.WorkerTask.run(WorkerTask.java:227)
connect                        |        at java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:511)
connect                        |        at java.util.concurrent.FutureTask.run(FutureTask.java:266)
connect                        |        at java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1149)
connect                        |        at java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:624)
connect                        |        at java.lang.Thread.run(Thread.java:748)
```



### AVRO Converter Example

```
$ ./http_avro_basic_auth.sh
```

Sending using:

```bash
seq -f "{\"f1\": \"value%g\"}" 10 | docker exec -i connect kafka-avro-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic avro-topic --property value.schema='{"type":"record","name":"myrecord","fields":[{"name":"f1","type":"string"}]}'
```

Getting:

```
curl admin:password@localhost:9083/api/messages | jq .
[
  {
    "id": 1,
    "message": "Struct{f1=value1}"
  },
  {
    "id": 2,
    "message": "Struct{f1=value2}"
  },
  {
    "id": 3,
    "message": "Struct{f1=value3}"
  },
  {
    "id": 4,
    "message": "Struct{f1=value4}"
  },
  {
    "id": 5,
    "message": "Struct{f1=value5}"
  },
  {
    "id": 6,
    "message": "Struct{f1=value6}"
  },
  {
    "id": 7,
    "message": "Struct{f1=value7}"
  },
  {
    "id": 8,
    "message": "Struct{f1=value8}"
  },
  {
    "id": 9,
    "message": "Struct{f1=value9}"
  },
  {
    "id": 10,
    "message": "Struct{f1=value10}"
  }
]
```
