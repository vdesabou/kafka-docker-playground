#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.yml"

log "Sending messages to topic filestream"
playground topic produce -t filestream --nb-messages 5 << 'EOF'
[
    {
        "_meta": {
            "topic": "",
            "key": "",
            "relationships": [
            ]
        },
        "nested": {
            "phone": "faker.phone.imei()",
            "website": "faker.internet.domainName()"
        },
        "id": "iteration.index",
        "name": "faker.internet.userName()",
        "email": "faker.internet.exampleEmail()",
        "phone": "faker.phone.imei()",
        "website": "faker.internet.domainName()",
        "city": "faker.address.city()",
        "company": "faker.company.name()"
    }
]
EOF

log "Creating FileStream Sink connector"
playground connector create-or-update --connector filestream-sink --environment "${PLAYGROUND_ENVIRONMENT}" << EOF
{
     "tasks.max": "1",
     "connector.class": "org.apache.kafka.connect.file.FileStreamSinkConnector",
     "topics": "filestream",
     "file": "/tmp/output.json",
     "key.converter": "org.apache.kafka.connect.storage.StringConverter",
     "value.converter": "org.apache.kafka.connect.json.JsonConverter",
     "value.converter.schemas.enable": "false"
}
EOF


sleep 5

log "Verify we have received the data in file"
docker exec connect cat /tmp/output.json
