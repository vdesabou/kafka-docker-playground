#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if test -z "$(docker images -q store/oracle/weblogic:12.2.1.3-dev-200127)"
then
     if [ ! -z "$CI" ]
     then
          # if this is github actions, pull the image
          docker pull store/oracle/weblogic:12.2.1.3-dev-200127
     else
          logerror "Image store/oracle/weblogic:12.2.1.3-dev-200127 is not present. You must pull it from https://hub.docker.com/_/oracle-weblogic-server-12c"
          exit 1
     fi
fi

# https://github.com/oracle/docker-images/tree/main/OracleWebLogic/samples/12212-domain-online-config
if test -z "$(docker images -q weblogic-jms:latest)"
then
     log "Building WebLogic JMS docker image..it can take a while..."
     OLDDIR=$PWD
     cd ${DIR}/docker-weblogic
     docker build --build-arg ADMIN_PASSWORD="welcome1" -t 1213-domain ./1213-domain
     docker build -t weblogic-jms:latest ./12212-domain-online-config -f ./12212-domain-online-config/Dockerfile
     cd ${OLDDIR}
fi

if [ ! -f ${DIR}/wlthint3client.jar ]
then
     docker run weblogic-jms:latest cat /u01/oracle/wlserver/server/lib/wlthint3client.jar > ${DIR}/wlthint3client.jar
fi

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"


log "Sending messages to topic sink-messages"
docker exec -i broker kafka-console-producer --broker-list broker:9092 --topic sink-messages << EOF
This is my message
EOF

log "Creating JMS weblogic sink connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.confluent.connect.jms.JmsSinkConnector",
               "topics": "sink-messages",
               "java.naming.factory.initial": "weblogic.jndi.WLInitialContextFactory",
               "java.naming.provider.url": "t3://weblogic-jms:7001",
               "java.naming.security.principal": "weblogic",
               "java.naming.security.credentials": "welcome1",
               "connection.factory.name": "myFactory",
               "jms.destination.name": "myJMSServer/mySystemModule!myJMSServer@MyDistributedQueue",
               "jms.destination.type": "queue",
               "key.converter": "org.apache.kafka.connect.storage.StringConverter",
               "value.converter": "org.apache.kafka.connect.storage.StringConverter",
               "confluent.license": "",
               "confluent.topic.bootstrap.servers": "broker:9092",
               "confluent.topic.replication.factor": "1"
          }' \
     http://localhost:8083/connectors/jms-weblogic-topic-sink/config | jq .
     
sleep 5

# FIXTHIS; need to be automated
log "Check the message has been received in destination queue, using console"
