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
playground topic delete --topic http-topic-messages
set -e

log "Creating http-topic-messages topic in Confluent Cloud"
set +e
playground topic create --topic http-topic-messages
set -e

connector_name="HttpSource_$USER"
set +e
playground connector delete --connector $connector_name > /dev/null 2>&1
set -e

# log "Set webserver to reply with 200"
# playground tools http-server set-response --status-code 200
# playground tools http-server set-response --delay 2000


log "Creating fully managed connector"
playground connector create-or-update --connector $connector_name << EOF
{
    "connector.class": "HttpSource",
    "name": "$connector_name",
    "kafka.auth.mode": "KAFKA_API_KEY",
    "kafka.api.key": "$CLOUD_KEY",
    "kafka.api.secret": "$CLOUD_SECRET",
    "tasks.max" : "1",
    "output.data.format": "AVRO",
    "topic.name.pattern":"http-topic-\${entityName}",
    "entity.names": "messages",
    "url": "http://$NGROK_HOSTNAME:$NGROK_PORT/test-index/_search",
    "http.offset.mode": "CHAINING",
    "http.request.method": "POST",
    "http.request.body": "{\\"size\\": 100, \\"sort\\": [{\\"@time\\": \\"asc\\"}], \\"search_after\\": [\${offset}]}",
    "http.initial.offset": "1647948000000",
    "http.response.data.json.pointer": "/hits/hits",
    "http.offset.json.pointer": "/sort/0",
    "request.interval.ms": "5000"
}
EOF
wait_for_ccloud_connector_up $connector_name 180

log "Wait 5 seconds for connector to start and fetch initial batch"
sleep 5

playground topic consume --topic http-topic-messages --min-expected-messages 3 --timeout 10


log "Do you want to delete the fully managed connector $connector_name ?"
check_if_continue

playground connector delete --connector $connector_name
