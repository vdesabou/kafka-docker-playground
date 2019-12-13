# MQTT Source connector

## Objective

Quickly test [MQTT Source](https://docs.confluent.io/current/connect/kafka-connect-mqtt/mqtt-source-connector/mqtt_source_connector_quickstart.html#example-configure-mqtt-source-connector-for-eclipse-mosquitto-broker) connector.

## Pre-requisites

* `docker-compose` (example `brew cask install docker`)

## How to run

Simply run:

```
$ ./mqtt.sh
```

## Details of what the script is doing

Note: The `./password` file was created with (`myuser/mypassword`) and command:

```bash
$ mosquitto_passwd -c password myuser
```

Creating MQTT Source connector

```bash
$ docker exec connect \
     curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.confluent.connect.mqtt.MqttSourceConnector",
                    "tasks.max": "1",
                    "mqtt.server.uri": "tcp://mosquitto:1883",
                    "mqtt.topics":"my-mqtt-topic",
                    "kafka.topic":"mqtt-source-1",
                    "mqtt.qos": "2",
                    "mqtt.username": "myuser",
                    "mqtt.password": "mypassword",
                    "confluent.license": "",
                    "confluent.topic.bootstrap.servers": "broker:9092",
                    "confluent.topic.replication.factor": "1"
          }' \
     http://localhost:8083/connectors/source-mqtt/config | jq .
```



Send message to MQTT in my-mqtt-topic topic

```bash
$ docker exec mosquitto sh -c 'mosquitto_pub -h localhost -p 1883 -u "myuser" -P "mypassword" -t "my-mqtt-topic" -m "sample-msg-1"'
```

Verify we have received the data in mqtt-source-1 topic

```bash
$ docker exec broker kafka-console-consumer -bootstrap-server broker:9092 --topic mqtt-source-1 --from-beginning --max-messages 1
```

N.B: Control Center is reachable at [http://127.0.0.1:9021](http://127.0.0.1:9021])
