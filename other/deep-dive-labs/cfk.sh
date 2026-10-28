#!/bin/bash
set -e
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh
source ${DIR}/lab-utils.bash

# lab of https://kafka-docker-playground.io/#/deep-dive-cfk
# the opposite of the other labs: it needs the cfk environment, so it runs in the cfk CI job only
# (run-tests.sh runs only this script of the folder there)
if [ "${PLAYGROUND_ENVIRONMENT:-plaintext}" != "cfk" ]
then
    logwarn "the cfk lab needs the cfk environment (k3d, kubectl, helm), skipping with ${PLAYGROUND_ENVIRONMENT:-plaintext}"
    exit 111
fi

log "Step 1: the FileStream sink on Kubernetes"
playground start-environment --environment cfk --docker-compose-override-file "${DIR}/docker-compose.plaintext.yml"
lab_run playground state get run.environment
lab_expect_contains "cfk"
lab_run playground status
lab_expect_contains "confluent-operator-"
lab_expect_contains "connect-0"
lab_expect_contains "kafka-0"
lab_expect_contains "kraftcontroller-0"
lab_expect_contains "schemaregistry-0"
lab_run playground topic produce -t filestream --nb-messages 5 --value '{"id": %g, "name": "name-%g"}'
lab_expect_exit 0
lab_expect_contains "kafkatopic.platform.confluent.io/filestream created"
lab_create_filestream_sink
lab_run playground connector status -c filestream-sink
lab_expect_contains "☸️ kubectl -n confluent get connector filestream-sink"
lab_expect_contains "☸️ CFK status details"
lab_expect_contains "app-ready: True"
lab_expect_contains "filestream-sink ✅ RUNNING 0:🟢 RUNNING"
lab_run playground container exec -c connect --command "cat /tmp/output.json"
lab_expect_exit 0
lab_expect_contains "🪄 Executing command in pod connect-0 with bash"
lab_expect_contains "{name=name-1, id=1}"

log "Step 2: what the CLI does on Kubernetes"
lab_run playground connector create-or-update -c lab-rewrites --dry-run << 'EOF'
{
  "tasks.max": "1",
  "connector.class": "org.apache.kafka.connect.file.FileStreamSinkConnector",
  "topics": "filestream",
  "file": "/tmp/output.json",
  "confluent.topic.bootstrap.servers": "broker:9092",
  "value.converter": "io.confluent.connect.avro.AvroConverter",
  "value.converter.schema.registry.url": "http://schema-registry:8081"
}
EOF
lab_expect_exit 0
lab_expect_contains "🌵 --dry-run: Connector CRD manifest that would be applied:"
lab_expect_contains "kind: Connector"
lab_expect_contains "class: org.apache.kafka.connect.file.FileStreamSinkConnector"
lab_expect_contains "taskMax: 1"
lab_expect_contains 'confluent.topic.bootstrap.servers: "kafka:9071"'
lab_expect_contains 'value.converter.schema.registry.url: "http://schemaregistry:8081"'
lab_run playground connector create-or-update -c FileStream_Sink --dry-run << 'EOF'
{
  "connector.class": "org.apache.kafka.connect.file.FileStreamSinkConnector",
  "topics": "filestream"
}
EOF
lab_expect_exit 1
lab_expect_contains "with CFK, the connector name is the name of a Kubernetes Connector resource"
lab_run playground connector show-config -c filestream-sink
lab_expect_contains "(using CFK Connector CR)"
lab_expect_contains '"file": "/tmp/output.json"'
lab_run playground connector validate -c filestream-sink
lab_expect_contains "⚠️ validation with CFK currently performs basic checks only (no Connect REST validation endpoint)"
lab_expect_contains "✅ Basic CFK validation passed"
lab_run playground connector benchmark -c filestream-sink
lab_expect_exit 1
lab_expect_contains "❌ benchmark is not available with the cfk environment yet"
lab_run playground container recreate
lab_expect_exit 1
lab_expect_contains "❌ container recreate is not supported in cfk mode"
lab_run playground topic describe -t filestream
lab_expect_contains "🎰 kubectl -n confluent describe kafkatopic filestream"
lab_expect_contains "Kind: KafkaTopic"
lab_expect_contains "PartitionCount: 1"

