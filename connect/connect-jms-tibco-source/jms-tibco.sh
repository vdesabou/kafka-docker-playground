#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if connect_cp_version_greater_than_8 && [ ! -z "$CONNECTOR_TAG" ] && ! version_gt $CONNECTOR_TAG "12.1.99"
then
     logwarn "minimal supported connector version is 12.2.0 for CP 8.0"
     logwarn "see https://docs.confluent.io/platform/current/connect/supported-connector-version-8.1.html#supported-connector-versions-in-cp-8-1"
     exit 111
fi

# Need to create the TIBCO EMS image using https://github.com/mikeschippers/docker-tibco
cd ../../connect/connect-jms-tibco-source/docker-tibco/
get_3rdparty_file "TIB_ems-ce_8.5.1_linux_x86_64.zip"
cd -
if [ ! -f ../../connect/connect-jms-tibco-source/docker-tibco/TIB_ems-ce_8.5.1_linux_x86_64.zip ]
then
     logerror "❌ ../../connect/connect-jms-tibco-source/docker-tibco/ does not contain TIBCO EMS zip file TIB_ems-ce_8.5.1_linux_x86_64.zip"
     exit 1
fi

if [ ! -f ../../connect/connect-jms-tibco-source/tibjms.jar ] || [ ! -f ../../connect/connect-jms-tibco-source/jms-2.0.jar ]
then
    log "../../connect/connect-jms-tibco-source/tibjms.jar or jms-2.0.jar missing, will get them from ../../connect/connect-jms-tibco-source/docker-tibco/TIB_ems-ce_8.5.1_linux_x86_64.zip"
    rm -rf /tmp/TIB_ems-ce_8.5.1
    unzip ../../connect/connect-jms-tibco-source/docker-tibco/TIB_ems-ce_8.5.1_linux_x86_64.zip -d /tmp/
    tar xvfz /tmp/TIB_ems-ce_8.5.1/tar/TIB_ems-ce_8.5.1_linux_x86_64-java_client.tar.gz opt/tibco/ems/8.5/lib/tibjms.jar
    tar xvfz /tmp/TIB_ems-ce_8.5.1/tar/TIB_ems-ce_8.5.1_linux_x86_64-java_client.tar.gz opt/tibco/ems/8.5/lib/jms-2.0.jar
    cp opt/tibco/ems/8.5/lib/tibjms.jar ../../connect/connect-jms-tibco-source/
    cp opt/tibco/ems/8.5/lib/jms-2.0.jar ../../connect/connect-jms-tibco-source/
    rm -rf opt
fi

if test -z "$(docker images -q tibems:latest)"
then
     log "Building TIBCO EMS docker image..it can take a while..."
     OLDDIR=$PWD
     cd ../../connect/connect-jms-tibco-source/docker-tibco
     docker build -t tibbase:1.0.0 ./tibbase
     docker build -t tibems:latest . -f ./tibems/Dockerfile
     cd ${OLDDIR}
fi


cd ../../connect/connect-jms-tibco-source

# Copy JAR files to confluent-hub
mkdir -p ../../confluent-hub/confluentinc-kafka-connect-jms/lib/
cp ../../connect/connect-jms-tibco-source/tibjms.jar ../../confluent-hub/confluentinc-kafka-connect-jms/lib/tibjms.jar
cp ../../connect/connect-jms-tibco-source/jms-2.0.jar ../../confluent-hub/confluentinc-kafka-connect-jms/lib/jms-2.0.jar
cd -
PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.yml"

log "Sending EMS messages m1 m2 m3 m4 m5 in queue connector-quickstart"
docker exec tibco-ems bash -c '
cd /opt/tibco/ems/8.5/samples/java
export TIBEMS_JAVA=/opt/tibco/ems/8.5/lib
CLASSPATH=${TIBEMS_JAVA}/jms-2.0.jar:${CLASSPATH}
CLASSPATH=.:${TIBEMS_JAVA}/tibjms.jar:${TIBEMS_JAVA}/tibjmsadmin.jar:${CLASSPATH}
export CLASSPATH
javac *.java
java tibjmsMsgProducer -user admin -queue connector-quickstart m1 m2 m3 m4 m5'


log "Creating JMS TIBCO source connector"
playground connector create-or-update --connector jms-tibco-source  << EOF
{
     "connector.class": "io.confluent.connect.jms.JmsSourceConnector",
     "tasks.max": "1",
     "kafka.topic": "from-tibco-messages",
     "java.naming.factory.initial": "com.tibco.tibjms.naming.TibjmsInitialContextFactory",
     "java.naming.provider.url": "tibjmsnaming://tibco-ems:7222",
     "jms.destination.type": "queue",
     "jms.destination.name": "connector-quickstart",
     "key.converter": "org.apache.kafka.connect.storage.StringConverter",
     "value.converter": "org.apache.kafka.connect.storage.StringConverter",
     "confluent.license": "",
     "confluent.topic.bootstrap.servers": "broker:9092",
     "confluent.topic.replication.factor": "1"
}
EOF

sleep 5

log "Verify we have received the data in from-tibco-messages topic"
playground topic consume --topic from-tibco-messages --min-expected-messages 2 --timeout 60

sleep 5

log "Asserting that TIBCO EMS queue connector-quickstart is empty after connector processing"
log "This tests that commitRecord API properly deletes messages from external system"

# Try to consume one message with a short timeout - if queue is empty, consumer will timeout
set +e
CONSUMER_OUTPUT=$(docker exec tibco-ems bash -c '
cd /opt/tibco/ems/8.5/samples/java
export TIBEMS_JAVA=/opt/tibco/ems/8.5/lib
CLASSPATH=${TIBEMS_JAVA}/jms-2.0.jar:${CLASSPATH}
CLASSPATH=.:${TIBEMS_JAVA}/tibjms.jar:${TIBEMS_JAVA}/tibjmsadmin.jar:${CLASSPATH}
export CLASSPATH
timeout 5 java tibjmsMsgConsumer -user admin -queue connector-quickstart 2>&1 || true
')
set -e

# Check if any messages were consumed
if echo "$CONSUMER_OUTPUT" | grep -q "Received [0-9]* messages"; then
    QUEUE_SIZE=$(echo "$CONSUMER_OUTPUT" | grep -o "Received [0-9]* messages" | grep -o "[0-9]*")
    logerror "❌ FAILURE: Messages still remain in TIBCO EMS queue connector-quickstart (consumed: $QUEUE_SIZE) - messages were not deleted"
    log "Consumer output:"
    echo "$CONSUMER_OUTPUT"
    exit 1
else
    log "✅ SUCCESS: TIBCO EMS queue connector-quickstart is empty - messages were successfully consumed and deleted"
fi
