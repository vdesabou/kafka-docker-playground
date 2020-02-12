#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml" -a

log "Sleep 60 seconds"
sleep 60

log "Verify we have received the data in syslog topic"
docker exec broker kafka-console-consumer --bootstrap-server broker:9092 --topic topic-log --from-beginning --max-messages 100