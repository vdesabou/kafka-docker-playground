#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if ! version_gt $TAG_BASE "8.1.99"
then
     logerror "CP 8.2+ is required to have support for value.converter.schema.content configuration property"
     exit 1
fi

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.yml"

log "Sending messages to topic filestream"
playground topic produce -t filestream --nb-messages 1 << 'EOF'
{
    "id": "emp_001",
    "name": "Kevin"
}
EOF

log "Creating FileStream Sink connector with schema content"
playground connector create-or-update --connector filestream-sink  << EOF
{
     "tasks.max": "1",
     "connector.class": "org.apache.kafka.connect.file.FileStreamSinkConnector",
     "topics": "filestream",
     "file": "/tmp/output.json",
     "key.converter": "org.apache.kafka.connect.storage.StringConverter",
     "value.converter": "org.apache.kafka.connect.json.JsonConverter",
     "value.converter.schemas.enable": "true",
     "value.converter.schema.content": "{\"type\": \"struct\", \"fields\": [{ \"field\": \"id\", \"type\": \"string\", \"optional\": false },{ \"field\": \"name\", \"type\": \"string\", \"optional\": false }]}"
}
EOF


sleep 5

log "Verify we have received the data in file"
docker exec connect cat /tmp/output.json
# Struct{id=emp_001,name=Kevin}