# MQTT Source connector

## Objective

Quickly test [MQTT Source Connector](https://docs.confluent.io/kafka-connect-mqtt/current/mqtt-source-connector/index.html) connector with Confluent Cloud.

## How to run

Simply set the environment variables for connection to your Confluent Cloud cluster and run:

```bash
$ export BOOTSTRAP_SERVERS=XXX
$ export SASL_JAAS_CONFIG="org.apache.kafka.common.security.plain.PlainLoginModule required username='<<api_key>>' password='<<api_secret>>';"
$ export SCHEMA_REGISTRY_URL=YYY
$ export SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO=SR_KEY:SR_SECRET
$ export BASIC_AUTH_CREDENTIALS_SOURCE=USER_INFO
$ ./mqtt.sh
```

## Details of what the script is doing

Note: The `./password` file was created with (`myuser/mypassword`) and command:

```bash
$ mosquitto_passwd -c password myuser
```

The connector is created with (this also passes license info as this is an enterprise connector):

```
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
               "confluent.topic.ssl.endpoint.identification.algorithm" : "https",
               "confluent.topic.sasl.mechanism" : "PLAIN",
               "confluent.topic.bootstrap.servers": "${file:/data:bootstrap.servers}",
               "confluent.topic.sasl.jaas.config" : "org.apache.kafka.common.security.plain.PlainLoginModule required username=\"${file:/data:sasl.username}\" password=\"${file:/data:sasl.password}\";",
               "confluent.topic.security.protocol" : "SASL_SSL",
               "confluent.topic.replication.factor": "3"
          }' \
     http://localhost:8083/connectors/source-mqtt/config | jq .
```
If the license settings are applied in the underlying Connect Worker, or already available in the Confluent Cloud cluster you can use the simpler form:

``` bash
$ curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.confluent.connect.mqtt.MqttSourceConnector",
               "tasks.max": "1",
               "mqtt.server.uri": "tcp://mosquitto:1883",
               "mqtt.topics":"basic1-topic",
               "kafka.topic":"basic1",
               "mqtt.qos": "2",
               "mqtt.username": "myuser",
               "mqtt.password": "mypassword",
                "value.converter": "org.apache.kafka.connect.converters.ByteArrayConverter"
          }' \
     http://localhost:8083/connectors/basic1-mqtt/config | jq .
```

Send message to MQTT in basic1-topic topic from a file

```bash
$ confluent kafka topic create "basic1"
$ docker exec -i mosquitto sh -c 'mosquitto_pub -h localhost -p 1883 -u "myuser" -P "mypassword" -t "basic1-topic" -s' < basic_data.json
```

Verify we have received the data in basic1-topic topic (uses the property file created in ../environment/data)

```bash
$ docker exec -e BOOTSTRAP_SERVERS="$BOOTSTRAP_SERVERS" -e KAFKA_TOPIC="basic1-topic" connect bash -c 'kafka-console-consumer --bootstrap-server $BOOTSTRAP_SERVERS  --consumer.config /data/ --topic $KAFKA_TOPIC --from-beginning --max-messages 1'
```

N.B: Control Center is reachable at [http://127.0.0.1:9021](http://127.0.0.1:9021])
