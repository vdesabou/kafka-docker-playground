#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if connect_cp_version_greater_than_8 && [ ! -z "$CONNECTOR_TAG" ] && ! version_gt $CONNECTOR_TAG "1.1.99"
then
     logwarn "minimal supported connector version is 1.2.0 for CP 8.0"
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

function dump_solace_cfk_debug () {
     if [[ "${PLAYGROUND_ENVIRONMENT:-plaintext}" != "cfk" ]]
     then
          return
     fi

nproc
free -h
df -h
ulimit -a
docker info

     log "####################################################"
     log "☸️ kubectl get pods -o wide"
     kubectl -n confluent get pods -o wide || true
     log "####################################################"
     log "☸️ kubectl describe pod solace"
     kubectl -n confluent describe pod solace || true
     log "####################################################"
     log "☸️ kubectl get events (latest 30)"
     kubectl -n confluent get events --sort-by=.lastTimestamp | tail -30 || true
     log "####################################################"
     log "☸️ kubectl logs solace --all-containers --tail=200"
     kubectl -n confluent logs solace --all-containers=true --tail=200 || true
     log "####################################################"
     log "☸️ kubectl logs solace --all-containers --previous --tail=200"
     kubectl -n confluent logs solace --all-containers=true --previous --tail=200 || true
     log "####################################################"
}

function run_solace_cli_script_with_retry () {
     local script_name="$1"
     local description="$2"
     local max_wait=300
     local cur_wait=0
     local output_file="/tmp/solace-cli-${script_name}.log"

     if [[ "${PLAYGROUND_ENVIRONMENT:-plaintext}" == "cfk" ]]
     then
          max_wait=300
     fi

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
               dump_solace_cfk_debug
               cat "$output_file"
               exit 1
          fi
     done
}

function create_solace_queue_with_retry () {
     local queue_name="$1"
     local max_wait=300
     local cur_wait=0
     local output_file="/tmp/solace-semp-create-queue-${queue_name}.log"
     local get_status
     local post_status

     if [[ "${PLAYGROUND_ENVIRONMENT:-plaintext}" == "cfk" ]]
     then
          max_wait=900
     fi

     log "⌛ Waiting up to $max_wait seconds for Solace SEMP API to create queue ${queue_name}"
     while true
     do
          if [[ "${PLAYGROUND_ENVIRONMENT:-plaintext}" == "cfk" ]]
          then
               set +e
               get_status=$(playground container exec --container solace --command "bash -c 'curl -sS -u admin:admin -o /tmp/semp-get.log -w \"%{http_code}\" \"http://localhost:8080/SEMP/v2/config/msgVpns/default/queues/${queue_name}\"'")
               ret_get=$?
               if [ $ret_get -eq 0 ]
               then
                    playground container exec --container solace --command "cat /tmp/semp-get.log" > "$output_file" 2>&1 || true
               fi
               set -e
          else
               set +e
               get_status=$(curl -sS -u admin:admin -o "$output_file" -w "%{http_code}" "http://localhost:8080/SEMP/v2/config/msgVpns/default/queues/${queue_name}")
               ret_get=$?
               set -e
          fi

          if [ $ret_get -eq 0 ] && [[ "$get_status" == "200" ]]
          then
               log "Solace queue ${queue_name} is ready"
               return
          fi

          if [[ "${PLAYGROUND_ENVIRONMENT:-plaintext}" == "cfk" ]]
          then
               set +e
               post_status=$(playground container exec --container solace --command "bash -c 'curl -sS -u admin:admin -o /tmp/semp-post.log -w \"%{http_code}\" -X POST \"http://localhost:8080/SEMP/v2/config/msgVpns/default/queues\" -H \"Content-Type: application/json\" -d \"{\\\"queueName\\\":\\\"${queue_name}\\\",\\\"permission\\\":\\\"consume\\\",\\\"ingressEnabled\\\":true,\\\"egressEnabled\\\":true}\"'")
               ret_post=$?
               if [ $ret_post -eq 0 ]
               then
                    playground container exec --container solace --command "cat /tmp/semp-post.log" > "$output_file" 2>&1 || true
               fi
               set -e
          else
               set +e
               post_status=$(curl -sS -u admin:admin -o "$output_file" -w "%{http_code}" -X POST "http://localhost:8080/SEMP/v2/config/msgVpns/default/queues" -H "Content-Type: application/json" -d "{\"queueName\":\"${queue_name}\",\"permission\":\"consume\",\"ingressEnabled\":true,\"egressEnabled\":true}")
               ret_post=$?
               set -e
          fi

          if [ $ret_post -eq 0 ] && { [[ "$post_status" == "200" ]] || [[ "$post_status" == "201" ]] || [[ "$post_status" == "204" ]]; }
          then
               log "Solace queue ${queue_name} was created through SEMP API"
               return
          fi

          if [ $ret_post -eq 0 ] && [[ "$post_status" == "400" ]] && grep -qi "already exists" "$output_file"
          then
               log "Solace queue ${queue_name} already exists"
               return
          fi

          sleep 10
          cur_wait=$((cur_wait + 10))
          if (( cur_wait % 60 == 0 ))
          then
               logwarn "Solace SEMP queue creation not ready yet, retrying... (${cur_wait}/${max_wait}s)"
          fi
          if [[ "$cur_wait" -gt "$max_wait" ]]
          then
               logerror "Solace SEMP API could not create queue ${queue_name} after ${max_wait} seconds"
               cat "$output_file"
               dump_solace_cfk_debug
               exit 1
          fi
     done
}

