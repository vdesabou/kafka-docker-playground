#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

NGROK_AUTH_TOKEN=${NGROK_AUTH_TOKEN:-$1}

display_ngrok_warning

bootstrap_ccloud_environment



docker compose -f docker-compose.noauth.yml build
docker compose -f docker-compose.noauth.yml down -v --remove-orphans
docker compose -f docker-compose.noauth.yml up -d --quiet-pull

sleep 5

get_ngrok_url

set +e
playground topic delete --topic http-topic
set -e

log "Creating http-topic topic in Confluent Cloud"
set +e
playground topic create --topic http-topic
set -e

log "Sending messages to topic http-topic"
playground topic produce -t http-topic --nb-messages 10 --forced-value '{"f1":"value%g"}' << 'EOF'
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

connector_name="HttpSink_$USER"
set +e
playground connector delete --connector $connector_name > /dev/null 2>&1
set -e

log "Set webserver to reply with 200"
playground tools http-server set-response --status-code 200
# playground tools http-server set-response --delay 2000
# playground tools http-server set-response --body '{"message":"Hello, World!"}'

log "Creating fully managed connector"
playground connector create-or-update --connector $connector_name << EOF
{
  "connector.class": "HttpSink",
  "name": "$connector_name",
  "kafka.auth.mode": "KAFKA_API_KEY",
  "kafka.api.key": "$CLOUD_KEY",
  "kafka.api.secret": "$CLOUD_SECRET",
  "topics": "http-topic",
  "input.data.format": "AVRO",
  "http.api.url": "http://$NGROK_HOSTNAME:$NGROK_PORT",
  "tasks.max" : "1",
  "request.body.format" : "json",
  "headers": "Content-Type: application/json"
}
EOF
wait_for_ccloud_connector_up $connector_name 180


connectorId=$(get_ccloud_connector_lcc $connector_name)

log "Verifying topic success-$connectorId"
playground topic consume --topic success-$connectorId --min-expected-messages 10 --timeout 60

log "Do you want to delete the fully managed connector $connector_name ?"
check_if_continue

playground connector delete --connector $connector_name
