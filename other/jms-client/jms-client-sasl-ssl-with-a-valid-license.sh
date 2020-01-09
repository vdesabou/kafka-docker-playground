#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

${DIR}/../../environment/sasl-ssl/start.sh "${PWD}/docker-compose.sasl-ssl.yml" -a -b

ZOOKEEPER_IP=$(container_to_ip zookeeper)

log "Blocking communication between jms-client and zookeeper"
block_host jms-client $ZOOKEEPER_IP

log "Sending messages to topic test-queue using JMS client"
docker exec -e BOOTSTRAP_SERVERS="broker:9091" -e USERNAME="client" -e PASSWORD="client-secret" -e CONFLUENT_LICENSE="put your license here" jms-client bash -c "java -jar jms-client-1.0.0-jar-with-dependencies.jar"

log "Removing network partition between jms-client and zookeeper"
remove_partition jms-client zookeeper
