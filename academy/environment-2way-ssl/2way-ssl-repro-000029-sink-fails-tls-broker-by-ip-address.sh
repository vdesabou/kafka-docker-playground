#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

# this exercise is about TLS (mutual TLS between all the components): it needs the 2way-ssl environment
playground start-environment --environment 2way-ssl --docker-compose-override-file "${PWD}/docker-compose.2way-ssl.repro-000029-sink-fails-tls-broker-by-ip-address.yml"

playground topic produce -t payments --nb-messages 3 --forced-value '{"payment": %g}'

# the customer config: "the DNS of the new data center is not ready yet, use the IP address of the broker"
broker_ip=$(playground --output-level ERROR container exec -c connect --command "getent hosts broker" | awk '{print $1}' | tail -1)
log "The broker is at $broker_ip"

log "Creating the FileStream sink connector"
set +e
playground connector create-or-update --connector filestream-sink << EOF
{
     "tasks.max": "1",
     "connector.class": "org.apache.kafka.connect.file.FileStreamSinkConnector",
     "topics": "payments",
     "file": "/tmp/output.json",
     "key.converter": "org.apache.kafka.connect.storage.StringConverter",
     "value.converter": "org.apache.kafka.connect.storage.StringConverter",
     "consumer.override.bootstrap.servers": "$broker_ip:9092"
}
EOF
set -e

sleep 30
playground connector status --connector filestream-sink || true
