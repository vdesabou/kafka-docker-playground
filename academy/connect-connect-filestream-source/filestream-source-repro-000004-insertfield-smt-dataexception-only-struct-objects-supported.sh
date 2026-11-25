#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.repro-000004-insertfield-smt-dataexception-only-struct-objects-supported.yml"
log "Generating data"
# a few JSON lines, written locally (no call to an external data generator)
docker exec -i connect bash -c "mkdir -p /tmp/kafka-connect/examples/ && cat > /tmp/kafka-connect/examples/file.json" << 'EOF'
{"id":1,"first_name":"Florance","last_name":"Probet","email":"fprobet0@example.com","gender":"Female","country":"DK","account_balance":20949.73}
{"id":2,"first_name":"Ravi","last_name":"Harly","email":"rharly1@example.com","gender":"Male","country":"FR","account_balance":3011.5}
{"id":3,"first_name":"Jenelle","last_name":"Fick","email":"jfick2@example.com","gender":"Female","country":"PH","account_balance":22810.68}
EOF

log "Creating FileStream Source connector"
playground connector create-or-update --connector filestream-source  << EOF
{
     "tasks.max": "1",
     "connector.class": "org.apache.kafka.connect.file.FileStreamSourceConnector",
     "topic": "filestream",
     "file": "/tmp/kafka-connect/examples/file.json",
     "key.converter": "org.apache.kafka.connect.storage.StringConverter",
     "value.converter": "org.apache.kafka.connect.json.JsonConverter",
     "value.converter.schemas.enable": "false",
     "errors.log.enable": "true",
     "errors.log.include.messages": "true",

     "transforms": "InsertField",
     "transforms.InsertField.type": "org.apache.kafka.connect.transforms.InsertField\$Value",
     "transforms.InsertField.static.field": "MessageSource",
     "transforms.InsertField.static.value": "Kafka Connect framework"
}
EOF

sleep 5

playground connector status
