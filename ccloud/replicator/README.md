# Replicator (using Confluent Cloud)

## Cloud to Cloud example

### Prerequisites

When the script run, it will ask to login using ccloud, this will be the destination cluster.

You need to fill information for source cluster in `env.source` file:

```
$ cat env.source

BOOTSTRAP_SERVERS_SRC="xxx.confluent.cloud:9092"
CLOUD_KEY_SRC="xxx"
CLOUD_SECRET_SRC="xxxx"
SASL_JAAS_CONFIG_SRC="org.apache.kafka.common.security.plain.PlainLoginModule required username=\"$CLOUD_KEY_SRC\" password=\"$CLOUD_SECRET_SRC\";"
SCHEMA_REGISTRY_URL_SRC="https://xxxx.confluent.cloud"
SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO_SRC="xxx:xxx"
```

The `topic-replicator`in the source cluster should be created manually

### How to run

```
$ ./cloud-to-cloud.sh
```

### Details of what the script is doing

Sending messages to topic topic-replicator-avro on SRC cluster (topic topic-replicator-avro should be created manually first)

```bash
$ docker exec -i -e BOOTSTRAP_SERVERS_SRC="$BOOTSTRAP_SERVERS_SRC" -e SASL_JAAS_CONFIG_SRC="$SASL_JAAS_CONFIG_SRC" -e SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO_SRC="$SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO_SRC" -e SCHEMA_REGISTRY_URL_SRC="$SCHEMA_REGISTRY_URL_SRC" connect kafka-avro-console-producer --broker-list $BOOTSTRAP_SERVERS_SRC --producer-property ssl.endpoint.identification.algorithm=https --producer-property sasl.mechanism=PLAIN --producer-property security.protocol=SASL_SSL --producer-property sasl.jaas.config="$SASL_JAAS_CONFIG_SRC" --property basic.auth.credentials.source=USER_INFO --property schema.registry.basic.auth.user.info="$SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO_SRC" --property schema.registry.url=$SCHEMA_REGISTRY_URL_SRC --topic topic-replicator --property value.schema='{"type":"record","name":"myrecord","fields":[{"name":"u_name","type":"string"},{"name":"u_price", "type": "float"}, {"name":"u_quantity", "type": "int"}]}' << EOF
{"u_name": "scissors", "u_price": 2.75, "u_quantity": 3}
{"u_name": "tape", "u_price": 0.99, "u_quantity": 10}
{"u_name": "notebooks", "u_price": 1.99, "u_quantity": 5}
EOF
```

```bash
$ docker container exec -e BOOTSTRAP_SERVERS="$BOOTSTRAP_SERVERS" -e CLOUD_KEY="$CLOUD_KEY" -e CLOUD_SECRET="$CLOUD_SECRET" -e BOOTSTRAP_SERVERS_SRC="$BOOTSTRAP_SERVERS_SRC" -e CLOUD_KEY_SRC="$CLOUD_KEY_SRC" -e CLOUD_SECRET_SRC="$CLOUD_SECRET_SRC" connect \
     curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
          "connector.class":"io.confluent.connect.replicator.ReplicatorSourceConnector",
          "key.converter": "io.confluent.connect.replicator.util.ByteArrayConverter",
          "value.converter": "io.confluent.connect.replicator.util.ByteArrayConverter",
          "header.converter": "io.confluent.connect.replicator.util.ByteArrayConverter",
          "src.consumer.group.id": "replicate-demo-to-travis",
          "src.kafka.ssl.endpoint.identification.algorithm":"https",
          "src.kafka.bootstrap.servers": "'"$BOOTSTRAP_SERVERS_SRC"'",
          "src.kafka.security.protocol" : "SASL_SSL",
          "src.kafka.sasl.jaas.config": "org.apache.kafka.common.security.plain.PlainLoginModule required username=\"'$CLOUD_KEY_SRC'\" password=\"'$CLOUD_SECRET_SRC'\";",
          "src.kafka.sasl.mechanism":"PLAIN",
          "src.kafka.request.timeout.ms":"20000",
          "src.kafka.retry.backoff.ms":"500",
          "dest.kafka.ssl.endpoint.identification.algorithm":"https",
          "dest.kafka.bootstrap.servers": "'"$BOOTSTRAP_SERVERS"'",
          "dest.kafka.security.protocol" : "SASL_SSL",
          "dest.kafka.sasl.jaas.config": "org.apache.kafka.common.security.plain.PlainLoginModule required username=\"'$CLOUD_KEY'\" password=\"'$CLOUD_SECRET'\";",
          "dest.kafka.sasl.mechanism":"PLAIN",
          "dest.kafka.request.timeout.ms":"20000",
          "dest.kafka.retry.backoff.ms":"500",
          "confluent.topic.ssl.endpoint.identification.algorithm" : "https",
          "confluent.topic.sasl.mechanism" : "PLAIN",
          "confluent.topic.bootstrap.servers": "'"$BOOTSTRAP_SERVERS_SRC"'",
          "confluent.topic.sasl.jaas.config" : "org.apache.kafka.common.security.plain.PlainLoginModule required username=\"'$CLOUD_KEY_SRC'\" password=\"'$CLOUD_SECRET_SRC'\";",
          "confluent.topic.security.protocol" : "SASL_SSL",
          "confluent.topic.replication.factor": "3",
          "provenance.header.enable": true,
          "topic.whitelist": "topic-replicator"
          }' \
     http://localhost:8083/connectors/replicate-demo-to-travis/config | jq .
```


