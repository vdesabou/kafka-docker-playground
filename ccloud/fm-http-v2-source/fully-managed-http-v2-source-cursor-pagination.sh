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
playground topic delete --topic http-source-topic-v2
set -e

log "Creating http-source-topic-v2 topic in Confluent Cloud"
set +e
playground topic create --topic http-source-topic-v2
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
    "api1.http.api.path": "/storage/v1/b/test-bucket/o",
    "api1.topics": "http-source-topic-v2",
    "api1.http.request.headers": "Content-Type: application/json",
    "api1.test.api": "false",

    "api1.http.offset.mode": "CURSOR_PAGINATION",
    "api1.http.request.method": "GET",
    "api1.http.request.parameters": "pageToken=\${offset}",
    "api1.http.response.data.json.pointer": "/items",
    "api1.http.next.page.json.pointer": "/nextPageToken",
    "api1.request.interval.ms": "1000"
}
EOF
wait_for_ccloud_connector_up $connector_name 180


log "Verify we have received the data in http-source-topic-v2 topic (expecting 15 messages across 3 pages)"
playground topic consume --topic http-source-topic-v2 --min-expected-messages 15 --timeout 60


log "Do you want to delete the fully managed connector $connector_name ?"
check_if_continue

playground connector delete --connector $connector_name
