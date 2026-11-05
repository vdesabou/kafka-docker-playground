#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

set +e
docker rm -f javascript-ccloud-consumer javascript-ccloud-producer > /dev/null 2>&1
set -e

bootstrap_ccloud_environment

NB_MESSAGES=10
STRING_TOPIC=client_javascript_$TAG
AVRO_TOPIC=client_javascript_avro_$TAG

# client.properties: the cluster and Schema Registry of the environment, gitignored (it has the API keys)
sed -e "s|:BOOTSTRAP_SERVERS:|$BOOTSTRAP_SERVERS|g" \
    -e "s|:CLOUD_KEY:|$CLOUD_KEY|g" \
    -e "s|:CLOUD_SECRET:|$CLOUD_SECRET|g" \
    -e "s|:SCHEMA_REGISTRY_URL:|$SCHEMA_REGISTRY_URL|g" \
    -e "s|:SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO:|$SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO|g" \
    ${DIR}/client.properties.template > ${DIR}/client.properties

# playground topic delete also deletes the subjects <topic>-key and <topic>-value
function cleanup_cloud_resources {
    set +e
    log "Deleting topics $STRING_TOPIC and $AVRO_TOPIC (and subject $AVRO_TOPIC-value), and their consumer groups"
    playground topic delete --topic $STRING_TOPIC
    playground topic delete --topic $AVRO_TOPIC
    playground consumer-group delete --group $STRING_TOPIC-group
    playground consumer-group delete --group $AVRO_TOPIC-group
    docker rm -f javascript-ccloud-consumer javascript-ccloud-producer > /dev/null 2>&1
    set -e
}
trap cleanup_cloud_resources EXIT

log "Creating topics $STRING_TOPIC and $AVRO_TOPIC in Confluent Cloud (auto.create.topics.enable=false)"
set +e
playground topic delete --topic $STRING_TOPIC > /dev/null 2>&1
playground topic delete --topic $AVRO_TOPIC > /dev/null 2>&1
# committed offsets of a previous run would point past the records of the recreated topics
playground consumer-group delete --group $STRING_TOPIC-group > /dev/null 2>&1
playground consumer-group delete --group $AVRO_TOPIC-group > /dev/null 2>&1
sleep 3
set -e
playground topic create --topic $STRING_TOPIC
playground topic create --topic $AVRO_TOPIC

log "Building the JavaScript client image (same code as other/client-javascript)"
docker build -q -t vdesabou/javascript-ccloud-example-docker ${DIR}/../../other/client-javascript > /dev/null

# the client containers run with shorter TCP keepalives than the Linux default (2 hours), below the idle timeout of the
# Confluent Cloud load balancers
function run_client {
    docker run --rm --name "$1" --sysctl net.ipv4.tcp_keepalive_time=60 --sysctl net.ipv4.tcp_keepalive_intvl=30 \
        -v ${DIR}/client.properties:/tmp/client.properties:ro vdesabou/javascript-ccloud-example-docker node client.js "$2" "$3" /tmp/client.properties $NB_MESSAGES
}

log "Producing $NB_MESSAGES string records with the JavaScript producer"
run_client javascript-ccloud-producer produce $STRING_TOPIC

log "Consuming them with the JavaScript consumer, it fails if fewer than $NB_MESSAGES records arrive within 60 seconds"
run_client javascript-ccloud-consumer consume $STRING_TOPIC

log "Producing $NB_MESSAGES Avro records with the JavaScript producer (AvroSerializer, schema registered under subject $AVRO_TOPIC-value)"
run_client javascript-ccloud-producer produce-avro $AVRO_TOPIC

log "Consuming them with the JavaScript consumer (AvroDeserializer)"
run_client javascript-ccloud-consumer consume-avro $AVRO_TOPIC

log "Checking the Avro records with playground topic consume (Java deserializer, same schema)"
playground topic consume --topic $AVRO_TOPIC --min-expected-messages $NB_MESSAGES --timeout 60