Verify we have received the data in topic-replicator topic

```bash
$ docker container exec -e BOOTSTRAP_SERVERS="$BOOTSTRAP_SERVERS" -e SASL_JAAS_CONFIG="$SASL_JAAS_CONFIG" -e BASIC_AUTH_CREDENTIALS_SOURCE="$BASIC_AUTH_CREDENTIALS_SOURCE" -e SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO="$SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO" -e SCHEMA_REGISTRY_URL="$SCHEMA_REGISTRY_URL" connect bash -c 'kafka-avro-console-consumer --topic topic-replicator --bootstrap-server $BOOTSTRAP_SERVERS --consumer-property ssl.endpoint.identification.algorithm=https --consumer-property sasl.mechanism=PLAIN --consumer-property security.protocol=SASL_SSL --consumer-property sasl.jaas.config="$SASL_JAAS_CONFIG" --property basic.auth.credentials.source=$BASIC_AUTH_CREDENTIALS_SOURCE --property schema.registry.basic.auth.user.info="$SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO" --property schema.registry.url=$SCHEMA_REGISTRY_URL --from-beginning --max-messages 3'
```

## OnPrem to Cloud example

### How to run

```
$ ./onprem-to-cloud.sh
```

### Details of what the script is doing

The script does:

Creating topic in Confluent Cloud (auto.create.topics.enable=false)

```bash
$ create_topic products
```

Sending messages to topic products on source OnPREM cluster

```bash
$ docker exec -i connect kafka-avro-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic products --property value.schema='{"type":"record","name":"myrecord","fields":[{"name":"name","type":"string"},
{"name":"price", "type": "float"}, {"name":"quantity", "type": "int"}]}' << EOF
{"name": "scissors", "price": 2.75, "quantity": 3}
{"name": "tape", "price": 0.99, "quantity": 10}
{"name": "notebooks", "price": 1.99, "quantity": 5}
EOF
```

```bash
$ docker container exec -e BOOTSTRAP_SERVERS="$BOOTSTRAP_SERVERS" -e CLOUD_KEY="$CLOUD_KEY" -e CLOUD_SECRET="$CLOUD_SECRET" -e BOOTSTRAP_SERVERS_SRC="$BOOTSTRAP_SERVERS_SRC" -e CLOUD_KEY_SRC="$CLOUD_KEY_SRC" -e CLOUD_SECRET_SRC="$CLOUD_SECRET_SRC" connect \
     curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
          "connector.class":"io.confluent.connect.replicator.ReplicatorSourceConnector",
          "key.converter": "io.confluent.connect.replicator.util.ByteArrayConverter",
          "value.converter": "io.confluent.connect.replicator.util.ByteArrayConverter",
          "header.converter": "io.confluent.connect.replicator.util.ByteArrayConverter",
          "src.consumer.group.id": "replicate-onprem-to-cloud",
          "src.kafka.bootstrap.servers": "broker:9092",
          "dest.kafka.ssl.endpoint.identification.algorithm":"https",
          "dest.kafka.bootstrap.servers": "'"$BOOTSTRAP_SERVERS"'",
          "dest.kafka.security.protocol" : "SASL_SSL",
          "dest.kafka.sasl.jaas.config": "org.apache.kafka.common.security.plain.PlainLoginModule required username=\"'$CLOUD_KEY'\" password=\"'$CLOUD_SECRET'\";",
          "dest.kafka.sasl.mechanism":"PLAIN",
          "dest.kafka.request.timeout.ms":"20000",
          "dest.kafka.retry.backoff.ms":"500",
          "confluent.topic.ssl.endpoint.identification.algorithm" : "https",
          "confluent.topic.sasl.mechanism" : "PLAIN",
          "confluent.topic.bootstrap.servers": "'"$BOOTSTRAP_SERVERS"'",
          "confluent.topic.sasl.jaas.config" : "org.apache.kafka.common.security.plain.PlainLoginModule required username=\"'$CLOUD_KEY'\" password=\"'$CLOUD_SECRET'\";",
          "confluent.topic.security.protocol" : "SASL_SSL",
          "confluent.topic.replication.factor": "3",
          "provenance.header.enable": true,
          "topic.whitelist": "products",
          "topic.config.sync": false,
          "topic.auto.create": false
          }' \
     http://localhost:8083/connectors/replicate-onprem-to-cloud/config | jq .
```

