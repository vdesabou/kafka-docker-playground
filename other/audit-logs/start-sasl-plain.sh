#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if ! version_gt $TAG_BASE "5.3.99"; then
    logwarn "WARN: Audit logs is only available from Confluent Platform 5.4.0"
    exit 111
fi

playground start-environment --environment sasl-plain --docker-compose-override-file "${PWD}/docker-compose.sasl-plain.yml"

sleep 10

log "Checking messages from topic confluent-audit-log-events"
docker exec -i connect kafka-console-consumer --bootstrap-server broker:9092 --topic confluent-audit-log-events --consumer.config /tmp/client.properties --from-beginning --max-messages 5