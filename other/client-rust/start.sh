#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

# the Rust client only implements the KIP-848 consumer group protocol (group.protocol=consumer), GA in CP 8.0 (Apache Kafka 4.0)
if ! version_gt $TAG_BASE "7.9.99"
then
     logwarn "The Confluent Rust client consumer needs the KIP-848 consumer group protocol, GA since CP 8.0, skipping with CP $TAG"
     exit 111
fi

if [ -n "$CLIENT_VERSION" ]
then
     log "📦 CLIENT_VERSION is set: building the client-rust image with client version $CLIENT_VERSION"
fi

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.yml"

NB_MESSAGES=100

log "Rust client version (confluent-kafka crate) in the image"
playground container exec -c client-rust --command "cat /usr/local/share/client-version.txt"

log "Creating topic client-rust"
playground topic create --topic client-rust --nb-partitions 3

log "Producing $NB_MESSAGES records with the Rust producer"
playground container exec -c client-rust --command "producer broker:9092 client-rust $NB_MESSAGES"

log "Consuming them with the Rust consumer (group.protocol=consumer), it fails if fewer than $NB_MESSAGES records arrive within 60 seconds"
playground container exec -c client-rust --command "consumer broker:9092 client-rust client-rust-group $NB_MESSAGES 60"

log "Checking the records with playground topic consume"
playground topic consume --topic client-rust --min-expected-messages $NB_MESSAGES --timeout 60

log "Checking the consumer group client-rust-group (KIP-848 consumer protocol) committed all the offsets"
playground consumer-group describe --group client-rust-group
