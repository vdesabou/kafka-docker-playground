#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if connect_cp_version_greater_than_8 && [ ! -z "$CONNECTOR_TAG" ] && ! version_gt $CONNECTOR_TAG "2.1.15"
then
     logwarn "minimal supported connector version is 2.1.16 for CP 8.0"
     logwarn "see https://docs.confluent.io/platform/8.0/connect/supported-connector-version.html#"
     exit 111
fi

function wait_for_solace () {
     MAX_WAIT=240
     log "⌛ Waiting up to $MAX_WAIT seconds for Solace to startup"
     # Use playground logs so readiness wait works for both Docker and CFK environments.
     playground container logs --container solace --wait-for-log "Starting solace process" --max-wait "$MAX_WAIT"
     playground container logs --container solace --wait-for-log "Launching solacedaemon" --max-wait "$MAX_WAIT"
     log "Solace is started!"
     sleep 30
}

cd ../../connect/connect-solace-sink
if [ ! -f ${DIR}/sol-jms-10.6.4.jar ]
then
     log "Downloading sol-jms-10.6.4.jar"
     wget -q https://repo1.maven.org/maven2/com/solacesystems/sol-jms/10.6.4/sol-jms-10.6.4.jar
fi
cd -


cd ../../connect/connect-solace-sink

# Copy JAR files to confluent-hub
mkdir -p ../../confluent-hub/confluentinc-kafka-connect-solace-sink/lib/
cp ../../connect/connect-solace-sink/sol-jms-10.6.4.jar ../../confluent-hub/confluentinc-kafka-connect-solace-sink/lib/sol-jms-10.6.4.jar
cd -
PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.yml"

wait_for_solace
log "Solace UI is accessible at http://127.0.0.1:8080 (admin/admin)"

log "Sending messages to topic sink-messages"
playground topic produce -t sink-messages --nb-messages 10 << 'EOF'
%g
EOF

log "Creating Solace sink connector"
playground connector create-or-update --connector solace-sink  << EOF
{
     "connector.class": "io.confluent.connect.jms.SolaceSinkConnector",
     "tasks.max": "1",
     "topics": "sink-messages",
     "solace.host": "smf://solace:55555",
     "solace.username": "admin",
     "solace.password": "admin",
     "solace.dynamic.durables": "true",
     "jms.destination.type": "queue",
     "jms.destination.name": "connector-quickstart",
     "key.converter": "org.apache.kafka.connect.storage.StringConverter",
     "value.converter": "org.apache.kafka.connect.storage.StringConverter",
     "confluent.topic.bootstrap.servers": "broker:9092",
     "confluent.topic.replication.factor": "1"
}
EOF

sleep 30

log "Confirm the messages were delivered to the connector-quickstart queue in the default Message VPN using CLI"
playground container exec --container solace --command "bash -c \"/usr/sw/loads/currentload/bin/cli -A -s cliscripts/show_queue_cmd\"" > /tmp/result.log  2>&1
cat /tmp/result.log
grep "10       0.00" /tmp/result.log