Verify we have received the data in `products` topic:


```bash
$ docker container exec -e BOOTSTRAP_SERVERS="$BOOTSTRAP_SERVERS" -e SASL_JAAS_CONFIG="$SASL_JAAS_CONFIG" -e BASIC_AUTH_CREDENTIALS_SOURCE="$BASIC_AUTH_CREDENTIALS_SOURCE" -e SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO="$SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO" -e SCHEMA_REGISTRY_URL="$SCHEMA_REGISTRY_URL" connect bash -c 'kafka-avro-console-consumer --topic products --bootstrap-server $BOOTSTRAP_SERVERS --consumer-property ssl.endpoint.identification.algorithm=https --consumer-property sasl.mechanism=PLAIN --consumer-property security.protocol=SASL_SSL --consumer-property sasl.jaas.config="$SASL_JAAS_CONFIG" --property basic.auth.credentials.source=$BASIC_AUTH_CREDENTIALS_SOURCE --property schema.registry.basic.auth.user.info="$SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO" --property schema.registry.url=$SCHEMA_REGISTRY_URL --from-beginning --max-messages 3'
```


## Avro Converter examples

The two example above are using default `value.converter`=`io.confluent.connect.replicator.util.ByteArrayConverter` which does not preserve the schemas.

There are two scripts ending with `-repro-avro.sh`that are using `value.converter`=`io.confluent.connect.avro.AvroConverter` that preserve schemas:

### Cloud to Cloud example

```bash
docker container exec -e BOOTSTRAP_SERVERS="$BOOTSTRAP_SERVERS" -e CLOUD_KEY="$CLOUD_KEY" -e CLOUD_SECRET="$CLOUD_SECRET" -e BOOTSTRAP_SERVERS_SRC="$BOOTSTRAP_SERVERS_SRC" -e CLOUD_KEY_SRC="$CLOUD_KEY_SRC" -e CLOUD_SECRET_SRC="$CLOUD_SECRET_SRC" -e SCHEMA_REGISTRY_URL_SRC="$SCHEMA_REGISTRY_URL_SRC" -e SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO_SRC="$SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO_SRC" -e SCHEMA_REGISTRY_URL="$SCHEMA_REGISTRY_URL" -e SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO="$SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO" connect \
     curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
          "connector.class":"io.confluent.connect.replicator.ReplicatorSourceConnector",
          "src.consumer.group.id": "replicate-demo-to-travis",
          "src.value.converter": "io.confluent.connect.avro.AvroConverter",
          "src.value.converter.schema.registry.url": "'"$SCHEMA_REGISTRY_URL_SRC"'",
          "src.value.converter.basic.auth.user.info": "'"$SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO_SRC"'",
          "src.value.converter.basic.auth.credentials.source": "USER_INFO",

          "src.kafka.ssl.endpoint.identification.algorithm":"https",
          "src.kafka.bootstrap.servers": "'"$BOOTSTRAP_SERVERS_SRC"'",
          "src.kafka.security.protocol" : "SASL_SSL",
          "src.kafka.sasl.jaas.config": "org.apache.kafka.common.security.plain.PlainLoginModule required username=\"'$CLOUD_KEY_SRC'\" password=\"'$CLOUD_SECRET_SRC'\";",
          "src.kafka.sasl.mechanism":"PLAIN",
          "src.request.timeout.ms": "20000",
          "src.retry.backoff.ms": "500",

          "value.converter": "io.confluent.connect.avro.AvroConverter",
          "value.converter.schema.registry.url": "'"$SCHEMA_REGISTRY_URL"'",
          "value.converter.basic.auth.user.info": "'"$SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO"'",
          "value.converter.basic.auth.credentials.source": "USER_INFO",

          "dest.kafka.ssl.endpoint.identification.algorithm":"https",
          "dest.kafka.bootstrap.servers": "'"$BOOTSTRAP_SERVERS"'",
          "dest.kafka.security.protocol" : "SASL_SSL",
          "dest.kafka.sasl.jaas.config": "org.apache.kafka.common.security.plain.PlainLoginModule required username=\"'$CLOUD_KEY'\" password=\"'$CLOUD_SECRET'\";",
          "dest.kafka.sasl.mechanism":"PLAIN",
          "dest.kafka.request.timeout.ms":"20000",
          "dest.kafka.retry.backoff.ms":"500",
          "confluent.topic.ssl.endpoint.identification.algorithm" : "https",
          "confluent.topic.sasl.mechanism" : "PLAIN",
          "confluent.topic.bootstrap.servers": "'"$BOOTSTRAP_SERVERS_SRC"'",
          "confluent.topic.sasl.jaas.config" : "org.apache.kafka.common.security.plain.PlainLoginModule required username=\"'$CLOUD_KEY_SRC'\" password=\"'$CLOUD_SECRET_SRC'\";",
          "confluent.topic.security.protocol" : "SASL_SSL",
          "confluent.topic.replication.factor": "3",
          "provenance.header.enable": true,
          "topic.whitelist": "topic-replicator-avro"
          }' \
     http://localhost:8083/connectors/replicate-demo-to-travis/config | jq .
```

