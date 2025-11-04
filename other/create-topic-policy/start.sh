#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if [ ! -f ${DIR}/create-topic-policy/target/mytopicpolicy-1.0.0-SNAPSHOT.jar ]
then
     # build mytopicpolicy
     log "Build mytopicpolicy"
     docker run -i --rm -e TAG=$TAG_BASE -e KAFKA_CLIENT_TAG=$KAFKA_CLIENT_TAG -v "${DIR}/create-topic-policy":/usr/src/mymaven -v "$HOME/.m2":/root/.m2 -v "${DIR}/create-topic-policy/target:/usr/src/mymaven/target" -w /usr/src/mymaven maven:3.9.11-eclipse-temurin-11 mvn package
fi

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.yml"

wait_container_ready

set +e
log "Trying to create a topic with name that does not start with kafka-docker-playground, it should FAIL"
docker exec connect kafka-topics --create --topic mytopic --bootstrap-server broker:9092
set -e

log "Trying to create a topic with name that starts with kafka-docker-playground, it should WORK"
docker exec connect kafka-topics --create --topic kafka-docker-playground2 --bootstrap-server broker:9092