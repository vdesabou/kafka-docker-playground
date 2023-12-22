#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

playground start-environment --environment plaintext --docker-compose-override-file "${PWD}/docker-compose.plaintext.yml"

log "Creating datagen-source-users connector"
playground connector create-or-update --connector datagen-source-users << EOF
{
               "topics": "users",
               "tasks.max": "1",
               "connector.class": "io.confluent.kafka.connect.datagen.DatagenConnector",
               "kafka.topic": "users",
               "quickstart": "users",
               "key.converter": "org.apache.kafka.connect.storage.StringConverter",
               "key.converter.schemas.enable": "false",
               "value.converter": "io.confluent.connect.avro.AvroConverter",
               "value.converter.schema.registry.url": "http://schema-registry:8081",
               "value.converter.schemas.enable": "false",
               "max.interval": 100,
               "iterations": -1
          }
EOF

log "Creating http-sink connector"
playground connector create-or-update --connector http-sink << EOF
{
               "topics": "users",
               "tasks.max": "1",
               "connector.class": "io.confluent.connect.http.HttpSinkConnector",
               "key.converter": "org.apache.kafka.connect.storage.StringConverter",
               "value.converter": "io.confluent.connect.avro.AvroConverter",
               "value.converter.schema.registry.url": "http://schema-registry:8081",
               "confluent.topic.bootstrap.servers": "broker:9092",
               "confluent.topic.replication.factor": "1",
               "reporter.bootstrap.servers": "broker:9092",
               "reporter.error.topic.name": "error-responses",
               "reporter.error.topic.replication.factor": 1,
               "reporter.result.topic.name": "success-responses",
               "reporter.result.topic.replication.factor": 1,
               "http.api.url": "http://http-service-basic-auth:8080/api/messages",
               "auth.type": "BASIC",
               "connection.user": "admin",
               "connection.password": "password",
               "retry.on.status.codes" : "400-500"
          }
EOF

log "Creating http-sink-with-batching connector"
playground connector create-or-update --connector http-sink-with-batching << EOF
{
               "topics": "users",
               "tasks.max": "1",
               "connector.class": "io.confluent.connect.http.HttpSinkConnector",
               "key.converter": "org.apache.kafka.connect.storage.StringConverter",
               "value.converter": "io.confluent.connect.avro.AvroConverter",
               "value.converter.schema.registry.url": "http://schema-registry:8081",
               "confluent.topic.bootstrap.servers": "broker:9092",
               "confluent.topic.replication.factor": "1",
               "reporter.bootstrap.servers": "broker:9092",
               "reporter.error.topic.name": "error-responses",
               "reporter.error.topic.replication.factor": 1,
               "reporter.result.topic.name": "success-responses",
               "reporter.result.topic.replication.factor": 1,
               "http.api.url": "http://http-service-basic-auth:8080/api/messages",
               "auth.type": "BASIC",
               "connection.user": "admin",
               "connection.password": "password",
               "retry.on.status.codes" : "400-500",
               "batch.max.size": "1000"
          }
EOF

log "Creating http-sink-with-consumer-quota connector"
playground connector create-or-update --connector http-sink-with-consumer-quota << EOF
{
               "topics": "users",
               "tasks.max": "1",
               "connector.class": "io.confluent.connect.http.HttpSinkConnector",
               "key.converter": "org.apache.kafka.connect.storage.StringConverter",
               "value.converter": "io.confluent.connect.avro.AvroConverter",
               "value.converter.schema.registry.url": "http://schema-registry:8081",
               "confluent.topic.bootstrap.servers": "broker:9092",
               "confluent.topic.replication.factor": "1",
               "reporter.bootstrap.servers": "broker:9092",
               "reporter.error.topic.name": "error-responses",
               "reporter.error.topic.replication.factor": 1,
               "reporter.result.topic.name": "success-responses",
               "reporter.result.topic.replication.factor": 1,
               "http.api.url": "http://http-service-basic-auth:8080/api/messages",
               "auth.type": "BASIC",
               "connection.user": "admin",
               "connection.password": "password",
               "retry.on.status.codes" : "400-500"
          }
