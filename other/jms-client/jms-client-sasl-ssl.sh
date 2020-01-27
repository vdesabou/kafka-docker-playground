#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if [ ! -f ${DIR}/jms-client/target/jms-client-1.0.0-SNAPSHOT.jar ]
then
     # build jms-client transform
     log "Build jms-client transform"
     docker run -it --rm -e KAFKA_CLIENT_TAG=$KAFKA_CLIENT_TAG -v "${DIR}/jms-client":/usr/src/mymaven -v "$HOME/.m2":/root/.m2 -v "${DIR}/jms-client/target:/usr/src/mymaven/target" -w /usr/src/mymaven maven:3.6.1-jdk-8 mvn package
fi

${DIR}/../../environment/sasl-ssl/start.sh "${PWD}/docker-compose.sasl-ssl.yml" -a -b

log "Sending messages to topic test-queue using JMS client"
docker exec -e BOOTSTRAP_SERVERS="broker:9092" -e ZOOKEEPER_CONNECT="zookeeper:2181" -e USERNAME="client" -e PASSWORD="client-secret" jms-client bash -c "java -jar jms-client-1.0.0-jar-with-dependencies.jar"