# RabbitMQ Sink connector

![asciinema](https://github.com/vdesabou/gifs/blob/master/connect/connect-rabbitmq-sink/asciinema.gif?raw=true)

## Objective

Quickly test [RabbitMQ Sink](https://docs.confluent.io/current/connect/kafka-connect-rabbitmq/sink/index.html#rabbitmq-sink-connector-for-cp) connector.


## How to run

Simply run:

```
$ ./rabbitmq.sh
```

## Details of what the script is doing

Create RabbitMQ exchange, queue and binding:

```bash
$ docker exec -it rabbitmq rabbitmqadmin -u myuser -p mypassword -V / declare exchange name=exchange1 type=direct
$ docker exec -it rabbitmq rabbitmqadmin -u myuser -p mypassword -V / declare queue name=queue1 durable=true
$ docker exec -it rabbitmq rabbitmqadmin -u myuser -p mypassword -V / declare binding source=exchange1 destination=queue1 routing_key=rkey1
```

Sending messages to topic `rabbitmq-messages`:

```bash
$ seq 10 | docker exec -i broker kafka-console-producer --broker-list broker:9092 --topic rabbitmq-messages
```

Creating RabbitMQ Source connector:

```bash
$ docker exec connect \
     curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class" : "io.confluent.connect.rabbitmq.sink.RabbitMQSinkConnector",
               "tasks.max" : "1",
               "topics": "rabbitmq-messages",
               "key.converter": "org.apache.kafka.connect.storage.StringConverter",
               "value.converter": "org.apache.kafka.connect.converters.ByteArrayConverter",
               "rabbitmq.queue" : "myqueue",
               "rabbitmq.host" : "rabbitmq",
               "rabbitmq.username" : "myuser",
               "rabbitmq.password" : "mypassword",
               "rabbitmq.exchange": "exchange1",
               "rabbitmq.routing.key": "rkey1",
               "rabbitmq.delivery.mode": "PERSISTENT",
               "confluent.topic.bootstrap.servers": "broker:9092",
               "confluent.topic.replication.factor": "1"
          }' \
     http://localhost:8083/connectors/rabbitmq-sink/config | jq .
```

Check messages received in RabbitMQ:

```bash
$ docker exec -it rabbitmq rabbitmqadmin -u myuser -p mypassword get queue=queue1 count=10
```

Results:

```
+-------------+-----------+---------------+---------+---------------+------------------+-------------+
| routing_key | exchange  | message_count | payload | payload_bytes | payload_encoding | redelivered |
+-------------+-----------+---------------+---------+---------------+------------------+-------------+
| rkey1       | exchange1 | 9             | 1       | 1             | string           | False       |
| rkey1       | exchange1 | 8             | 2       | 1             | string           | False       |
| rkey1       | exchange1 | 7             | 3       | 1             | string           | False       |
| rkey1       | exchange1 | 6             | 4       | 1             | string           | False       |
| rkey1       | exchange1 | 5             | 5       | 1             | string           | False       |
| rkey1       | exchange1 | 4             | 6       | 1             | string           | False       |
| rkey1       | exchange1 | 3             | 7       | 1             | string           | False       |
| rkey1       | exchange1 | 2             | 8       | 1             | string           | False       |
| rkey1       | exchange1 | 1             | 9       | 1             | string           | False       |
| rkey1       | exchange1 | 0             | 10      | 2             | string           | False       |
+-------------+-----------+---------------+---------+---------------+------------------+-------------+
```

N.B: Control Center is reachable at [http://127.0.0.1:9021](http://127.0.0.1:9021])