## OnPrem to Cloud example

```bash
docker container exec -e BOOTSTRAP_SERVERS="$BOOTSTRAP_SERVERS" -e CLOUD_KEY="$CLOUD_KEY" -e CLOUD_SECRET="$CLOUD_SECRET" -e BOOTSTRAP_SERVERS_SRC="$BOOTSTRAP_SERVERS_SRC" -e CLOUD_KEY_SRC="$CLOUD_KEY_SRC" -e CLOUD_SECRET_SRC="$CLOUD_SECRET_SRC" -e SCHEMA_REGISTRY_URL="$SCHEMA_REGISTRY_URL" -e SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO="$SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO" connect \
     curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
          "connector.class":"io.confluent.connect.replicator.ReplicatorSourceConnector",
          "src.consumer.group.id": "replicate-onprem-to-cloud",
          "src.value.converter": "io.confluent.connect.avro.AvroConverter",
          "src.value.converter.schema.registry.url": "http://schema-registry:8081",
          "src.kafka.bootstrap.servers": "broker:9092",

          "value.converter": "io.confluent.connect.avro.AvroConverter",
          "value.converter.schema.registry.url": "'"$SCHEMA_REGISTRY_URL"'",
          "value.converter.basic.auth.user.info": "'"$SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO"'",
          "value.converter.basic.auth.credentials.source": "USER_INFO",

          "dest.kafka.ssl.endpoint.identification.algorithm":"https",
          "dest.kafka.bootstrap.servers": "'"$BOOTSTRAP_SERVERS"'",
          "dest.kafka.security.protocol" : "SASL_SSL",
          "dest.kafka.sasl.jaas.config": "org.apache.kafka.common.security.plain.PlainLoginModule required username=\"'$CLOUD_KEY'\" password=\"'$CLOUD_SECRET'\";",
          "dest.kafka.sasl.mechanism":"PLAIN",
          "dest.kafka.request.timeout.ms":"20000",
          "dest.kafka.retry.backoff.ms":"500",
          "confluent.topic.ssl.endpoint.identification.algorithm" : "https",
          "confluent.topic.sasl.mechanism" : "PLAIN",
          "confluent.topic.bootstrap.servers": "'"$BOOTSTRAP_SERVERS"'",
          "confluent.topic.sasl.jaas.config" : "org.apache.kafka.common.security.plain.PlainLoginModule required username=\"'$CLOUD_KEY'\" password=\"'$CLOUD_SECRET'\";",
          "confluent.topic.security.protocol" : "SASL_SSL",
          "confluent.topic.replication.factor": "3",
          "provenance.header.enable": true,
          "topic.whitelist": "products-avro",
          "topic.config.sync": false,
          "topic.auto.create": false
          }' \
     http://localhost:8083/connectors/replicate-onprem-to-cloud/config | jq .
```

N.B: Control Center is reachable at [http://127.0.0.1:9021](http://127.0.0.1:9021])
