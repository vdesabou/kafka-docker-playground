# MQTT Source connector



## Objective

Quickly test [MQTT Source](https://docs.confluent.io/current/connect/kafka-connect-mqtt/mqtt-source-connector/mqtt_source_connector_quickstart.html#example-configure-mqtt-source-connector-for-eclipse-mosquitto-broker) connector.


## How to run

Simply run:

```
$ playground run -f mqtt<use tab key to activate fzf completion (see https://kafka-docker-playground.io/#/cli?id=%e2%9a%a1-setup-completion), otherwise use full path, or relative path>
```

or with MTLS

```
$ playground run -f mqtt-source-mtls<use tab key to activate fzf completion (see https://kafka-docker-playground.io/#/cli?id=%e2%9a%a1-setup-completion), otherwise use full path, or relative path>
```

## Details of what the script is doing

Note: The `./password` file was created with (`myuser/mypassword`) and command:

```bash
$ mosquitto_passwd -c password myuser
```

Creating MQTT Source connector

```bash
$ curl -X PUT \
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
playground topic consume --topic mqtt-source-1 --min-expected-messages 1 --timeout 60
```

Results:

```
sample-msg-1
```

N.B: Control Center is reachable at [http://127.0.0.1:9021](http://127.0.0.1:9021])
