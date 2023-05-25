#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if ! version_gt $TAG_BASE "5.3.99"; then
    logwarn "WARN: Audit logs is only available from Confluent Platform 5.4.0"
    exit 111
fi

${DIR}/../../environment/sasl-plain/start.sh "${PWD}/docker-compose.sasl-plain.yml"

sleep 10

log "Checking messages from topic confluent-audit-log-events"
playground topic consume --topic confluent-audit-log-events --min-expected-messages 5 --timeout 60