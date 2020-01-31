# RabbitMQ Source connector

## Objective

Quickly test [RabbitMQ Source](https://docs.confluent.io/current/connect/kafka-connect-rabbitmq/index.html#quick-start) connector.

## Pre-requisites

* `docker-compose` (example `brew cask install docker`)

## How to run

Simply run:

```
$ ./rabbitmq.sh
```

## Details of what the script is doing

Send message to RabbitMQ in `myqueue`:

```bash
$ docker exec rabbitmq_producer bash -c "python /producer.py myqueue 5"
```

Creating RabbitMQ Source connector

```bash
$ docker exec connect \
     curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class" : "io.confluent.connect.rabbitmq.RabbitMQSourceConnector",
                  "tasks.max" : "1",
                  "kafka.topic" : "rabbitmq",
                  "rabbitmq.queue" : "myqueue",
                  "rabbitmq.host" : "rabbitmq",
                  "rabbitmq.username" : "myuser",
                  "rabbitmq.password" : "mypassword"
          }' \
     http://localhost:8083/connectors/rabbitmq-source/config | jq .
```


Verify we have received the data in `rabbitmq` topic

```bash
$ docker exec connect kafka-avro-console-consumer -bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic rabbitmq --from-beginning --max-messages 5
```

Results:

```
"´\u0001{\"id\": 0, \"body\": \"010101010101010101010101010101010101010101010101010101010101010101010\"}"
"´\u0001{\"id\": 1, \"body\": \"010101010101010101010101010101010101010101010101010101010101010101010\"}"
"´\u0001{\"id\": 2, \"body\": \"010101010101010101010101010101010101010101010101010101010101010101010\"}"
"´\u0001{\"id\": 3, \"body\": \"010101010101010101010101010101010101010101010101010101010101010101010\"}"
"´\u0001{\"id\": 4, \"body\": \"010101010101010101010101010101010101010101010101010101010101010101010\"}"
```

Note:

Run the following command to consume all records in RabbitMQ queue `myqueue`

```bash
$ docker exec -it rabbitmq_consumer bash -c "python /consumer.py myqueue"
```

N.B: Control Center is reachable at [http://127.0.0.1:9021](http://127.0.0.1:9021])
