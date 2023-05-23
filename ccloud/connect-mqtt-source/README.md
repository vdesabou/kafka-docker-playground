# MQTT Source connector

## Objective

Quickly test [MQTT Source Connector](https://docs.confluent.io/kafka-connect-mqtt/current/mqtt-source-connector/index.html) connector with Confluent Cloud.

## Prerequisites

All you have to do is to be already logged in with [confluent CLI](https://docs.confluent.io/confluent-cli/current/overview.html#confluent-cli-overview).

By default, a new Confluent Cloud environment with a Cluster will be created.

You can configure the cluster by setting environment variables:

* `CLUSTER_CLOUD`: The Cloud provider (possible values: `aws`, `gcp` and `azure`, default `aws`)
* `CLUSTER_REGION`: The Cloud region (use `confluent kafka region list` to get the list, default `eu-west-2`)
* `CLUSTER_TYPE`: The type of cluster (possible values: `basic`, `standard` and `dedicated`, default `basic`)
* `ENVIRONMENT` (optional): The environment id where want your new cluster (example: `env-xxxxx`) 

In case you want to use your own existing cluster, you need to setup these environment variables:

* `ENVIRONMENT`: The environment id where your cluster is located (example: `env-xxxxx`) 
* `CLUSTER_NAME`: The cluster name
* `CLUSTER_CLOUD`: The Cloud provider (possible values: `aws`, `gcp` and `azure`)
* `CLUSTER_REGION`: The Cloud region (example `us-east-2`)
* `CLUSTER_CREDS`: The Kafka api key and secret to use, it should be separated with semi-colon (example: `<API_KEY>:<API_KEY_SECRET>`)
* `SCHEMA_REGISTRY_CREDS` (optional, if not set, new one will be created): The Schema Registry api key and secret to use, it should be separated with semi-colon (example: `<SR_API_KEY>:<SR_API_KEY_SECRET>`)

## How to run

```
$ playground run -f mqtt-source<tab>
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
               "topic.creation.default.replication.factor": "-1",
               "topic.creation.default.partitions": "-1",
               "confluent.topic.ssl.endpoint.identification.algorithm" : "https",
               "confluent.topic.sasl.mechanism" : "PLAIN",
               "confluent.topic.bootstrap.servers": "${file:/data:bootstrap.servers}",
               "confluent.topic.sasl.jaas.config" : "org.apache.kafka.common.security.plain.PlainLoginModule required username=\"${file:/data:sasl.username}\" password=\"${file:/data:sasl.password}\";",
               "confluent.topic.security.protocol" : "SASL_SSL",
               "confluent.topic.replication.factor": "3"
          }' \
     http://localhost:8083/connectors/mqtt-source/config | jq .
```

Send message to MQTT in `my-mqtt-topic` topic:

```bash
docker exec mosquitto sh -c 'mosquitto_pub -h localhost -p 1883 -u "myuser" -P "mypassword" -t "my-mqtt-topic" -m "sample-msg-1"'
```

Verify we have received the data in `mqtt-source-1` topic:

```bash
playground topic consume --topic mqtt-source-1 --expected-messages 1
```

N.B: Control Center is reachable at [http://127.0.0.1:9021](http://127.0.0.1:9021])
