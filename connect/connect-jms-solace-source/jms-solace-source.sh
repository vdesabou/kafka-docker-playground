#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if connect_cp_version_greater_than_8 && [ ! -z "$CONNECTOR_TAG" ] && ! version_gt $CONNECTOR_TAG "12.1.99"
then
     logwarn "minimal supported connector version is 12.2.0 for CP 8.0"
     logwarn "see https://docs.confluent.io/platform/8.0/connect/supported-connector-version.html#"
     exit 111
fi

function wait_for_solace () {
     MAX_WAIT=600
     log "⌛ Waiting up to $MAX_WAIT seconds for Solace to startup"
     # Use playground logs so readiness wait works for both Docker and CFK environments.
     playground container logs --container solace --wait-for-log "Running pre-startup checks" --max-wait "$MAX_WAIT"
     log "Solace is started!"
     sleep 30
}

function run_solace_cli_script_with_retry () {
     local script_name="$1"
     local description="$2"
     local output_file="${3:-/tmp/solace-cli-${script_name}.log}"
     local max_wait=300
     local cur_wait=0

     log "⌛ Waiting up to $max_wait seconds for Solace CLI to be ready for ${description}"
     while true
     do
          set +e
          playground container exec --container solace --command "bash -c \"/usr/sw/loads/currentload/bin/cli -A -s cliscripts/${script_name}\"" > "$output_file" 2>&1
          ret=$?
          set -e

          if [ $ret -eq 0 ]
          then
               log "Solace CLI is ready for ${description}"
               return
          fi

          sleep 10
          cur_wait=$((cur_wait + 10))
          if (( cur_wait % 60 == 0 ))
          then
               logwarn "Solace CLI not ready yet for ${description}, retrying... (${cur_wait}/${max_wait}s)"
          fi
          if [[ "$cur_wait" -gt "$max_wait" ]]
          then
               logerror "Solace CLI is not ready for ${description} after ${max_wait} seconds"
               cat "$output_file"
               exit 1
          fi
     done
}

if [ ! -f ${DIR}/sol-jms-10.6.4.jar ]
then
     log "Downloading sol-jms-10.6.4.jar"
     wget -q https://repo1.maven.org/maven2/com/solacesystems/sol-jms/10.6.4/sol-jms-10.6.4.jar
fi

if [ ! -f ${DIR}/commons-lang-2.6.jar ]
then
     log "Downloading commons-lang-2.6.jar"
     wget -q https://repo1.maven.org/maven2/commons-lang/commons-lang/2.6/commons-lang-2.6.jar
fi


cd ../../connect/connect-jms-solace-source

# Copy JAR files to confluent-hub
mkdir -p ../../confluent-hub/confluentinc-kafka-connect-jms/lib/
cp ../../connect/connect-jms-solace-source/sol-jms-10.6.4.jar ../../confluent-hub/confluentinc-kafka-connect-jms/lib/sol-jms-10.6.4.jar
cp ../../connect/connect-jms-solace-source/commons-lang-2.6.jar ../../confluent-hub/confluentinc-kafka-connect-jms/lib/commons-lang-2.6.jar
cd -
PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.yml"

wait_for_solace
log "Solace UI is accessible at http://127.0.0.1:8080 (admin/admin)"

log "Create the queue connector-quickstart in the default Message VPN using CLI"
run_solace_cli_script_with_retry "create_queue_cmd" "queue creation"

# Setting message.timestamp.type=LogAppendTime otherwise we have CreateTime:0
playground topic create --topic source-messages --nb-partitions 1
playground topic alter --topic source-messages --add-config message.timestamp.type=LogAppendTime

log "Publish messages to the Solace queue using the REST endpoint"
for i in 1000 1001 1002
do
     curl -X POST -d "m1" http://localhost:9000/Queue/connector-quickstart -H "Content-Type: text/plain" -H "Solace-Message-ID: $i"
done

log "Creating Solace source connector"
playground connector create-or-update --connector jms-solace-source  << EOF
{
     "connector.class": "io.confluent.connect.jms.JmsSourceConnector",
     "tasks.max": "1",
     "kafka.topic": "source-messages",
     "java.naming.factory.initial": "com.solacesystems.jndi.SolJNDIInitialContextFactory",
     "java.naming.provider.url": "smf://solace:55555",
     "java.naming.security.principal": "admin",
     "java.naming.security.credentials": "admin",
     "connection.factory.name": "/jms/cf/default",
     "Solace_JMS_VPN": "default",
     "jms.destination.type": "queue",
     "jms.destination.name": "connector-quickstart",
     "key.converter": "org.apache.kafka.connect.storage.StringConverter",
     "value.converter": "org.apache.kafka.connect.storage.StringConverter",
     "confluent.topic.bootstrap.servers": "broker:9092",
     "confluent.topic.replication.factor": "1"
}
EOF

sleep 10

log "Verifying topic source-messages"
playground topic consume --topic source-messages --min-expected-messages 3 --timeout 60

sleep 5

log "Asserting that Solace queue connector-quickstart is empty after connector processing"
log "This tests that commitRecord API properly deletes messages from external system"
QUEUE_MSG_COUNT=$(curl -s -u admin:admin http://localhost:8080/SEMP/v2/monitor/msgVpns/default/queues/connector-quickstart | jq -r '.data.msgSpoolUsage // empty')

if [ -z "$QUEUE_MSG_COUNT" ]; then
    logerror "❌ Failed to retrieve queue message count from Solace"
    exit 1
fi

log "Current message spool usage for connector-quickstart: $QUEUE_MSG_COUNT bytes"

if [ "$QUEUE_MSG_COUNT" -eq 0 ]; then
    log "✅ SUCCESS: Solace queue connector-quickstart is empty - messages were successfully consumed and deleted"
else
    logerror "❌ FAILURE: Messages still remain in Solace queue connector-quickstart (spool usage: $QUEUE_MSG_COUNT bytes) - messages were not deleted"
    log "Displaying queue statistics:"
    curl -s -u admin:admin http://localhost:8080/SEMP/v2/monitor/msgVpns/default/queues/connector-quickstart | jq '.'
    exit 1
fi
