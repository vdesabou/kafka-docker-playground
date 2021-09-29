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

if [ ! -f ${DIR}/jms-receiver/lib/wlthint3client.jar ]
then
     docker run weblogic-jms:latest cat /u01/oracle/wlserver/server/lib/wlthint3client.jar > ${DIR}/jms-receiver/lib/wlthint3client.jar
fi

if [ ! -f ${DIR}/jms-receiver/lib/weblogic.jar ]
then
     docker run weblogic-jms:latest cat /u01/oracle/wlserver/server/lib/weblogic.jar > ${DIR}/jms-receiver/lib/weblogic.jar
fi

for component in jms-receiver
do
     if [ ! -f ${DIR}/${component}/target/${component}-1.0.0.jar ]
     then
          log "Building jar for ${component}"
          docker run -i --rm -e KAFKA_CLIENT_TAG=$KAFKA_CLIENT_TAG -e TAG=$TAG_BASE -v "${DIR}/${component}":/usr/src/mymaven -v "$HOME/.m2":/root/.m2 -v "${DIR}/${component}/target:/usr/src/mymaven/target" -w /usr/src/mymaven maven:3.6.1-jdk-8 mvn package
     fi
done

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

log "Check the message has been received in destination queue"
timeout 60 docker exec jms-receiver bash -c 'java -cp "/tmp/weblogic.jar:/tmp/wlthint3client.jar:/jms-receiver-1.0.0.jar" com.sample.jms.toolkit.JMSReceiver'
