# MQTT Sink connector

![asciinema](asciinema.gif)

## Objective

Quickly test [MQTT Sink](https://docs.confluent.io/current/connect/kafka-connect-mqtt/mqtt-sink-connector/mqtt_sink_connector_quickstart.html#example-configure-mqtt-sink-connector-for-eclipse-mosquitto-broker) connector.

## Pre-requisites

* `docker-compose` (example `brew cask install docker`)

## How to run

Simply run:

```
$ ./mqtt-sink.sh
```

## Details of what the script is doing

Note: The `./password` file was created with (`myuser/mypassword`) and command:

```bash
$ mosquitto_passwd -c password myuser
```

Sending messages to topic sink-messages

```bash
$ docker exec -i broker kafka-console-producer --broker-list broker:9092 --topic sink-messages << EOF
This is my message
EOF
```

Creating MQTT Sink connector

```bash
$ docker exec connect \
     curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.confluent.connect.mqtt.MqttSinkConnector",
                    "tasks.max": "1",
                    "mqtt.server.uri": "tcp://mosquitto:1883",
                    "topics":"sink-messages",
                    "mqtt.qos": "2",
                    "mqtt.username": "myuser",
                    "mqtt.password": "mypassword",
                    "key.converter": "org.apache.kafka.connect.storage.StringConverter",
                    "value.converter": "org.apache.kafka.connect.storage.StringConverter",
                    "confluent.license": "",
                    "confluent.topic.bootstrap.servers": "broker:9092",
                    "confluent.topic.replication.factor": "1"
          }' \
     http://localhost:8083/connectors/sink-mqtt/config | jq .
```

Verify we have received messages in MQTT sink-messages topic

```bash
docker exec mosquitto sh -c 'mosquitto_sub -h localhost -p 1883 -u "myuser" -P "mypassword" -t "sink-messages" -C 1'
```

N.B: Control Center is reachable at [http://127.0.0.1:9021](http://127.0.0.1:9021])
