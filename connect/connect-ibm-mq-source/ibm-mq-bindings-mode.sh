#!/bin/bash

set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

log "🔔 This example is using bindings mode, which means that the connector is running in the same container as IBM MQ, and is using local connection to connect to it"
logwarn "🔔 CP version is hardcoded to 8.1.0 and connnector version is hardcoded to 13.0.5 in the Dockerfile, if you want to use different versions, you will need to build your own image and update the docker-compose file accordingly"

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

# make sure control-center is not disabled
export ENABLE_CONTROL_CENTER=true

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.bindings-mode.yml" --wait-for-control-center

sleep 10

function wait_for_connect_to_start () {
     MAX_WAIT=150
     CUR_WAIT=0
     sleep 5
     set +e
     log "⌛ Waiting up to $MAX_WAIT seconds for connect to start"
     while [[ ! $(cat /tmp/out.txt) =~ "Finished starting connectors and tasks" ]]
     do
          sleep 10
          CUR_WAIT=$(( CUR_WAIT+10 ))
          if [[ "$CUR_WAIT" -gt "$MAX_WAIT" ]]; then
               echo -e "\nERROR: The logs still show 'Finished starting connectors and tasks' after $MAX_WAIT seconds.\n"
               cat /tmp/out.txt
               exit 1
          fi
     done
     log "connect is ready !"
     set -e
}

log "Run connect worker manually"
docker exec connect bash -c "KAFKA_OPTS='-Dcom.ibm.mq.jmqi.threadWaitTimeout=1 -Djava.library.path=/opt/mqm/java/lib64' /mnt/confluent/bin/connect-distributed /mnt/confluent/config/connect-distributed.properties" > /tmp/out.txt 2>&1 &

wait_for_connect_to_start

log "Creating IBM MQ source connector with bindings mode (mq.transport.type=bindings)"
playground connector create-or-update --connector ibm-mq-source-bindings << EOF
{
    "connector.class": "io.confluent.connect.ibm.mq.IbmMQSourceConnector",
    "kafka.topic": "MyKafkaTopicName",
    "mq.hostname": "localhost",
    "mq.port": "1414",
    "mq.transport.type": "bindings",
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
docker exec -i connect /opt/mqm/samp/bin/amqsput DEV.QUEUE.1 << EOF
Message 1
Message 1
EOF

sleep 5

log "Verify we have received the data in MyKafkaTopicName topic"
set +e
# it fails as cp is installed manually on ibm mq base image..
# but records should be in the topic anyway
playground topic consume --topic MyKafkaTopicName --min-expected-messages 2 --timeout 60
# 16:40:49 ℹ️ ✨ Display content of topic MyKafkaTopicName, it contains 2 messages
# 16:40:49 ℹ️ 🔮🙅 topic is not using any schema for key
# 16:40:49 ℹ️ 🔮🙅 topic is not using any schema for value
# OCI runtime exec failed: exec failed: unable to start container process: exec: "kafka-console-consumer": executable file not found in $PATH