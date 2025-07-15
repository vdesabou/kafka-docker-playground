#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.yml"

log "Sending messages to topic filestream"
playground topic produce -t filestream --nb-messages 5 --key 1 << 'EOF'
{
  "fields": [
    {
      "doc": "count",
      "name": "count",
      "type": "long"
    },
    {
      "doc": "First Name of Customer",
      "name": "first_name",
      "type": "string"
    },
    {
      "doc": "Last Name of Customer",
      "name": "last_name",
      "type": "string"
    },
    {
      "doc": "Address of Customer",
      "name": "address",
      "type": "string"
    }
  ],
  "name": "Customer",
  "namespace": "com.github.vdesabou",
  "type": "record"
}
EOF

playground topic produce -t filestream --key 1 --tombstone


log "Creating FileStream Sink connector"
playground connector create-or-update --connector filestream-sink  << EOF
{
  "tasks.max": "1",
  "connector.class": "org.apache.kafka.connect.file.FileStreamSinkConnector",
  "topics": "filestream",
  "file": "/tmp/output.json",

  "transforms": "dropTombstone",
  "transforms.dropTombstone.type": "io.yokota.kafka.connect.transform.jsonata.JsonataTransformation",
  "transforms.dropTombstone.expr": "value = null ? null : \$"
}
EOF


sleep 5

log "Verify we have received the data in file"
docker exec connect cat /tmp/output.json
