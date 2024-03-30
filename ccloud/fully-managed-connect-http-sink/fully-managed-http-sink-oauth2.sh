#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

NGROK_AUTH_TOKEN=${NGROK_AUTH_TOKEN:-$1}

display_ngrok_warning

bootstrap_ccloud_environment



docker compose -f docker-compose.oauth2.yml build
docker compose -f docker-compose.oauth2.yml down -v --remove-orphans
docker compose -f docker-compose.oauth2.yml up -d

sleep 5

log "Getting ngrok hostname and port"
NGROK_URL=$(curl --silent http://127.0.0.1:4040/api/tunnels | jq -r '.tunnels[0].public_url')
NGROK_HOSTNAME=$(echo $NGROK_URL | cut -d "/" -f3 | cut -d ":" -f 1)
NGROK_PORT=$(echo $NGROK_URL | cut -d "/" -f3 | cut -d ":" -f 2)

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
curl -X PUT -H "Content-Type: application/json" --data '{"errorCode": 200}' http://localhost:9006/set-response-error-code
# curl -X PUT -H "Content-Type: application/json" --data '{"delay": 2000}' http://localhost:9006/set-response-time
# curl -X PUT -H "Content-Type: application/json" --data '{"message":"Hello, World!"}' http://localhost:9006/set-response-body

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
  "auth.type": "OAUTH2",
  "oauth2.token.url": "http://$NGROK_HOSTNAME:$NGROK_PORT/oauth/token",
  "oauth2.client.id": "confidentialApplication",
  "oauth2.client.secret": "topSecret",
  "oauth2.token.property": "accessToken",
  "request.body.format" : "json",
  "headers": "Content-Type: application/json"
}
EOF
wait_for_ccloud_connector_up $connector_name 300

connectorId=$(get_ccloud_connector_lcc $connector_name)

log "Verifying topic success-$connectorId"
playground topic consume --topic success-$connectorId --min-expected-messages 10 --timeout 60

log "Do you want to delete the fully managed connector $connector_name ?"
check_if_continue

playground connector delete --connector $connector_name


# create token, see https://github.com/pedroetb/node-oauth2-server-example#with-client_credentials-grant-1
# token=$(curl -X POST \
#   http://localhost:9006/oauth/token \
#   -H 'Content-Type: application/x-www-form-urlencoded' \
#   -H 'Authorization: Basic Y29uZmlkZW50aWFsQXBwbGljYXRpb246dG9wU2VjcmV0' \
#   -d 'grant_type=client_credentials&scope=any' | jq -r '.accessToken')