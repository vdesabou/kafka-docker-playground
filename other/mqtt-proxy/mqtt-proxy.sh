#!/bin/bash
set -e


DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

playground start-environment --environment plaintext --docker-compose-override-file "${PWD}/docker-compose.plaintext.yml"


log "Send message to MQTT in car/engine/temperature topic"
docker exec mosquitto sh -c 'mosquitto_pub -h mqtt-proxy -p 1883 -t "car/engine/temperature" -q 2 -m "190F"'

sleep 5

log "Verify we have received the data in temperature topic"
playground topic consume --topic temperature --min-expected-messages 1 --timeout 60