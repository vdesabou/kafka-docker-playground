#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

set +e
docker rm -f c-ccloud-consumer c-ccloud-producer > /dev/null 2>&1
set -e

bootstrap_ccloud_environment

NB_MESSAGES=10
TOPIC=client_c_$TAG
GROUP=$TOPIC-group

# client.properties: the cluster of the environment, gitignored (it has the API key)
sed -e "s|:BOOTSTRAP_SERVERS:|$BOOTSTRAP_SERVERS|g" \
    -e "s|:CLOUD_KEY:|$CLOUD_KEY|g" \
    -e "s|:CLOUD_SECRET:|$CLOUD_SECRET|g" \
    ${DIR}/client.properties.template > ${DIR}/client.properties

function cleanup_cloud_resources {
    set +e
    log "Deleting topic $TOPIC and consumer group $GROUP"
    playground topic delete --topic $TOPIC
    playground consumer-group delete --group $GROUP
    docker rm -f c-ccloud-consumer c-ccloud-producer > /dev/null 2>&1
    set -e
}
trap cleanup_cloud_resources EXIT

log "Creating topic $TOPIC in Confluent Cloud (auto.create.topics.enable=false)"
set +e
playground topic delete --topic $TOPIC > /dev/null 2>&1
# committed offsets of a previous run would point past the records of the recreated topic
playground consumer-group delete --group $GROUP > /dev/null 2>&1
sleep 3
set -e
playground topic create --topic $TOPIC --nb-partitions 3

log "Building the C client image (librdkafka, same code as other/client-c)"
docker build -q -t kdp-client-c ${DIR}/../../other/client-c > /dev/null

# the client containers run with shorter TCP keepalives than the Linux default (2 hours), below the idle timeout of the
# Confluent Cloud load balancers
function run_client {
    docker run --rm --name "$1" --sysctl net.ipv4.tcp_keepalive_time=60 --sysctl net.ipv4.tcp_keepalive_intvl=30 \
        -v ${DIR}/client.properties:/tmp/client.properties:ro kdp-client-c client "$2" $TOPIC /tmp/client.properties $NB_MESSAGES
}

log "Producing $NB_MESSAGES string records with the C producer (librdkafka)"
run_client c-ccloud-producer produce

log "Consuming them with the C consumer, it fails if fewer than $NB_MESSAGES records arrive within 60 seconds"
run_client c-ccloud-consumer consume

log "Checking the records with playground topic consume"
playground topic consume --topic $TOPIC --min-expected-messages $NB_MESSAGES --timeout 60
