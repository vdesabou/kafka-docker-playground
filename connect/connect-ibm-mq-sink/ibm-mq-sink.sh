#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if [ ! -z "$TAG_BASE" ] && version_gt $TAG_BASE "7.9.99" && [ ! -z "$CONNECTOR_TAG" ] && ! version_gt $CONNECTOR_TAG "2.1.15"
then
     logwarn "minimal supported connector version is 2.1.16 for CP 8.0"
     logwarn "see https://docs.confluent.io/platform/current/connect/supported-connector-version-8.0.html#supported-connector-versions-in-cp-8-0"
     exit 111
fi

cd ../../connect/connect-ibm-mq-sink
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
     docker run --quiet --rm -v ${PWD}/IBM-MQ-Install-Java-All.jar:/tmp/IBM-MQ-Install-Java-All.jar -v ${PWD}/install:/tmp/install openjdk:8 java -jar /tmp/IBM-MQ-Install-Java-All.jar --acceptLicense /tmp/install
     cp ${PWD}/install/wmq/JavaSE/lib/jms.jar ${PWD}/
     cp ${PWD}/install/wmq/JavaSE/lib/com.ibm.mq.allclient.jar ${PWD}/
fi
cd -
PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.yml"

log "Sending messages to topic sink-messages"
playground topic produce --topic sink-messages --nb-messages 1 << 'EOF'
This is my message
EOF

log "Creating IBM MQ source connector"
playground connector create-or-update --connector ibm-mq-sink  << EOF
{
     "connector.class": "io.confluent.connect.jms.IbmMqSinkConnector",
     "topics": "sink-messages",
     "mq.hostname": "ibmmq",
     "mq.port": "1414",
     "mq.transport.type": "client",
     "mq.queue.manager": "QM1",
     "mq.channel": "DEV.APP.SVRCONN",
     "mq.username": "app",
     "mq.password": "passw0rd",
     "jms.destination.name": "DEV.QUEUE.1",
     "jms.destination.type": "queue",
     "value.converter": "org.apache.kafka.connect.storage.StringConverter",
     "key.converter": "org.apache.kafka.connect.storage.StringConverter",
     "confluent.license": "",
     "confluent.topic.bootstrap.servers": "broker:9092",
     "confluent.topic.replication.factor": "1"
}
EOF

sleep 10

log "Verify message received in DEV.QUEUE.1 queue"
docker exec ibmmq bash -c "/opt/mqm/samp/bin/amqsbcg DEV.QUEUE.1" > /tmp/result.log  2>&1
cat /tmp/result.log
grep "my message" /tmp/result.log

