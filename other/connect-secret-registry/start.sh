#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if ! version_gt $TAG_BASE "5.2.99"; then
    logwarn "WARN: Connect Secret Registry is available since CP 5.3 only"
    exit 111
fi

playground start-environment --environment rbac-sasl-plain --docker-compose-override-file "${PWD}/docker-compose.rbac-sasl-plain.yml"

log "Sending messages to topic rbac_topic"
playground topic produce -t rbac_topic --nb-messages 10 --forced-value '{"f1":"value%g"}' << 'EOF'
{
  "type": "record",
  "name": "myrecord",
  "fields": [
    {
      "name": "f1",
      "type": "string"
    }
  ]
}
EOF

log "Checking messages from topic rbac_topic"
playground topic consume --topic rbac_topic --min-expected-messages 1 --timeout 60

log "Registering secret my-smt-password with this-is-my-secret-value"
curl -X POST \
     -u superUser:superUser \
     -H "Content-Type: application/json" \
     --data '{
               "secret": "this-is-my-secret-value"
          }' \
     http://localhost:8083/secret/paths/my-rbac-connector/keys/my-smt-password/versions | jq .

log "Creating FileStream Sink connector"
playground connector create-or-update --connector my-rbac-connector  << EOF
{
     "tasks.max": "1",
     "connector.class": "org.apache.kafka.connect.file.FileStreamSinkConnector",
     "topics": "rbac_topic",
     "file": "/tmp/output.json",
     "value.converter": "io.confluent.connect.avro.AvroConverter",
     "value.converter.schema.registry.url": "http://schema-registry:8081",
     "transforms": "InsertField",
     "transforms.InsertField.type": "org.apache.kafka.connect.transforms.InsertField\$Value",
     "transforms.InsertField.static.field": "AddedBySMT",
     "transforms.InsertField.static.value": "\${secret:my-rbac-connector:my-smt-password}"
}
EOF


sleep 5

log "Verify we have received the data in file"
docker exec connect cat /tmp/output.json

# Struct{f1=This is a message sent with RBAC SASL/PLAIN authentication 1,AddedBySMT=this-is-my-secret-value}
# Struct{f1=This is a message sent with RBAC SASL/PLAIN authentication 2,AddedBySMT=this-is-my-secret-value}
# Struct{f1=This is a message sent with RBAC SASL/PLAIN authentication 3,AddedBySMT=this-is-my-secret-value}
# Struct{f1=This is a message sent with RBAC SASL/PLAIN authentication 4,AddedBySMT=this-is-my-secret-value}
# Struct{f1=This is a message sent with RBAC SASL/PLAIN authentication 5,AddedBySMT=this-is-my-secret-value}
# Struct{f1=This is a message sent with RBAC SASL/PLAIN authentication 6,AddedBySMT=this-is-my-secret-value}
# Struct{f1=This is a message sent with RBAC SASL/PLAIN authentication 7,AddedBySMT=this-is-my-secret-value}
# Struct{f1=This is a message sent with RBAC SASL/PLAIN authentication 8,AddedBySMT=this-is-my-secret-value}
# Struct{f1=This is a message sent with RBAC SASL/PLAIN authentication 9,AddedBySMT=this-is-my-secret-value}
# Struct{f1=This is a message sent with RBAC SASL/PLAIN authentication 10,AddedBySMT=this-is-my-secret-value}
