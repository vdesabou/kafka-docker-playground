#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

# required to make utils.sh script being able to work, do not remove:
# ${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"

function wait_for_um () {
     MAX_WAIT=240
     CUR_WAIT=0
     log "⌛ Waiting up to $MAX_WAIT seconds for Universal Messaging to startup"
     docker container logs umserver > /tmp/out.txt 2>&1
     while ! grep "Scheduling shutdown in" /tmp/out.txt > /dev/null;
     do
          sleep 10
          docker container logs umserver > /tmp/out.txt 2>&1
          CUR_WAIT=$(( CUR_WAIT+10 ))
          if [[ "$CUR_WAIT" -gt "$MAX_WAIT" ]]; then
               echo -e "\nERROR: The logs in all connect containers do not show 'Scheduling shutdown in' after $MAX_WAIT seconds. Please troubleshoot with 'docker container ps' and 'docker container logs'.\n"
               exit 1
          fi
     done
     log "Universal Messaging Server is started!"
     sleep 30
}


docker-compose -f ../../environment/plaintext/docker-compose.yml -f "${PWD}/docker-compose.plaintext.yml" down -v --remove-orphans
log "Starting up SAG Universal Messaging container to get Client libraries"
docker-compose -f ../../environment/plaintext/docker-compose.yml -f "${PWD}/docker-compose.plaintext.yml" up -d umserver

wait_for_um
log "Universal Messaging Realm Server is up"
 
if [ ! -f nClient.jar ]
then
     docker cp umserver:/opt/softwareag/UniversalMessaging/lib/nClient.jar nClient.jar
fi
if [ ! -f nJMS.jar ]
then
     docker cp umserver:/opt/softwareag/UniversalMessaging/lib/nJMS.jar nJMS.jar
fi

docker-compose -f ../../environment/plaintext/docker-compose.yml -f "${PWD}/docker-compose.plaintext.yml" up -d

../../scripts/wait-for-connect-and-controlcenter.sh


log "Create Connection Factory"
docker exec umserver runUMTool.sh CreateConnectionFactory -rname=nsp://localhost:9000 -connectionurl=nsp://umserver:9000 -factoryname=QueueConnectionFactory -factorytype=queue

log "Create Queue"
docker exec umserver runUMTool.sh CreateJMSQueue -rname=nsp://localhost:9000 -queuename=test-queue

log "Sending messages to topic sink-messages"
seq 10 | docker exec -i broker kafka-console-producer --broker-list broker:9092 --topic sink-messages

log "Creating Solace source connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.confluent.connect.jms.JmsSinkConnector",
               "tasks.max": "1",
               "topics": "sink-messages",
               "java.naming.provider.url": "nsp://umserver:9000",
               "java.naming.factory.initial": "com.pcbsys.nirvana.nSpace.NirvanaContextFactory",
               "connection.factory.name": "QueueConnectionFactory",
               "java.naming.security.principal": "admin",
               "java.naming.security.credentials": "admin",
               "jms.destination.type": "queue",
               "jms.destination.name": "test-queue",
               "key.converter": "org.apache.kafka.connect.storage.StringConverter",
               "value.converter": "org.apache.kafka.connect.storage.StringConverter",
               "confluent.topic.bootstrap.servers": "broker:9092",
               "confluent.topic.replication.factor": "1"
          }' \
     http://localhost:8083/connectors/jms-sag-um-sink/config | jq .

sleep 10

log "Confirm the messages were delivered to the test-queue queue "
docker exec -i umserver timeout 30 runUMTool.sh JMSSubscribe -rname=nsp://localhost:9000 -connectionfactory=QueueConnectionFactory -destination=test-queue
