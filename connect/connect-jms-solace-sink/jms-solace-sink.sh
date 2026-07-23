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

          if grep -E "SolOS startup in progress|Please try again later" "$output_file" > /dev/null 2>&1
          then
               sleep 10
               cur_wait=$((cur_wait + 10))
               if [[ "$cur_wait" -gt "$max_wait" ]]
               then
                    logerror "Solace CLI is not ready for ${description} after ${max_wait} seconds"
                    cat "$output_file"
                    exit 1
               fi
               continue
          fi

          logerror "Solace CLI command for ${description} failed with a non-retryable error"
          cat "$output_file"
          exit 1
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


cd ../../connect/connect-jms-solace-sink

# Copy JAR files to confluent-hub
mkdir -p ../../confluent-hub/confluentinc-kafka-connect-jms-sink/lib/
cp ../../connect/connect-jms-solace-sink/sol-jms-10.6.4.jar ../../confluent-hub/confluentinc-kafka-connect-jms-sink/lib/sol-jms-10.6.4.jar
cp ../../connect/connect-jms-solace-sink/commons-lang-2.6.jar ../../confluent-hub/confluentinc-kafka-connect-jms-sink/lib/commons-lang-2.6.jar
cd -
PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.yml"

wait_for_solace
log "Solace UI is accessible at http://127.0.0.1:8080 (admin/admin)"

log "Sending messages to topic sink-messages"
playground topic produce -t sink-messages --nb-messages 10 << 'EOF'
%g
EOF

log "Create connector-quickstart queue in the default Message VPN using CLI"
run_solace_cli_script_with_retry "create_queue_cmd" "queue creation"

log "Creating Solace sink connector"
playground connector create-or-update --connector jms-solace-sink  << EOF
{
     "connector.class": "io.confluent.connect.jms.JmsSinkConnector",
     "tasks.max": "1",
     "topics": "sink-messages",
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

log "Confirm the messages were delivered to the connector-quickstart queue in the default Message VPN using CLI"
run_solace_cli_script_with_retry "show_queue_cmd" "queue stats check" "/tmp/result.log"
cat /tmp/result.log
grep "10       0.00" /tmp/result.log