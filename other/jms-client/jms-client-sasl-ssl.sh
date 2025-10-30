#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if version_gt $TAG_BASE "5.3.99"; then
    logwarn "zookeeper.connect is deprecated. Use JMS client with confluent.license parameter only."
    exit 111
fi

if [ ! -f ${DIR}/jms-client/target/jms-client-1.0.0-SNAPSHOT.jar ]
then
     # build jms-client transform
     log "Build jms-client transform"
     docker run -i --rm -e TAG=$TAG_BASE -e KAFKA_CLIENT_TAG=$KAFKA_CLIENT_TAG -v "${DIR}/jms-client":/usr/src/mymaven -v "$HOME/.m2":/root/.m2 -v "${DIR}/jms-client/target:/usr/src/mymaven/target" -w /usr/src/mymaven maven:3.9.1-eclipse-temurin-11 mvn package
fi

# make sure control-center is not disabled
export ENABLE_CONTROL_CENTER=true

playground start-environment --environment sasl-ssl --docker-compose-override-file "${PWD}/docker-compose.sasl-ssl.yml" --wait-for-control-center

log "Sending messages to topic test-queue using JMS client"
docker exec -e BOOTSTRAP_SERVERS="broker:9092" -e ZOOKEEPER_CONNECT="zookeeper:2181" -e USERNAME="client" -e PASSWORD="client-secret" jms-client bash -c "java -jar jms-client-1.0.0-jar-with-dependencies.jar"