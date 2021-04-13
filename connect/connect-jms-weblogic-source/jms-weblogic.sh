#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if test -z "$(docker images -q store/oracle/weblogic:12.2.1.3-dev-200127)"
then
     logerror "Image store/oracle/weblogic:12.2.1.3-dev-200127 is not present. You must pull it from https://hub.docker.com/_/oracle-weblogic-server-12c"
     exit 1
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
     log "${DIR}/wlthint3client.jar missing, will get it from weblogic-jms:latest image"
     docker run weblogic-jms:latest cat /u01/oracle/wlserver/server/lib/wlthint3client.jar > ${DIR}/wlthint3client.jar
     docker run weblogic-jms:latest cat /u01/oracle/wlserver/server/lib/wlthint3client.jar > ${DIR}/jms-sender/lib/wlthint3client.jar
fi

if [ ! -f ${DIR}/weblogic.jar ]
then
     log "${DIR}/weblogic.jar missing, will get it from weblogic-jms:latest image"
     docker run weblogic-jms:latest cat /u01/oracle/wlserver/server/lib/weblogic.jar > ${DIR}/jms-sender/lib/weblogic.jar
fi

for component in jms-sender
do
     if [ ! -f ${DIR}/${component}/target/${component}-1.0.0-jar.jar ]
     then
          log "Building jar for ${component}"
          docker run -i --rm -e KAFKA_CLIENT_TAG=$KAFKA_CLIENT_TAG -e TAG=$TAG_BASE -v "${DIR}/${component}":/usr/src/mymaven -v "$HOME/.m2":/root/.m2 -v "${DIR}/${component}/target:/usr/src/mymaven/target" -w /usr/src/mymaven maven:3.6.1-jdk-11 mvn package
     fi
done

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"

docker exec jms-sender bash -c 'java -cp "/tmp/weblogic.jar:/tmp/wlthint3client.jar:/jms-sender-0.0.1-SNAPSHOT.jar" com.sample.jms.toolkit.JMSSender'

log "Creating JMS weblogic source connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.confluent.connect.weblogic.WeblogicSourceConnector",
               "kafka.topic":"from-weblogic-messages",
               "java.naming.factory.initial": "weblogic.jndi.WLInitialContextFactory",
               "jms.destination.name":"myQueue",
               "jms.destination.type":"queue",
               "java.naming.provider.url": "t3://weblogic-jms:7001/",
               "connection.factory.name": "weblogic.jms.ConnectionFactory",
               "java.naming.security.principal": "weblogic",
               "java.naming.security.credentials": "welcome1",
               "tasks.max" : "1",
               "jms.client.id": "id1",
               "confluent.license": "",
               "confluent.topic.bootstrap.servers": "broker:9092",
               "confluent.topic.replication.factor": "1"
          }' \
     http://localhost:8083/connectors/jms-weblogic-source/config | jq .

sleep 5

log "Verify we have received the data in from-weblogic-messages topic"
timeout 60 docker exec connect kafka-console-consumer -bootstrap-server broker:9092 --topic from-weblogic-messages --from-beginning --max-messages 2