EOF

# log "Add a consumption 256B per broker quota to client.id connector-consumer-http-sink-with-consumer-quota-0" 
docker exec broker env -i bash -l -c "kafka-configs  --bootstrap-server localhost:9092 --alter --add-config 'consumer_byte_rate=256' --entity-name connector-consumer-http-sink-with-consumer-quota-0 --entity-type clients"
docker exec broker env -i bash -l -c "kafka-configs  --bootstrap-server localhost:9092 --describe --entity-name connector-consumer-http-sink-with-consumer-quota-0 --entity-type clients"

log "Creating s3-sink bucket"
docker exec s3 awslocal s3 mb s3://s3-sink-bucket

log "Creating s3-sink connector"
playground connector create-or-update --connector s3-sink << EOF
{
               "topics": "users",
               "tasks.max": "1",
               "connector.class": "io.confluent.connect.s3.S3SinkConnector",
               "key.converter": "org.apache.kafka.connect.storage.StringConverter",
               "value.converter": "io.confluent.connect.avro.AvroConverter",
               "value.converter.schema.registry.url": "http://schema-registry:8081",
               "confluent.topic.bootstrap.servers": "broker:9092",
               "confluent.topic.replication.factor": "1",
               "reporter.bootstrap.servers": "broker:9092",
               "reporter.error.topic.name": "error-responses",
               "reporter.error.topic.replication.factor": 1,
               "reporter.result.topic.name": "success-responses",
               "reporter.result.topic.replication.factor": 1,
               "aws.access.key.id": "MY_AWS_KEY_ID",
               "aws.secret.access.key": "MY_AWS_SECRET_ACCESS_KEY",
               "store.url": "http://s3:4566",
               "s3.region": "us-west-2",
               "s3.bucket.name": "s3-sink-bucket",
               "s3.part.size": 52428801,
               "flush.size": "1000",
               "storage.class": "io.confluent.connect.s3.storage.S3Storage",
               "format.class": "io.confluent.connect.s3.format.avro.AvroFormat",
               "schema.compatibility": "NONE"
               
          }
EOF

log "Creating http-sink-with-fetch-latency connector"
playground connector create-or-update --connector http-sink-with-fetch-latency << EOF
{
               "topics": "users",
               "tasks.max": "1",
               "connector.class": "io.confluent.connect.http.HttpSinkConnector",
               "key.converter": "org.apache.kafka.connect.storage.StringConverter",
               "value.converter": "io.confluent.connect.avro.AvroConverter",
               "value.converter.schema.registry.url": "http://schema-registry:8081",
               "confluent.topic.bootstrap.servers": "broker:9092",
               "confluent.topic.replication.factor": "1",
               "reporter.bootstrap.servers": "broker:9092",
               "reporter.error.topic.name": "error-responses",
               "reporter.error.topic.replication.factor": 1,
               "reporter.result.topic.name": "success-responses",
               "reporter.result.topic.replication.factor": 1,
               "http.api.url": "http://http-service-basic-auth:8080/api/messages",
               "auth.type": "BASIC",
               "connection.user": "admin",
               "connection.password": "password",
               "retry.on.status.codes" : "400-500"

          }
EOF

log "Creating http-sink-with-put-latency connector"
playground connector create-or-update --connector http-sink-with-put-latency << EOF
{
               "topics": "users",
               "tasks.max": "1",
               "connector.class": "io.confluent.connect.http.HttpSinkConnector",
               "key.converter": "org.apache.kafka.connect.storage.StringConverter",
               "value.converter": "io.confluent.connect.avro.AvroConverter",
               "value.converter.schema.registry.url": "http://schema-registry:8081",
               "confluent.topic.bootstrap.servers": "broker:9092",
               "confluent.topic.replication.factor": "1",
               "reporter.bootstrap.servers": "broker:9092",
               "reporter.error.topic.name": "error-responses",
               "reporter.error.topic.replication.factor": 1,
               "reporter.result.topic.name": "success-responses",
               "reporter.result.topic.replication.factor": 1,
               "http.api.url": "http://http-service-basic-auth:8080/api/messages",
               "auth.type": "BASIC",
               "connection.user": "admin",
               "connection.password": "password",
               "retry.on.status.codes" : "400-500"
          }
