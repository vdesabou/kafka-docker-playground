#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if [ ! -f ${DIR}/jms-client/target/jms-client-1.0.0-SNAPSHOT.jar ]
then
     # build jms-client transform
     log "Build jms-client transform"
     docker run -i --rm -e TAG=$TAG_BASE -e KAFKA_CLIENT_TAG=$KAFKA_CLIENT_TAG -v "${DIR}/jms-client":/usr/src/mymaven -v "$HOME/.m2":/root/.m2 -v "${DIR}/jms-client/target:/usr/src/mymaven/target" -w /usr/src/mymaven maven:3.6.1-jdk-8 mvn package
fi

${DIR}/../../environment/sasl-ssl/start.sh "${PWD}/docker-compose.sasl-ssl.yml" -a -b

ZOOKEEPER_IP=$(container_to_ip zookeeper)

log "Blocking communication between jms-client and zookeeper"
block_host jms-client $ZOOKEEPER_IP

log "Sending messages to topic test-queue using JMS client"
docker exec -e BOOTSTRAP_SERVERS="broker:9092" -e USERNAME="client" -e PASSWORD="client-secret" -e CONFLUENT_LICENSE="put your license here" jms-client bash -c "java -jar jms-client-1.0.0-jar-with-dependencies.jar"

log "Removing network partition between jms-client and zookeeper"
remove_partition jms-client zookeeper
