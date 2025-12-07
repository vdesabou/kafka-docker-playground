#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if connect_cp_version_greater_than_8 && [ ! -z "$CONNECTOR_TAG" ] && ! version_gt $CONNECTOR_TAG "2.1.15"
then
     logwarn "minimal supported connector version is 2.1.16 for CP 8.0"
     logwarn "see https://docs.confluent.io/platform/current/connect/supported-connector-version-8.1.html#supported-connector-versions-in-cp-8-1"
     exit 111
fi

if test -z "$(docker images -q container-registry.oracle.com/middleware/weblogic:12.2.1.3)"
then
     if [ ! -z "$ORACLE_CONTAINER_REGISTRY_USERNAME" ] && [ ! -z "$ORACLE_CONTAINER_REGISTRY_PASSWORD" ]
     then
          docker login container-registry.oracle.com -u $ORACLE_CONTAINER_REGISTRY_USERNAME -p "$ORACLE_CONTAINER_REGISTRY_PASSWORD"
          docker pull container-registry.oracle.com/middleware/weblogic:12.2.1.3
     else
          logerror "Image container-registry.oracle.com/middleware/weblogic:12.2.1.3 is not present. You must pull it from https://container-registry.oracle.com"
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
     set +e
     log "🏗 Building jar for ${component}"
     docker run -i --rm -e KAFKA_CLIENT_TAG=$KAFKA_CLIENT_TAG -e TAG=$TAG_BASE -v "${PWD}/${component}":/usr/src/mymaven -v "$HOME/.m2":/root/.m2 -v "$PWD/../../scripts/settings.xml:/tmp/settings.xml" -v "${PWD}/${component}/target:/usr/src/mymaven/target" -w /usr/src/mymaven maven:3.9.11-eclipse-temurin-11 mvn -s /tmp/settings.xml -Dkafka.tag=$TAG -Dkafka.client.tag=$KAFKA_CLIENT_TAG package > /tmp/result.log 2>&1
     if [ $? != 0 ]
     then
          logerror "❌ failed to build java component $component"
          tail -500 /tmp/result.log
          exit 1
     fi
     set -e
done


cd ../../connect/connect-jms-weblogic-sink

# Copy JAR files to confluent-hub
mkdir -p ../../confluent-hub/confluentinc-kafka-connect-jms-sink/lib/
cp ../../connect/connect-jms-weblogic-sink/jms-receiver/lib/wlthint3client.jar ../../confluent-hub/confluentinc-kafka-connect-jms-sink/lib/wlthint3client.jar
cd -
PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.yml"


log "Sending messages to topic sink-messages"
playground topic produce --topic sink-messages --nb-messages 1 << 'EOF'
This is my message
EOF

log "Creating JMS weblogic sink connector"
playground connector create-or-update --connector weblogic-topic-sink  << EOF
{
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
}
EOF
     
sleep 5

log "Check the message has been received in destination queue"
timeout 60 docker exec jms-receiver bash -c 'java -cp "/tmp/weblogic.jar:/tmp/wlthint3client.jar:/jms-receiver-1.0.0.jar" com.sample.jms.toolkit.JMSReceiver'
