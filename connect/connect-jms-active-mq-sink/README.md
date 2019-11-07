# JMS ActiveMQ Sink connector

## Objective

Quickly test [JMS ActiveMQ Sink](https://docs.confluent.io/current/connect/kafka-connect-jms/sink/index.html#actvemq-quick-start) connector.

Using ActiveMQ Docker [image](https://hub.docker.com/r/rmohr/activemq/)

## Pre-requisites

* `docker-compose` (example `brew cask install docker`)
* `jq` (example `brew install jq`)


## How to run

Simply run:

```
$ ./jms-active-mq-sink.sh
```

## Details of what the script is doing

ActiveMQ UI is reachable at [http://127.0.0.1:8161](http://127.0.0.1:8161]) (`admin/admin`)

Sending messages to topic `sink-messages`

```bash
$ docker exec -i broker kafka-console-producer --broker-list broker:9092 --topic sink-messages << EOF
This is my message
EOF
```

The connector is created with:

```bash
$ docker exec connect \
     curl -X POST \
     -H "Content-Type: application/json" \
     --data '{
               "name": "jms-active-mq-sink",
               "config": {
                    "connector.class": "io.confluent.connect.jms.JmsSinkConnector",
                    "topics": "sink-messages",
                    "java.naming.factory.initial": "org.apache.activemq.jndi.ActiveMQInitialContextFactory",
                    "java.naming.provider.url": "tcp://activemq:61616",
                    "java.naming.security.principal": "admin",
                    "java.naming.security.credentials": "admin",
                    "jndi.connection.factory": "connectionFactory",
                    "jms.destination.type": "queue",
                    "jms.destination.name": "DEV.QUEUE.1",
                    "key.converter": "org.apache.kafka.connect.storage.StringConverter",
                    "value.converter": "org.apache.kafka.connect.storage.StringConverter",
                    "confluent.license": "",
                    "confluent.topic.bootstrap.servers": "broker:9092",
                    "confluent.topic.replication.factor": "1"
          }}' \
     http://localhost:8083/connectors | jq .
```

Get messages from DEV.QUEUE.1 JMS queue:

```bash
$ curl -XGET -u admin:admin -d "body=message" http://localhost:8161/api/message/DEV.QUEUE.1?type=queue
```

We get:

```
This is my message
```

N.B: Control Center is reachable at [http://127.0.0.1:9021](http://127.0.0.1:9021])