log "Step 3: pause, resume, restart: annotations and pod deletions"
lab_run playground connector pause -c filestream-sink
lab_expect_contains "☸️ kubectl annotate connector filestream-sink -n confluent platform.confluent.io/pause-connector=true --overwrite"
lab_run playground connector wait -c filestream-sink --state PAUSED --max-wait 120
lab_expect_exit 0
lab_run playground connector resume -c filestream-sink
lab_expect_contains "☸️ kubectl annotate connector filestream-sink -n confluent platform.confluent.io/resume-connector=true --overwrite"
lab_run playground connector wait -c filestream-sink --max-wait 120
lab_expect_exit 0
lab_run playground container restart -c connect
lab_expect_contains "🔁 Restarting pod connect-0"
# the port-forward to Connect died with the pod: connector wait starts a new one until the new connect-0 answers
lab_run playground connector wait -c filestream-sink --max-wait 300
lab_expect_exit 0
playground topic produce -t filestream --nb-messages 3 --value '{"id": "after-restart-%g"}'
sleep 15
lab_run playground container exec -c connect --command "cat /tmp/output.json"
lab_expect_exit 0
lab_expect_contains "{id=after-restart-1}"
lab_expect_not_contains "{name=name-1, id=1}" "a record written before the pod restart"
lab_run playground topic get-number-records -t filestream
lab_expect_contains "8"

log "Step 4: a failed task, the logs, a support bundle"
playground connector create-or-update -c filestream-broken --no-wait << 'EOF'
{
  "tasks.max": "1",
  "connector.class": "org.apache.kafka.connect.file.FileStreamSinkConnector",
  "topics": "filestream",
  "file": "/does/not/exist/output.json",
  "key.converter": "org.apache.kafka.connect.storage.StringConverter",
  "value.converter": "org.apache.kafka.connect.json.JsonConverter",
  "value.converter.schemas.enable": "false"
}
EOF
lab_run playground connector wait -c filestream-broken --state FAILED --max-wait 180
lab_expect_exit 0
lab_run playground connector status -c filestream-broken
lab_expect_contains "0:🛑 FAILED"
lab_expect_contains "Couldn't find or create file '/does/not/exist/output.json'"
lab_run playground container logs -c connect --errors
lab_expect_contains "WorkerSinkTask{id=filestream-broken-0} Task threw an uncaught and unrecoverable exception"
lab_expect_contains "Caused by: java.nio.file.NoSuchFileException: /does/not/exist/output.json"
# the Connector CR reports the failed task (status.failedTasks) at its next reconcile only: wait for it, so that the
# bundle has it
failed_tasks=""
for i in $(seq 1 36)
do
    failed_tasks=$(kubectl -n confluent get connector filestream-broken -o jsonpath='{.status.failedTasks}' 2>/dev/null || true)
    if [ -n "$failed_tasks" ]
    then
        break
    fi
    sleep 5
done
log "status.failedTasks of the Connector CR after $(( (i - 1) * 5 )) seconds: $failed_tasks"
lab_run playground debug cfk generate-bundle
lab_expect_exit 0
lab_expect_contains "✅ Support bundle generated successfully!"
lab_expect_contains "📦 Bundle: /tmp/cfk-support-bundle/support-bundle-ns-confluent-"
bundle=$(grep -oE '/tmp/cfk-support-bundle/support-bundle[^ ]*\.tar\.gz' <<< "$LAB_OUTPUT" | head -1)
lab_run playground analyze cfk-bundle --bundle "$bundle" --output-dir /tmp/lab-cfk-bundle
lab_expect_exit 0
lab_expect_contains "CFK operator: 3.3.0 (image tag 0.1718.10)"
lab_expect_contains "Connector/filestream-broken has failed tasks"
lab_expect_contains "Affects 1 task(s): filestream-broken-0"
lab_expect_contains "outside the range supported by CFK 3.3.0: 7.5 - 8.3"
lab_run playground analyze cfk-bundle --bundle "$bundle" --component connect --output-dir /tmp/lab-cfk-bundle
lab_expect_exit 0
lab_expect_contains "Filtered on: --component connect"
lab_expect_contains "By component: connect"

log "Step 5: stop"
lab_run playground stop
lab_expect_contains "🔀 Stopping CFK port-forward process(es)"
lab_run k3d cluster list
lab_expect_contains "playground-cfk"

log "✅ all the outputs of the page are as expected"
