#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.failed-to-flush-timed-out-while-connector-running.yml"
log "Generating data"
docker exec -i connect bash -c "mkdir -p /tmp/kafka-connect/examples/ && curl -sSL -k 'https://api.mockaroo.com/api/17c84440?count=500&key=25fd9c80' -o /tmp/kafka-connect/examples/file.json"

docker exec --privileged --user root -i broker yum install -y libmnl
docker exec --privileged --user root -i broker bash -c 'wget -q http://vault.centos.org/8.1.1911/BaseOS/x86_64/os/Packages/iproute-tc-4.18.0-15.el8.x86_64.rpm && rpm -i --nodeps --nosignature http://vault.centos.org/8.1.1911/BaseOS/x86_64/os/Packages/iproute-tc-4.18.0-15.el8.x86_64.rpm'

log "Adding latency"
add_latency broker connect 1000ms

log "Creating FileStream Source connector"
playground connector create-or-update --connector filestream-source  << EOF
{
               "tasks.max": "1",
               "connector.class": "org.apache.kafka.connect.file.FileStreamSourceConnector",
               "topic": "filestream",
               "file": "/tmp/kafka-connect/examples/file.json",
               "key.converter": "org.apache.kafka.connect.storage.StringConverter",
               "value.converter": "org.apache.kafka.connect.json.JsonConverter",
               "value.converter.schemas.enable": "false"
          }
EOF


sleep 5

log "Verify we have received the data in filestream topic"
playground topic consume --topic filestream --min-expected-messages 10 --timeout 60

# works ok task is not failed, just printing in logs

# [2022-01-11 12:07:23,481] INFO [filestream-source|task-0|offsets] WorkerSourceTask{id=filestream-source-0} Committing offsets (org.apache.kafka.connect.runtime.WorkerSourceTask:485)
# [2022-01-11 12:07:23,481] INFO [filestream-source|task-0|offsets] WorkerSourceTask{id=filestream-source-0} flushing 441 outstanding messages for offset commit (org.apache.kafka.connect.runtime.WorkerSourceTask:502)
# [2022-01-11 12:07:23,559] INFO [filestream-source|task-0] [Producer clientId=confluent.monitoring.interceptor.connect-worker-producer] Cluster ID: jzQQ_4yATISr2EK839fD4A (org.apache.kafka.clients.Metadata:279)
# [2022-01-11 12:07:23,981] ERROR [filestream-source|task-0|offsets] WorkerSourceTask{id=filestream-source-0} Failed to flush, timed out while waiting for producer to flush outstanding 384 messages (org.apache.kafka.connect.runtime.WorkerSourceTask:509)
# [2022-01-11 12:07:23,982] ERROR [filestream-source|task-0|offsets] WorkerSourceTask{id=filestream-source-0} Failed to commit offsets (org.apache.kafka.connect.runtime.SourceTaskOffsetCommitter:116)
