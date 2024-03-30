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

connector_name="HttpSource_$USER"
set +e
playground connector delete --connector $connector_name > /dev/null 2>&1
set -e

log "Creating fully managed connector"
playground connector create-or-update --connector $connector_name << EOF
{
     "connector.class": "HttpSource",
     "name": "$connector_name",
     "kafka.auth.mode": "KAFKA_API_KEY",
     "kafka.api.key": "$CLOUD_KEY",
     "kafka.api.secret": "$CLOUD_SECRET",
     "topic.name.pattern": "http-topic",
     "output.data.format": "AVRO",
     "url": "http://$NGROK_HOSTNAME:$NGROK_PORT/api/messages",
     "entity.names": "AppName,User",
     "tasks.max" : "1",
     "auth.type": "oauth2",
     "oauth2.token.url": "http://$NGROK_HOSTNAME:$NGROK_PORT/oauth/token",
     "oauth2.client.id": "kc-client",
     "oauth2.client.secret": "kc-secret",
     "oauth2.client.mode": "header",
     "http.offset.mode": "SIMPLE_INCREMENTING",
     "http.initial.offset": "0"
}
EOF
wait_for_ccloud_connector_up $connector_name 300

# create token, see https://github.com/confluentinc/kafka-connect-http-demo#oauth2
token=$(curl -X POST \
  http://localhost:18080/oauth/token \
  -H 'Content-Type: application/x-www-form-urlencoded' \
  -H 'Authorization: Basic a2MtY2xpZW50OmtjLXNlY3JldA==' \
  -d 'grant_type=client_credentials&scope=any' | jq -r '.access_token')


log "Send a message to HTTP server"
curl -X PUT \
     -H "Content-Type: application/json" \
     -H "Authorization: Bearer ${token}" \
     --data '{"test":"value"}' \
     http://localhost:18080/api/messages | jq .


sleep 2

log "Verify we have received the data in http-topic topic"
playground topic consume --topic http-topic --min-expected-messages 1 --timeout 60


log "Do you want to delete the fully managed connector $connector_name ?"
check_if_continue

playground connector delete --connector $connector_name
