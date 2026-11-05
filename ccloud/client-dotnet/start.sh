#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

set +e
docker rm -f dotnet-ccloud-consumer dotnet-ccloud-producer > /dev/null 2>&1
set -e

bootstrap_ccloud_environment

NB_MESSAGES=10
STRING_TOPIC=client_dotnet_$TAG
AVRO_TOPIC=client_dotnet_avro_$TAG

# librdkafka.config: the cluster and Schema Registry of the environment, gitignored (it has the API keys)
sed -e "s|:BOOTSTRAP_SERVERS:|$BOOTSTRAP_SERVERS|g" \
    -e "s|:CLOUD_KEY:|$CLOUD_KEY|g" \
    -e "s|:CLOUD_SECRET:|$CLOUD_SECRET|g" \
    -e "s|:SCHEMA_REGISTRY_URL:|$SCHEMA_REGISTRY_URL|g" \
    -e "s|:SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO:|$SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO|g" \
    ${DIR}/librdkafka.config.template > ${DIR}/librdkafka.config

# playground topic delete also deletes the subjects <topic>-key and <topic>-value
function cleanup_cloud_resources {
    set +e
    log "Deleting topics $STRING_TOPIC and $AVRO_TOPIC, and subject $AVRO_TOPIC-value"
    playground topic delete --topic $STRING_TOPIC
    playground topic delete --topic $AVRO_TOPIC
    set -e
}
trap cleanup_cloud_resources EXIT

log "Creating topics $STRING_TOPIC and $AVRO_TOPIC in Confluent Cloud (auto.create.topics.enable=false)"
set +e
playground topic delete --topic $STRING_TOPIC > /dev/null 2>&1
playground topic delete --topic $AVRO_TOPIC > /dev/null 2>&1
sleep 3
set -e
playground topic create --topic $STRING_TOPIC
playground topic create --topic $AVRO_TOPIC

log "Building the .NET client image (.NET 10, Confluent.Kafka 2.16.0)"
docker build -q -t vdesabou/dotnet-ccloud-example-docker ${DIR} > /dev/null

# the client containers run with shorter TCP keepalives than the Linux default (2 hours), below the idle timeout of the
# Confluent Cloud load balancers
function run_client {
    docker run --rm --name "$1" --sysctl net.ipv4.tcp_keepalive_time=60 --sysctl net.ipv4.tcp_keepalive_intvl=30 \
        -v ${DIR}/librdkafka.config:/tmp/librdkafka.config:ro vdesabou/dotnet-ccloud-example-docker "$2" "$3" /tmp/librdkafka.config $NB_MESSAGES
}

log "Producing $NB_MESSAGES string records with the .NET producer"
run_client dotnet-ccloud-producer produce $STRING_TOPIC

log "Consuming them with the .NET consumer, it fails if fewer than $NB_MESSAGES records arrive within 60 seconds"
run_client dotnet-ccloud-consumer consume $STRING_TOPIC

log "Producing $NB_MESSAGES Avro records with the .NET producer (AvroSerializer, schema registered under subject $AVRO_TOPIC-value)"
run_client dotnet-ccloud-producer produce-avro $AVRO_TOPIC

log "Consuming them with the .NET consumer (AvroDeserializer)"
run_client dotnet-ccloud-consumer consume-avro $AVRO_TOPIC

log "Checking the Avro records with playground topic consume (Java deserializer, same schema)"
playground topic consume --topic $AVRO_TOPIC --min-expected-messages $NB_MESSAGES --timeout 60
