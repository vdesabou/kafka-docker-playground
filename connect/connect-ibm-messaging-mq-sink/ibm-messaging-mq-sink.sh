#!/bin/bash
set -e

# IBM's own open source MQ sink connector (https://github.com/ibm-messaging/kafka-connect-mq-sink)
# is not on Confluent Hub: get the jar from the GitHub release and package it as a Confluent Hub zip
if [ -z "$CONNECTOR_TAG" ]
then
    CONNECTOR_TAG=3.1.0
fi

if [ ! -z "$CONNECTOR_ZIP" ]
then
    # --connector-zip, for instance a locally built jar packaged like below
    :
elif [ ! -f ibm-messaging-kafka-connect-mq-sink-${CONNECTOR_TAG}.zip ]
then
    rm -rf /tmp/ibm-messaging-kafka-connect-mq-sink-${CONNECTOR_TAG}
    mkdir -p /tmp/ibm-messaging-kafka-connect-mq-sink-${CONNECTOR_TAG}/lib
    curl -L --fail -o /tmp/ibm-messaging-kafka-connect-mq-sink-${CONNECTOR_TAG}/lib/kafka-connect-mq-sink-${CONNECTOR_TAG}-jar-with-dependencies.jar https://github.com/ibm-messaging/kafka-connect-mq-sink/releases/download/v${CONNECTOR_TAG}/kafka-connect-mq-sink-${CONNECTOR_TAG}-jar-with-dependencies.jar
    cat > /tmp/ibm-messaging-kafka-connect-mq-sink-${CONNECTOR_TAG}/manifest.json << EOF
{
    "name": "kafka-connect-mq-sink",
    "version": "${CONNECTOR_TAG}",
    "title": "IBM MQ Sink Connector (ibm-messaging)",
    "description": "Kafka Connect sink connector for copying data from Apache Kafka into IBM MQ",
    "owner": {
        "username": "ibm-messaging",
        "name": "IBM Messaging"
    },
    "documentation_url": "https://github.com/ibm-messaging/kafka-connect-mq-sink",
    "component_types": ["sink"],
    "license": [
        {
            "name": "Apache License 2.0",
            "url": "https://www.apache.org/licenses/LICENSE-2.0"
        }
    ]
}
EOF
    (cd /tmp && zip -qr ibm-messaging-kafka-connect-mq-sink-${CONNECTOR_TAG}.zip ibm-messaging-kafka-connect-mq-sink-${CONNECTOR_TAG})
    mv /tmp/ibm-messaging-kafka-connect-mq-sink-${CONNECTOR_TAG}.zip .
fi

if [ -z "$CONNECTOR_ZIP" ]
then
    export CONNECTOR_ZIP=$PWD/ibm-messaging-kafka-connect-mq-sink-${CONNECTOR_TAG}.zip
fi
VERSION=$CONNECTOR_TAG
unset CONNECTOR_TAG

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if ! connect_cp_version_greater_than_8 && version_gt $VERSION "2.99.99"
then
    logwarn "IBM MQ sink connector ${VERSION} requires Java 17, it is only tested with CP 8+"
    exit 111
fi

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.yml"

log "Sending messages to topic sink-messages"
playground topic produce --topic sink-messages --nb-messages 3 << 'EOF'
This is my message
EOF

log "Creating IBM MQ sink connector (ibm-messaging version)"
playground connector create-or-update --connector ibm-messaging-mq-sink  << EOF
{
    "connector.class": "com.ibm.eventstreams.connect.mqsink.MQSinkConnector",
    "tasks.max": "1",
    "topics": "sink-messages",
    "mq.queue.manager": "QM1",
    "mq.connection.name.list": "ibmmq(1414)",
    "mq.channel.name": "DEV.APP.SVRCONN",
    "mq.user.name": "app",
    "mq.password": "passw0rd",
    "mq.queue": "DEV.QUEUE.1",
    "mq.message.builder": "com.ibm.eventstreams.connect.mqsink.builders.DefaultMessageBuilder",
    "key.converter": "org.apache.kafka.connect.storage.StringConverter",
    "value.converter": "org.apache.kafka.connect.storage.StringConverter"
}
EOF

log "Verify messages are received in DEV.QUEUE.1 queue"
MAX_WAIT=120
CUR_WAIT=0
nb_messages=0
while [ $nb_messages -lt 3 ]
do
    playground container exec --container ibmmq --command "bash -c \"/opt/mqm/samp/bin/amqsbcg DEV.QUEUE.1\"" > /tmp/result.log 2>&1 || true
    nb_messages=$(grep -c "Message descriptor" /tmp/result.log || true)
    sleep 10
    CUR_WAIT=$(( CUR_WAIT+10 ))
    if [[ "$CUR_WAIT" -gt "$MAX_WAIT" ]]
    then
        cat /tmp/result.log
        logerror "❗❗❗ Expected 3 messages in DEV.QUEUE.1 queue but got $nb_messages after $MAX_WAIT seconds"
        exit 1
    fi
done
cat /tmp/result.log
grep "This is my messa" /tmp/result.log
log "✅ $nb_messages messages received in DEV.QUEUE.1 queue"
