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

cd ../../connect/connect-ibm-mq-source
get_3rdparty_file "IBM-MQ-Install-Java-All.jar"

if [ ! -f ${PWD}/IBM-MQ-Install-Java-All.jar ]
then
     # not running with github actions
     logerror "❌ ${PWD}/IBM-MQ-Install-Java-All.jar is missing. It must be downloaded manually in order to acknowledge user agreement"
     exit 1
fi

if [ ! -f ${PWD}/com.ibm.mq.allclient.jar ]
then
     # install deps
     log "Getting com.ibm.mq.allclient.jar and jms.jar from IBM-MQ-Install-Java-All.jar"
     if [[ "$OSTYPE" == "darwin"* ]]
     then
          # workaround for issue on linux, see https://github.com/vdesabou/kafka-docker-playground/issues/851#issuecomment-821151962
          rm -rf ${PWD}/install/
     else
          sudo rm -rf ${PWD}/install/
     fi
     docker run --quiet --rm -v ${PWD}/IBM-MQ-Install-Java-All.jar:/tmp/IBM-MQ-Install-Java-All.jar -v ${PWD}/install:/tmp/install eclipse-temurin:8 java -jar /tmp/IBM-MQ-Install-Java-All.jar --acceptLicense /tmp/install
     cp ${PWD}/install/wmq/JavaSE/lib/jms.jar ${PWD}/
     cp ${PWD}/install/wmq/JavaSE/lib/com.ibm.mq.allclient.jar ${PWD}/
fi
cd -


cd ../../connect/connect-ibm-mq-source

# Copy JAR files to confluent-hub
mkdir -p ../../confluent-hub/confluentinc-kafka-connect-ibmmq/lib/
cp ../../connect/connect-ibm-mq-source/com.ibm.mq.allclient.jar ../../confluent-hub/confluentinc-kafka-connect-ibmmq/lib/com.ibm.mq.allclient.jar
cp ../../connect/connect-ibm-mq-source/jms.jar ../../confluent-hub/confluentinc-kafka-connect-ibmmq/lib/jms.jar
cp ../../connect/connect-ibm-mq-source/com.ibm.mq.allclient.jar ../../confluent-hub/confluentinc-kafka-connect-ibmmq/lib/com.ibm.mq.allclient.jar
cp ../../connect/connect-ibm-mq-source/jms.jar ../../confluent-hub/confluentinc-kafka-connect-ibmmq/lib/jms.jar
cp ../../connect/connect-ibm-mq-source/com.ibm.mq.allclient.jar ../../confluent-hub/confluentinc-kafka-connect-ibmmq/lib/com.ibm.mq.allclient.jar
cp ../../connect/connect-ibm-mq-source/jms.jar ../../confluent-hub/confluentinc-kafka-connect-ibmmq/lib/jms.jar
cp ../../connect/connect-ibm-mq-source/com.ibm.mq.allclient.jar ../../confluent-hub/confluentinc-kafka-connect-ibmmq/lib/com.ibm.mq.allclient.jar
cp ../../connect/connect-ibm-mq-source/jms.jar ../../confluent-hub/confluentinc-kafka-connect-ibmmq/lib/jms.jar
cd -
PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.yml"


log "Creating IBM MQ source connector"
playground connector create-or-update --connector ibm-mq-source  << EOF
{
     "connector.class": "io.confluent.connect.ibm.mq.IbmMQSourceConnector",
     "kafka.topic": "MyKafkaTopicName",
     "mq.hostname": "ibmmq",
     "mq.port": "1414",
     "mq.transport.type": "client",
     "mq.queue.manager": "QM1",
     "mq.channel": "DEV.APP.SVRCONN",
     "mq.username": "app",
     "mq.password": "passw0rd",
     "max.retry.time": "10000",
     "jms.destination.name": "DEV.QUEUE.1",
     "jms.destination.type": "queue",
     "confluent.license": "",
     "confluent.topic.bootstrap.servers": "broker:9092",
     "confluent.topic.replication.factor": "1"
}
EOF

sleep 5

log "Sending messages to DEV.QUEUE.1 JMS queue:"
docker exec -i ibmmq /opt/mqm/samp/bin/amqsput DEV.QUEUE.1 << EOF
Message 1
Message 1
EOF

sleep 5

log "Verify we have received the data in MyKafkaTopicName topic"
playground topic consume --topic MyKafkaTopicName --min-expected-messages 2 --timeout 60
