#!/bin/bash
set -e

# IBM's own open source MQ source connector (https://github.com/ibm-messaging/kafka-connect-mq-source)
# is not on Confluent Hub: get the jar from the GitHub release and package it as a Confluent Hub zip
if [ -z "$CONNECTOR_TAG" ]
then
    CONNECTOR_TAG=3.0.0
fi

if [ ! -z "$CONNECTOR_ZIP" ]
then
    # --connector-zip, for instance a locally built jar packaged like below
    :
elif [ ! -f ibm-messaging-kafka-connect-mq-source-${CONNECTOR_TAG}.zip ]
then
    rm -rf /tmp/ibm-messaging-kafka-connect-mq-source-${CONNECTOR_TAG}
    mkdir -p /tmp/ibm-messaging-kafka-connect-mq-source-${CONNECTOR_TAG}/lib
    curl -L --fail -o /tmp/ibm-messaging-kafka-connect-mq-source-${CONNECTOR_TAG}/lib/kafka-connect-mq-source-${CONNECTOR_TAG}-jar-with-dependencies.jar https://github.com/ibm-messaging/kafka-connect-mq-source/releases/download/v${CONNECTOR_TAG}/kafka-connect-mq-source-${CONNECTOR_TAG}-jar-with-dependencies.jar
    cat > /tmp/ibm-messaging-kafka-connect-mq-source-${CONNECTOR_TAG}/manifest.json << EOF
{
    "name": "kafka-connect-mq-source",
    "version": "${CONNECTOR_TAG}",
    "title": "IBM MQ Source Connector (ibm-messaging)",
    "description": "Kafka Connect source connector for copying data from IBM MQ into Apache Kafka",
    "owner": {
        "username": "ibm-messaging",
        "name": "IBM Messaging"
    },
    "documentation_url": "https://github.com/ibm-messaging/kafka-connect-mq-source",
    "component_types": ["source"],
    "license": [
        {
            "name": "Apache License 2.0",
            "url": "https://www.apache.org/licenses/LICENSE-2.0"
        }
    ]
}
EOF
    (cd /tmp && zip -qr ibm-messaging-kafka-connect-mq-source-${CONNECTOR_TAG}.zip ibm-messaging-kafka-connect-mq-source-${CONNECTOR_TAG})
    mv /tmp/ibm-messaging-kafka-connect-mq-source-${CONNECTOR_TAG}.zip .
fi

if [ -z "$CONNECTOR_ZIP" ]
then
    export CONNECTOR_ZIP=$PWD/ibm-messaging-kafka-connect-mq-source-${CONNECTOR_TAG}.zip
fi
VERSION=$CONNECTOR_TAG
unset CONNECTOR_TAG

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if ! connect_cp_version_greater_than_8 && version_gt $VERSION "2.99.99"
then
    logwarn "IBM MQ source connector ${VERSION} requires Java 17, it is only tested with CP 8+"
    exit 111
fi

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.yml"

log "Creating IBM MQ source connector (ibm-messaging version)"
playground connector create-or-update --connector ibm-messaging-mq-source  << EOF
{
    "connector.class": "com.ibm.eventstreams.connect.mqsource.MQSourceConnector",
    "tasks.max": "1",
    "topic": "MyKafkaTopicName",
    "mq.queue.manager": "QM1",
    "mq.connection.name.list": "ibmmq(1414)",
    "mq.channel.name": "DEV.APP.SVRCONN",
    "mq.user.name": "app",
    "mq.password": "passw0rd",
    "mq.queue": "DEV.QUEUE.1",
    "mq.record.builder": "com.ibm.eventstreams.connect.mqsource.builders.DefaultRecordBuilder",
    "mq.message.body.jms": "true",
    "key.converter": "org.apache.kafka.connect.storage.StringConverter",
    "value.converter": "org.apache.kafka.connect.storage.StringConverter"
}
EOF

sleep 5

log "Sending messages to DEV.QUEUE.1 queue"
playground container exec --container ibmmq --command "/opt/mqm/samp/bin/amqsput DEV.QUEUE.1" << EOF
Message 1
Message 2

EOF

log "Verify we have received the data in MyKafkaTopicName topic"
playground topic consume --topic MyKafkaTopicName --min-expected-messages 2 --timeout 60 --grep "Message 2"
