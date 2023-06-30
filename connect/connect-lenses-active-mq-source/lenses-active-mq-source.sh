#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if [ ! -f ${DIR}/activemq-all-5.15.4.jar ]
then
     log "Downloading activemq-all-5.15.4.jar"
     wget https://repo1.maven.org/maven2/org/apache/activemq/activemq-all/5.15.4/activemq-all-5.15.4.jar
fi

if [ -z "$CONNECTOR_TAG" ]
then
    CONNECTOR_TAG=1.2.3
fi

if [ ! -f $PWD/kafka-connect-jms-${CONNECTOR_TAG}-2.1.0-all.jar ]
then
    curl -L -o kafka-connect-jms-${CONNECTOR_TAG}-2.1.0-all.tar.gz https://github.com/lensesio/stream-reactor/releases/download/${CONNECTOR_TAG}/kafka-connect-jms-${CONNECTOR_TAG}-2.1.0-all.tar.gz
    tar xvfz kafka-connect-jms-${CONNECTOR_TAG}-2.1.0-all.tar.gz
fi

export VERSION=$CONNECTOR_TAG
unset CONNECTOR_TAG

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"


log "Creating Lenses JMS ActiveMQ source connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data @lenses-active-mq-source.json \
     http://localhost:8083/connectors/lenses-active-mq-source/config | jq .

sleep 5

log "Sending messages to myqueue JMS queue:"
curl -XPOST -u admin:admin -d 'body={"u_name": "scissors", "u_price": 2.75, "u_quantity": 3}' http://localhost:8161/api/message/jms-queue?type=queue

sleep 5

log "Verify we have received the data in MyKafkaTopicName topic"
playground topic consume --topic MyKafkaTopicName --min-expected-messages 1 --timeout 60
