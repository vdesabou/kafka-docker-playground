# MQTT Source connector



## Objective

Quickly test [MQTT Source](https://docs.confluent.io/current/connect/kafka-connect-mqtt/mqtt-source-connector/mqtt_source_connector_quickstart.html#example-configure-mqtt-source-connector-for-eclipse-mosquitto-broker) connector.


## How to run

Simply run:

```
$ ./mqtt.sh
```

or using SMT [jcustenborder/kafka-connect-json-schema](https://www.confluent.io/hub/jcustenborder/kafka-connect-json-schema) in order to be able to workaround MQTT connector only able to handle ByteArray or String:

```
$ ./mqtt-avro.sh
```

SMT:

```json
"transforms" : "fromJson",
"transforms.fromJson.type" : "com.github.jcustenborder.kafka.connect.json.FromJson$Value",
"transforms.fromJson.json.schema.location" : "Inline",
"transforms.fromJson.json.schema.inline" : "{\n  \"$id\": \"https://example.com/person.schema.json\",\n  \"$schema\": \"http://json-schema.org/draft-07/schema#\",\n  \"title\": \"Person\",\n  \"type\": \"object\",\n  \"properties\": {\n    \"firstName\": {\n      \"type\": \"string\",\n      \"description\": \"The person first name.\"\n    },\n    \"lastName\": {\n      \"type\": \"string\",\n      \"description\": \"The person last name.\"\n    },\n    \"age\": {\n      \"description\": \"Age in years which must be equal to or greater than zero.\",\n      \"type\": \"integer\",\n      \"minimum\": 0\n    }\n  }\n}",
"confluent.license": "",
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
$ docker exec broker kafka-console-consumer -bootstrap-server broker:9092 --topic mqtt-source-1 --from-beginning --max-messages 1
```

Results:

```
sample-msg-1
```

N.B: Control Center is reachable at [http://127.0.0.1:9021](http://127.0.0.1:9021])
