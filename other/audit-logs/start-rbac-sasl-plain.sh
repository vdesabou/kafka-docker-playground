#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if ! version_gt $TAG_BASE "5.3.99"; then
    logwarn "Audit logs is only available from Confluent Platform 5.4.0"
    exit 111
fi

playground start-environment --environment rbac-sasl-plain --docker-compose-override-file "${PWD}/docker-compose.rbac-sasl-plain.yml"

sleep 10

log "Checking messages from topic confluent-audit-log-events"
docker exec -e KAFKA_DEBUG="" -i connect  kafka-console-consumer --bootstrap-server broker:9092 --topic confluent-audit-log-events --consumer.config /etc/kafka/secrets/client_without_interceptors.config --from-beginning --max-messages 5