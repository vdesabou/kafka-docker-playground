# IBM MQ Source connector

## Objective

Quickly test [IBM MQ Source](https://docs.confluent.io/current/connect/kafka-connect-ibmmq/index.html) connector.

Using IBM MQ Docker [image](https://hub.docker.com/r/ibmcom/mq/)

## Pre-requisites

* `docker-compose` (example `brew cask install docker`)
* Download [9.0.0.8-IBM-MQ-Install-Java-All.jar](https://www-945.ibm.com/support/fixcentral/swg/selectFixes?product=ibm%2FWebSphere%2FWebSphere+MQ&fixids=9.0.0.4-IBM-MQ-Install-Java-All&source=dbluesearch&function=fixId&parent=ibm/WebSphere) and place it in `./9.0.0.8-IBM-MQ-Install-Java-All.jar`

![IBM download page](Screenshot1.png)

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
     http://localhost:8083/connectors/ibm-mq-source/config | jq .
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
docker exec connect kafka-avro-console-consumer -bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic MyKafkaTopicName --from-beginning --max-messages 2
```

N.B: Control Center is reachable at [http://127.0.0.1:9021](http://127.0.0.1:9021])
