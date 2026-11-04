#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

NGROK_AUTH_TOKEN=${NGROK_AUTH_TOKEN:-$1}

display_ngrok_warning

bootstrap_ccloud_environment


docker compose -f docker-compose.yml build
docker compose -f docker-compose.yml down -v --remove-orphans
docker compose -f docker-compose.yml up -d --quiet-pull

sleep 5

get_ngrok_url

set +e
playground topic delete --topic http-topic-spaces
set -e

log "Creating http-topic-spaces topic in Confluent Cloud"
set +e
playground topic create --topic http-topic-spaces
set -e

connector_name="HttpSourceV2_$USER"
set +e
playground connector delete --connector $connector_name > /dev/null 2>&1
set -e

log "Creating fully managed connector"
playground connector create-or-update --connector $connector_name << EOF
{
    "connector.class": "HttpSourceV2",
    "name": "$connector_name",
    "kafka.auth.mode": "KAFKA_API_KEY",
    "kafka.api.key": "$CLOUD_KEY",
    "kafka.api.secret": "$CLOUD_SECRET",
    "output.data.format": "AVRO",
    "tasks.max" : "1",

    "http.api.base.url": "http://$NGROK_HOSTNAME:$NGROK_PORT",
    "behavior.on.error": "FAIL",

    "apis.num": "1",
    "api1.http.api.path": "/wiki/rest/api/space",
    "api1.topics": "http-topic-spaces",
    "api1.http.request.headers": "Content-Type: application/json",
    "api1.test.api": "false",

    "api1.http.offset.mode": "SIMPLE_INCREMENTING",
    "api1.http.request.parameters": "start=\${offset}&limit=1",
    "api1.http.initial.offset": "0",
    "api1.http.response.data.json.pointer": "/results",
    "api1.request.interval.ms": "1000"
}
EOF
wait_for_ccloud_connector_up $connector_name 180


sleep 10

log "Verify we have received the initial spaces in http-topic-spaces topic (expecting at least 15 spaces, 1 per page)"
playground topic consume --topic http-topic-spaces --min-expected-messages 15 --timeout 60


log "Do you want to delete the fully managed connector $connector_name ?"
check_if_continue

playground connector delete --connector $connector_name
