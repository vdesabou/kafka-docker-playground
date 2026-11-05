#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

bootstrap_ccloud_environment

TOPIC="client_rust_${TAG_BASE}"
GROUP="client_rust_group_${TAG_BASE}"
NB_MESSAGES=100

function cleanup_cloud_resources {
    set +e
    log "Deleting topic $TOPIC and consumer group $GROUP"
    playground topic delete --topic $TOPIC
    playground consumer-group delete --group $GROUP
    docker rm -f client-rust-ccloud-producer client-rust-ccloud-consumer > /dev/null 2>&1
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

log "Building the Rust client image (same code as other/client-rust), the first build takes a few minutes"
if [ -n "$CLIENT_VERSION" ]
then
     log "📦 CLIENT_VERSION is set: building the image with client version $CLIENT_VERSION"
fi
docker build -q --build-arg CLIENT_VERSION="${CLIENT_VERSION:-}" -t kdp-client-rust ${DIR}/../../other/client-rust > /dev/null
log "Rust client version: $(docker run --rm kdp-client-rust cat /usr/local/share/client-version.txt)"

# the API key and secret are passed as environment variables (-e NAME without a value): never on a command line
export SASL_USERNAME="$CLOUD_KEY"
export SASL_PASSWORD="$CLOUD_SECRET"

log "Producing $NB_MESSAGES records with the Rust producer (SASL_SSL, PLAIN)"
docker run --rm --name client-rust-ccloud-producer -e SASL_USERNAME -e SASL_PASSWORD kdp-client-rust producer "$BOOTSTRAP_SERVERS" $TOPIC $NB_MESSAGES

log "Consuming them with the Rust consumer (group.protocol=consumer), it fails if fewer than $NB_MESSAGES records arrive within 120 seconds"
docker run --rm --name client-rust-ccloud-consumer -e SASL_USERNAME -e SASL_PASSWORD kdp-client-rust consumer "$BOOTSTRAP_SERVERS" $TOPIC $GROUP $NB_MESSAGES 120

log "Checking the records with playground topic consume"
playground topic consume --topic $TOPIC --min-expected-messages $NB_MESSAGES --timeout 60

log "Checking the consumer group $GROUP (KIP-848 consumer protocol) committed all the offsets"
playground consumer-group describe --group $GROUP
