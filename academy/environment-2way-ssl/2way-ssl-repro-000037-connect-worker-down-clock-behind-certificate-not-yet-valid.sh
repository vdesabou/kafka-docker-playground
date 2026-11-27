#!/bin/bash
set -e
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

# this exercise is about TLS (mutual TLS between all the components): it needs the 2way-ssl environment
playground start-environment --environment 2way-ssl --docker-compose-override-file "${PWD}/docker-compose.2way-ssl.repro-000037-connect-worker-down-clock-behind-certificate-not-yet-valid.yml"

playground topic produce -t payments --nb-messages 3 --forced-value '{"payment": %g}'

log "Creating the FileStream sink connector"
playground connector create-or-update --connector filestream-sink << EOF2
{
     "tasks.max": "1",
     "connector.class": "org.apache.kafka.connect.file.FileStreamSinkConnector",
     "topics": "payments",
     "file": "/tmp/output.json",
     "key.converter": "org.apache.kafka.connect.storage.StringConverter",
     "value.converter": "org.apache.kafka.connect.storage.StringConverter"
}
EOF2

# the date the certificate of the broker starts to be valid (the environment creates its certificates at its first start)
not_before=$(playground --output-level ERROR container exec -c broker --command "keytool -list -v -keystore /etc/kafka/secrets/kafka.broker.keystore.jks -storepass confluent 2>/dev/null | grep -m1 'Valid from' | sed -e 's/^Valid from: //' -e 's/ until:.*//'")
behind=$(playground --output-level ERROR container exec -c broker --command "date -u -d '$not_before - 2 days' '+%Y-%m-%d %H:%M:%S'" | tail -1)
log "The certificate of the broker is valid from $not_before"

# 💥 the host of the worker was swapped during the night: no NTP, its clock is two days before that date
log "🔧 Night maintenance: the Connect worker comes back on new hardware"
playground debug clock -c connect --at "$behind" || true

sleep 30
playground connector status --connector filestream-sink || true
