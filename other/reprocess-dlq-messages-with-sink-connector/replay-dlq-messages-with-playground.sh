#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.yml"

log "Sending messages to topic avro-topic"
playground topic produce -t avro-topic --nb-messages 10 < ../../scripts/cli/predefined-schemas/avro/lead.avsc

log "killing schema-registry container to have the messages sent to DLQ since schema-registry is not available"
playground container kill --container schema-registry

log "Creating FileStream Sink connector"
playground connector create-or-update --connector filestream-sink --wait << EOF
{
    "tasks.max": "1",
    "connector.class": "org.apache.kafka.connect.file.FileStreamSinkConnector",
    "topics": "avro-topic",
    "file": "/tmp/output.json",

    "errors.tolerance": "all",
    "errors.deadletterqueue.topic.name": "dlq",
    "errors.deadletterqueue.topic.replication.factor": "1",
    "errors.deadletterqueue.context.headers.enable": "true",
    "errors.log.enable": "true",
    "errors.log.include.messages": "true"
}
EOF

playground topic wait-for-records --topic dlq --min-expected-messages 10 --max-wait 120

log "Inspect the DLQ: records grouped by error, with the root cause and the original offsets"
playground topic dlq inspect --topic dlq

nb_records=$(playground topic dlq inspect --topic dlq --json | jq '[.groups[] | select(.stage == "VALUE_CONVERTER") | .count] | add // 0')
if [ "$nb_records" != "10" ]
then
    logerror "❌ expected 10 records failed in the value converter in the DLQ, got $nb_records"
    exit 1
fi

log "Restart schema-registry container: the cause of the failures is fixed"
playground container restart --container schema-registry

retries=0
until playground schema get --subject avro-topic-value > /dev/null 2>&1
do
    retries=$((retries+1))
    if [ $retries -gt 60 ]
    then
        logerror "❌ schema-registry is not available after 120 seconds"
        exit 1
    fi
    sleep 2
done

log "Replay the DLQ records to their original topic avro-topic (dry run first)"
playground topic dlq replay --topic dlq --dry-run
playground topic dlq replay --topic dlq

log "filestream-sink processes the replayed records: they are now written to the file"
playground connector show-lag --connector filestream-sink --max-wait 120

log "Verify we have received the data in file"
playground container exec --container connect --command "cat /tmp/output.json"
nb_lines=$(playground --output-level ERROR container exec --container connect --command "wc -l < /tmp/output.json" | tr -d ' \r')
if [ "$nb_lines" != "10" ]
then
    logerror "❌ expected 10 records in /tmp/output.json, got $nb_lines"
    exit 1
fi

nb_dlq=$(playground topic get-number-records --topic dlq | tail -1)
if [ "$nb_dlq" != "10" ]
then
    logerror "❌ the replayed records failed again: the DLQ has $nb_dlq records instead of 10"
    exit 1
fi
log "✅ the 10 replayed records were processed and none went back to the DLQ"
