# IBM MQ Source connector

## Objective

Quickly test [IBM MQ Source](https://docs.confluent.io/current/connect/kafka-connect-ibmmq/index.html) connector.

Using IBM MQ Docker [image](https://hub.docker.com/r/ibmcom/mq/)

## Pre-requisites

* `docker-compose` (example `brew cask install docker`)

* Follow [Installing IBM MQ Client Library](https://docs.confluent.io/current/connect/kafka-connect-ibmmq/sink/index.html#installing-ibm-mq-client-library) and place them in `./jms.jar` and `./com.ibm.mq.allclient.jar`

## How to run

Simply run:

```
$ ./ibm-mq.sh
```

## Details of what the script is doing

The connector is created with:

```bash
$ docker exec connect \
     curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.confluent.connect.ibm.mq.IbmMQSourceConnector",
                    "kafka.topic": "MyKafkaTopicName",
                    "mq.hostname": "ibmmq",
                    "mq.port": "1414",
                    "mq.transport.type": "client",
                    "mq.queue.manager": "QM1",
                    "mq.channel": "DEV.APP.SVRCONN",
                    "mq.username": "app",
                    "mq.password": "passw0rd",
                    "jms.destination.name": "DEV.QUEUE.1",
                    "jms.destination.type": "queue",
                    "confluent.license": "",
                    "confluent.topic.bootstrap.servers": "broker:9092",
                    "confluent.topic.replication.factor": "1"
          }' \
     http://localhost:8083/connectors/ibm-mq-source/config | jq_docker_cli .
```

Messages are sent to IBM MQ using:

```bash
$ docker exec -i ibmmq /opt/mqm/samp/bin/amqsput DEV.QUEUE.1 << EOF
Message 1
Message 2

EOF
```

Verify we have received the data in MyKafkaTopicName topic:

```bash
docker exec schema-registry kafka-avro-console-consumer -bootstrap-server broker:9092 --topic MyKafkaTopicName --from-beginning --max-messages 2
```

N.B: Control Center is reachable at [http://127.0.0.1:9021](http://127.0.0.1:9021])
