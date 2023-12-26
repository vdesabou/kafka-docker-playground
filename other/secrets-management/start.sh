#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if ! version_gt $TAG_BASE "5.2.99"; then
    logwarn "WARN: Confluent Secrets is available since CP 5.3 only"
    exit 111
fi

verify_installed "confluent"
check_confluent_version 3.0.0 || exit 1

cd ../../other/secrets-management
rm -f ${DIR}/secrets/secret.txt
rm -f ${DIR}/secrets/CONFLUENT_SECURITY_MASTER_KEY

log "Generate master key"
confluent secret master-key generate --local-secrets-file ${DIR}/secrets/secret.txt --passphrase @${DIR}/secrets/passphrase.txt > /tmp/result.log 2>&1
cat /tmp/result.log
export CONFLUENT_SECURITY_MASTER_KEY=$(grep "Master Key" /tmp/result.log | cut -d"|" -f 3 | sed "s/ //g" | tail -1 | tr -d "\n")
echo "$CONFLUENT_SECURITY_MASTER_KEY" > ${DIR}/secrets/CONFLUENT_SECURITY_MASTER_KEY
log "Encrypting my-secret-property in file my-config-file.properties"
confluent secret file encrypt --local-secrets-file ${DIR}/secrets/secret.txt --remote-secrets-file ${DIR}/secrets/secret.txt --config my-secret-property --config-file ${DIR}/secrets/my-config-file.properties
cd -

export CONFLUENT_SECURITY_MASTER_KEY=$(cat ${DIR}/secrets/CONFLUENT_SECURITY_MASTER_KEY | sed 's/ //g' | tail -1 | tr -d '\n')
log "Exporting CONFLUENT_SECURITY_MASTER_KEY=$CONFLUENT_SECURITY_MASTER_KEY"

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.yml"

log "Sending messages to topic my-secret-value"
playground topic produce -t my-secret-value << 'EOF'
{"customer_name":"Ed", "complaint_type":"Dirty car", "trip_cost": 29.10, "new_customer": false, "number_of_rides": 22}
EOF

log "Creating FileStream Sink connector with topics set with secrets variable"
playground connector create-or-update --connector filestream-sink  << EOF
{
    "tasks.max": "1",
    "connector.class": "org.apache.kafka.connect.file.FileStreamSinkConnector",
    "topics": "\${securepass:/etc/kafka/secrets/secret.txt:my-config-file.properties/my-secret-property}",
    "file": "/tmp/output.json",
    "key.converter": "org.apache.kafka.connect.storage.StringConverter",
    "value.converter": "org.apache.kafka.connect.json.JsonConverter",
    "value.converter.schemas.enable": "false"
}
EOF


sleep 5

log "Verify we have received the data in file"
docker exec connect cat /tmp/output.json
