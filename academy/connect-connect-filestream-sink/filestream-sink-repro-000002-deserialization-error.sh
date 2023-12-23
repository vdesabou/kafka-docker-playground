#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.repro-000002-deserialization-error.yml"

log "Sending messages to topic filestream"
playground topic produce -t filestream --nb-messages 3 --verbose << 'EOF'
{"type":"record","name":"myrecord","fields":[{"name":"u_name","type":"string"},{"name":"u_price", "type": "float"}, {"name":"u_quantity", "type": "int"}]}
EOF


log "Sending again message to topic filestream"
playground topic produce -t filestream --nb-messages 1 --verbose << 'EOF'
{"u_name": "poison pill", "u_price": 1.75, "u_quantity": 1}
EOF

log "Sending again messages to topic filestream"
playground topic produce -t filestream --nb-messages 1 --verbose << 'EOF'
{"type":"record","name":"myrecord","fields":[{"name":"u_name","type":"string"},{"name":"u_price", "type": "float"}, {"name":"u_quantity", "type": "int"}]}
EOF

log "Creating FileStream Sink connector"
playground connector create-or-update --connector filestream-sink --environment "${PLAYGROUND_ENVIRONMENT}" << EOF
{
     "tasks.max": "1",
     "connector.class": "org.apache.kafka.connect.file.FileStreamSinkConnector",
     "topics": "filestream",
     "file": "/tmp/output.json",
     "key.converter": "org.apache.kafka.connect.storage.StringConverter",
     "value.converter": "io.confluent.connect.avro.AvroConverter",
     "value.converter.schema.registry.url": "http://schema-registry:8081"
}
EOF


sleep 5

playground connector status

playground topic consume

playground connector show-lag

# log "Verify we have received the data in file"
# docker exec connect cat /tmp/output.json
