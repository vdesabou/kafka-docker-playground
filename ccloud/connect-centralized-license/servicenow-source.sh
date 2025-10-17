#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh


SERVICENOW_URL=${SERVICENOW_URL:-$1}
SERVICENOW_PASSWORD=${SERVICENOW_PASSWORD:-$2}

if [ -z "$SERVICENOW_URL" ]
then
     logerror "SERVICENOW_URL is not set. Export it as environment variable or pass it as argument"
     exit 1
fi

if [[ "$SERVICENOW_URL" != */ ]]
then
    logerror "SERVICENOW_URL does not end with "/" Example: https://dev12345.service-now.com/ "
    exit 1
fi

if [ -z "$SERVICENOW_PASSWORD" ]
then
     logerror "SERVICENOW_PASSWORD is not set. Export it as environment variable or pass it as argument"
     exit 1
fi

if [ ! -z "$GITHUB_RUN_NUMBER" ]
then
     # this is github actions
     set +e
     log "Waking up servicenow instance..."
     docker run -e USERNAME="$SERVICENOW_DEVELOPER_USERNAME" -e PASSWORD="$SERVICENOW_DEVELOPER_PASSWORD" vdesabou/servicenowinstancewakeup:latest
     set -e
     wait_for_end_of_hibernation
fi

set +e
playground topic delete --topic _confluent-command
set -e

playground start-environment --environment ccloud --docker-compose-override-file "${PWD}/docker-compose.servicenow-source.yml"


#############

if ! version_gt $TAG_BASE "5.9.9"; then
     # note: for 6.x CONNECT_TOPIC_CREATION_ENABLE=true
     log "Creating topic in Confluent Cloud (auto.create.topics.enable=false)"
     set +e
     playground topic create --topic topic-servicenow
     set -e
fi

TODAY=$(date -u '+%Y-%m-%d')

log "Creating ServiceNow Source connector"
playground connector create-or-update --connector servicenow-source  << EOF
{
     "connector.class": "io.confluent.connect.servicenow.ServiceNowSourceConnector",
     "kafka.topic": "topic-servicenow",
     "servicenow.url": "$SERVICENOW_URL",
     "tasks.max": "1",
     "servicenow.table": "incident",
     "servicenow.user": "admin",
     "servicenow.password": "$SERVICENOW_PASSWORD",
     "servicenow.since": "$TODAY",
     "topic.creation.default.replication.factor": "-1",
     "topic.creation.default.partitions": "-1",
     "key.converter": "org.apache.kafka.connect.json.JsonConverter",
     "value.converter": "org.apache.kafka.connect.json.JsonConverter"
}
EOF

sleep 10

log "Create one record to ServiceNow"
curl -X POST \
    "${SERVICENOW_URL}/api/now/table/incident" \
    --user admin:"$SERVICENOW_PASSWORD" \
    -H 'Accept: application/json' \
    -H 'Content-Type: application/json' \
    -H 'cache-control: no-cache' \
    -d '{"short_description": "This is test"}'

sleep 5

log "Verify we have received the data in topic-servicenow topic"
playground topic consume --topic topic-servicenow --min-expected-messages 1 --max-messages 3 --timeout 60

