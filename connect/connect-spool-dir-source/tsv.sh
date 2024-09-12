#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.yml"

log "Generate data"
docker exec -i connect bash -c 'mkdir -p /tmp/data/input/ && mkdir -p /tmp/data/error/ && mkdir -p /tmp/data/finished/ && curl -k "https://api.mockaroo.com/api/b10f7e90?count=1000&key=25fd9c80" > /tmp/data/input/tsv-spooldir-source.tsv'

log "Creating TSV Spool Dir Source connector"
playground connector create-or-update --connector TsvSpoolDir  << EOF
{
     "tasks.max": "1",
     "connector.class": "com.github.jcustenborder.kafka.connect.spooldir.SpoolDirCsvSourceConnector",
     "input.file.pattern": "tsv-spooldir-source.tsv",
     "input.path": "/tmp/data/input",
     "error.path": "/tmp/data/error",
     "finished.path": "/tmp/data/finished",
     "halt.on.error": "false",
     "topic": "spooldir-tsv-topic",
     "schema.generation.enabled": "true",
     "csv.first.row.as.header": "true",
     "csv.separator.char": "9"
}
EOF


sleep 5

log "Verify we have received the data in spooldir-tsv-topic topic"
playground topic consume --topic spooldir-tsv-topic --min-expected-messages 10 --timeout 60