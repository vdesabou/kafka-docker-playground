#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if ! version_gt $TAG_BASE "5.3.2"; then
    logwarn "WARN: Audit logs is only available from Confluent Platform 5.4.0"
    exit 0
fi

${DIR}/../../environment/rbac-sasl-plain/start.sh "${PWD}/docker-compose.yml"

sleep 10

log "Checking messages from topic confluent-audit-log-events"
docker exec -i connect kafka-console-consumer --bootstrap-server broker:9092 --topic confluent-audit-log-events --consumer.config /etc/kafka/secrets/client_sasl_plain.config --from-beginning --max-messages 5