cd ../../connect/connect-solace-source
if [ ! -f ${DIR}/sol-jms-10.6.4.jar ]
then
     log "Downloading sol-jms-10.6.4.jar"
     wget -q https://repo1.maven.org/maven2/com/solacesystems/sol-jms/10.6.4/sol-jms-10.6.4.jar
fi
cd -


cd ../../connect/connect-solace-source

# Copy JAR files to confluent-hub
mkdir -p ../../confluent-hub/confluentinc-kafka-connect-solace-source/lib/
cp ../../connect/connect-solace-source/sol-jms-10.6.4.jar ../../confluent-hub/confluentinc-kafka-connect-solace-source/lib/sol-jms-10.6.4.jar
cd -
PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}

# In CFK mode, compose tmpfs /dev/shm is translated to an EmptyDir volume with a size limit.
# Solace can restart during startup in constrained CI environments when this is too small.
if [[ "${PLAYGROUND_ENVIRONMENT}" == "cfk" ]] && [[ -z "${CFK_TMPFS_SHM_SIZE_LIMIT:-}" ]]
then
     export CFK_TMPFS_SHM_SIZE_LIMIT="2Gi"
     log "Using CFK_TMPFS_SHM_SIZE_LIMIT=${CFK_TMPFS_SHM_SIZE_LIMIT} for Solace stability in CI"
fi

playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.yml"

wait_for_solace
log "Solace UI is accessible at http://127.0.0.1:8080 (admin/admin)"

log "Create the queue connector-quickstart in the default Message VPN using CLI"
if [[ "${PLAYGROUND_ENVIRONMENT}" == "cfk" ]]
then
     create_solace_queue_with_retry "connector-quickstart"
else
     run_solace_cli_script_with_retry "create_queue_cmd" "queue creation"
fi

# Setting message.timestamp.type=LogAppendTime otherwise we have CreateTime:0
playground topic create --topic from-solace-messages --nb-partitions 1
playground topic alter --topic from-solace-messages --add-config message.timestamp.type=LogAppendTime

log "Publish messages to the Solace queue using the REST endpoint"

for i in 1000 1001 1002
do
     if [[ "${PLAYGROUND_ENVIRONMENT}" == "cfk" ]]
     then
          playground container exec --container solace --command "bash -c 'curl -sS -X POST -d \"m1\" \"http://localhost:9000/Queue/connector-quickstart\" -H \"Content-Type: text/plain\" -H \"Solace-Message-ID: ${i}\"'"
     else
          curl -X POST -d "m1" http://localhost:9000/Queue/connector-quickstart -H "Content-Type: text/plain" -H "Solace-Message-ID: $i"
     fi
done

log "Creating Solace source connector"
playground connector create-or-update --connector solace-source  << EOF
{
     "connector.class": "io.confluent.connect.solace.SolaceSourceConnector",
     "tasks.max": "1",
     "kafka.topic": "from-solace-messages",
     "solace.host": "smf://solace:55555",
     "solace.username": "admin",
     "solace.password": "admin",
     "jms.destination.type": "queue",
     "jms.destination.name": "connector-quickstart",
     "key.converter": "org.apache.kafka.connect.storage.StringConverter",
     "value.converter": "org.apache.kafka.connect.storage.StringConverter",
     "confluent.topic.bootstrap.servers": "broker:9092",
     "confluent.topic.replication.factor": "1"
}
EOF

sleep 10

log "Verifying topic from-solace-messages"
playground topic consume --topic from-solace-messages --min-expected-messages 3 --timeout 60


sleep 5

log "Asserting that Solace queue connector-quickstart is empty after connector processing"
log "This tests that commitRecord API properly deletes messages from external system"
if [[ "${PLAYGROUND_ENVIRONMENT}" == "cfk" ]]
then
     QUEUE_MSG_COUNT=$(playground container exec --container solace --command "curl -s -u admin:admin http://localhost:8080/SEMP/v2/monitor/msgVpns/default/queues/connector-quickstart" | jq -r '.data.msgSpoolUsage // empty')
else
     QUEUE_MSG_COUNT=$(curl -s -u admin:admin http://localhost:8080/SEMP/v2/monitor/msgVpns/default/queues/connector-quickstart | jq -r '.data.msgSpoolUsage // empty')
fi

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
     if [[ "${PLAYGROUND_ENVIRONMENT}" == "cfk" ]]
     then
          playground container exec --container solace --command "curl -s -u admin:admin http://localhost:8080/SEMP/v2/monitor/msgVpns/default/queues/connector-quickstart" | jq '.'
     else
          curl -s -u admin:admin http://localhost:8080/SEMP/v2/monitor/msgVpns/default/queues/connector-quickstart | jq '.'
     fi
    exit 1
fi
