#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

bootstrap_ccloud_environment

if [ -f /tmp/delta_configs/env.delta ]
then
     source /tmp/delta_configs/env.delta
else
     logerror "ERROR: /tmp/delta_configs/env.delta has not been generated"
     exit 1
fi

docker-compose -f docker-compose.noauth.yml build
docker-compose -f docker-compose.noauth.yml down -v --remove-orphans
docker-compose -f docker-compose.noauth.yml up -d

sleep 5

log "Getting ngrok hostname and port"
NGROK_URL=$(curl --silent http://127.0.0.1:4551/api/tunnels | jq -r '.tunnels[0].public_url')
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

connector_name="HttpSink"
set +e
log "Deleting fully managed connector $connector_name, it might fail..."
playground ccloud-connector delete --connector $connector_name
set -e

log "Set webserver to reply with 200"
curl -X PUT -H "Content-Type: application/json" --data '{"errorCode": 200}' http://localhost:9006

log "Creating fully managed connector"
playground ccloud-connector create-or-update --connector $connector_name << EOF
{
     "connector.class": "HttpSink",
     "name": "HttpSink",
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
wait_for_ccloud_connector_up $connector_name 300


connectorId=$(get_ccloud_connector_lcc $connector_name)

log "Verifying topic success-$connectorId"
playground topic consume --topic success-$connectorId --min-expected-messages 10 --timeout 60

log "Do you want to delete the fully managed connector $connector_name ?"
check_if_continue

playground ccloud-connector delete --connector $connector_name