EOF

log "Creating http-sink-with-put-latency-and-batching connector"
playground connector create-or-update --connector http-sink-with-put-latency-and-batching << EOF
{
               "topics": "users",
               "tasks.max": "1",
               "connector.class": "io.confluent.connect.http.HttpSinkConnector",
               "key.converter": "org.apache.kafka.connect.storage.StringConverter",
               "value.converter": "io.confluent.connect.avro.AvroConverter",
               "value.converter.schema.registry.url": "http://schema-registry:8081",
               "confluent.topic.bootstrap.servers": "broker:9092",
               "confluent.topic.replication.factor": "1",
               "reporter.bootstrap.servers": "broker:9092",
               "reporter.error.topic.name": "error-responses",
               "reporter.error.topic.replication.factor": 1,
               "reporter.result.topic.name": "success-responses",
               "reporter.result.topic.replication.factor": 1,
               "http.api.url": "http://http-service-basic-auth:8080/api/messages",
               "auth.type": "BASIC",
               "connection.user": "admin",
               "connection.password": "password",
               "retry.on.status.codes" : "400-500",
               "batch.max.size": "1000"
          }
EOF

log "Creating s3-sink-with-put-latency bucket"
docker exec s3 awslocal s3 mb s3://s3-sink-with-put-latency-bucket

log "Creating s3-sink-with-put-latency connector"
playground connector create-or-update --connector s3-sink-with-put-latency << EOF
{
               "topics": "users",
               "tasks.max": "1",
               "connector.class": "io.confluent.connect.s3.S3SinkConnector",
               "key.converter": "org.apache.kafka.connect.storage.StringConverter",
               "value.converter": "io.confluent.connect.avro.AvroConverter",
               "value.converter.schema.registry.url": "http://schema-registry:8081",
               "confluent.topic.bootstrap.servers": "broker:9092",
               "confluent.topic.replication.factor": "1",
               "reporter.bootstrap.servers": "broker:9092",
               "reporter.error.topic.name": "error-responses",
               "reporter.error.topic.replication.factor": 1,
               "reporter.result.topic.name": "success-responses",
               "reporter.result.topic.replication.factor": 1,
               "aws.access.key.id": "MY_AWS_KEY_ID",
               "aws.secret.access.key": "MY_AWS_SECRET_ACCESS_KEY",
               "store.url": "http://s3:4566",
               "s3.region": "us-west-2",
               "s3.bucket.name": "s3-sink-with-put-latency-bucket",
               "s3.part.size": 52428801,
               "flush.size": "1000",
               "storage.class": "io.confluent.connect.s3.storage.S3Storage",
               "format.class": "io.confluent.connect.s3.format.avro.AvroFormat",
               "schema.compatibility": "NONE"
               
          }
EOF

source ${DIR}/tc-utils.sh

# connect-with-fetch-latency
latency_fetch=$(get_latency connect-with-fetch-latency broker)
log "Latency from connect-with-fetch-latency to broker BEFORE traffic control: $latency_fetch ms"

add_latency connect-with-fetch-latency broker 100ms

latency_fetch=$(get_latency connect-with-fetch-latency broker)
log "Latency from connect-with-fetch-latency to broker AFTER traffic control: $latency_fetch ms"

# connect-with-put-latency
latency_put=$(get_latency connect-with-put-latency http-service-basic-auth)
log "Latency from connect-with-put-latency to http-service-basic-auth BEFORE traffic control: $latency_put ms"

add_latency connect-with-put-latency http-service-basic-auth 100ms

latency_put=$(get_latency connect-with-put-latency http-service-basic-auth)
log "Latency from connect-with-put-latency to http-service-basic-auth AFTER traffic control: $latency_put ms"

if [ ! -z "$GITHUB_RUN_NUMBER" ]
then
     # running with github actions
     log "##################################################"
     log "Stopping everything"
     log "##################################################"
     bash ${DIR}/stop.sh
fi