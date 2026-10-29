#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.yml"

# number of records in the file (container exec also logs the command it runs: keep the number of the last line)
function output_line_count () {
    playground container exec --container connect --command "bash -c 'wc -l < /tmp/output.json 2>/dev/null || echo 0'" 2>/dev/null | tail -1 | grep -o -E "[0-9]+" | tail -1
}

log "Creating FileStream Sink connector"
playground connector create-or-update --connector filestream-sink --wait << EOF
{
     "tasks.max": "1",
     "connector.class": "org.apache.kafka.connect.file.FileStreamSinkConnector",
     "topics": "filestream",
     "file": "/tmp/output.json",
     "key.converter": "org.apache.kafka.connect.storage.StringConverter",
     "value.converter": "org.apache.kafka.connect.storage.StringConverter"
}
EOF

log "Throttle the consumer of the connector task to 1 KB/s with a client quota (client id connector-consumer-filestream-sink-0)"
playground quota set --connector filestream-sink --consumer-byte-rate 1024

log "Sending 100 records of 1 KB (100 KB, about 100 seconds at 1 KB/s)"
playground topic produce -t filestream --nb-messages 100 --value "record-%g-$(printf 'x%.0s' {1..1000})"

log "Verify the connector is throttled: after 30 seconds, only part of the 100 records is in the file"
sleep 30
nb_lines=$(output_line_count)
log "📄 $nb_lines records written in 30 seconds"
if [ "$nb_lines" -ge 100 ]
then
    logerror "❌ all the records were written in 30 seconds: the quota did not throttle the connector"
    exit 1
fi

log "Remove the quota"
playground quota delete --connector filestream-sink

log "Verify the remaining records are written right away"
MAX_WAIT=60
CUR_WAIT=0
while true
do
    nb_lines=$(output_line_count)
    if [ "$nb_lines" -ge 100 ]
    then
        log "✅ the 100 records are in the file, $CUR_WAIT seconds after removing the quota"
        break
    fi
    sleep 5
    CUR_WAIT=$(( CUR_WAIT+5 ))
    if [[ "$CUR_WAIT" -gt "$MAX_WAIT" ]]
    then
        logerror "❌ only $nb_lines records in the file $MAX_WAIT seconds after removing the quota"
        exit 1
    fi
done
