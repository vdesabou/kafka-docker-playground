#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if [ ! -f ${DIR}/create-topic-policy/target/mytopicpolicy-1.0.0-SNAPSHOT.jar ]
then
     # build mytopicpolicy
     log "Build mytopicpolicy"
     build_java_component_with_retry "create-topic-policy" docker run -i --rm -e TAG=$TAG_BASE -e KAFKA_CLIENT_TAG=$KAFKA_CLIENT_TAG -v "${DIR}/create-topic-policy":/usr/src/mymaven -v "$HOME/.m2":/root/.m2 -v "${DIR}/../../scripts/settings.xml:/tmp/settings.xml" -v "${DIR}/create-topic-policy/target:/usr/src/mymaven/target" -w /usr/src/mymaven maven:3.9.11-eclipse-temurin-11 mvn -s /tmp/settings.xml package
fi

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
if version_gt $TAG_BASE "7.9.99" || [ -n "$ENABLE_KRAFT" ]
then
    log "📝 KRaft: the create topic policy is configured on the controller (docker-compose.plaintext.kraft.yml)"
    DOCKER_COMPOSE_OVERRIDE_FILE="${PWD}/docker-compose.plaintext.kraft.yml"
else
    log "📝 ZooKeeper: the create topic policy is configured on the broker (docker-compose.plaintext.yml)"
    DOCKER_COMPOSE_OVERRIDE_FILE="${PWD}/docker-compose.plaintext.yml"
fi
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${DOCKER_COMPOSE_OVERRIDE_FILE}"

wait_container_ready

log "Trying to create a topic with name that does not start with kafka-docker-playground, it should FAIL"
set +e
playground topic create --topic mytopic
rc=$?
set -e
if [ $rc -eq 0 ]
then
    logerror "❌ topic mytopic should have been refused by the create topic policy"
    exit 1
fi
log "✅ topic mytopic refused by the create topic policy, as expected"

log "Trying to create a topic with name that starts with kafka-docker-playground, it should WORK"
playground topic create --topic kafka-docker-playground2