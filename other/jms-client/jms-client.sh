#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if version_gt $TAG_BASE "5.3.99"; then
    logwarn "WARN: zookeeper.connect is deprecated. Use JMS client with confluent.license parameter only."
    exit 111
fi

if [ ! -f ${DIR}/jms-client/target/jms-client-1.0.0-SNAPSHOT.jar ]
then
     # build jms-client transform
     log "Build jms-client transform"
     docker run -i --rm -e TAG=$TAG_BASE -e KAFKA_CLIENT_TAG=$KAFKA_CLIENT_TAG -v "${DIR}/jms-client":/usr/src/mymaven -v "$HOME/.m2":/root/.m2 -v "${DIR}/jms-client/target:/usr/src/mymaven/target" -w /usr/src/mymaven maven:3.6.1-jdk-8 mvn package
fi

# make sure control-center is not disabled
export ENABLE_CONTROL_CENTER=true

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.yml" -a -b


log "Sending messages to topic test-queue using JMS client"
docker exec -e BOOTSTRAP_SERVERS="broker:9092" -e ZOOKEEPER_CONNECT="zookeeper:2181" jms-client bash -c "java -jar jms-client-1.0.0-jar-with-dependencies.jar"