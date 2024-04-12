#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

ZENDESK_URL=${ZENDESK_URL:-$1}
ZENDESK_USERNAME=${ZENDESK_USERNAME:-$2}
ZENDESK_PASSWORD=${ZENDESK_PASSWORD:-$3}

if [ -z "$ZENDESK_URL" ]
then
     logerror "ZENDESK_URL is not set. Export it as environment variable or pass it as argument"
     exit 1
fi

if [ -z "$ZENDESK_USERNAME" ]
then
     logerror "ZENDESK_USERNAME is not set. Export it as environment variable or pass it as argument"
     exit 1
fi

if [ -z "$ZENDESK_PASSWORD" ]
then
     logerror "ZENDESK_PASSWORD is not set. Export it as environment variable or pass it as argument"
     exit 1
fi

bootstrap_ccloud_environment

set +e
playground topic delete --topic zendesk-topic-organizations
set -e

playground topic create --topic zendesk-topic-organizations

connector_name="ZendeskSource_$USER"
set +e
playground connector delete --connector $connector_name > /dev/null 2>&1
set -e

log "Creating fully managed connector"
playground connector create-or-update --connector $connector_name << EOF
{
     "connector.class": "ZendeskSource",
     "name": "$connector_name",
     "kafka.auth.mode": "KAFKA_API_KEY",
     "kafka.api.key": "$CLOUD_KEY",
     "kafka.api.secret": "$CLOUD_SECRET",
     "output.data.format": "JSON",
     "zendesk.auth.type": "basic",
     "zendesk.url": "$ZENDESK_URL",
     "zendesk.user": "$ZENDESK_USERNAME",
     "zendesk.password": "$ZENDESK_PASSWORD",
     "zendesk.tables": "organizations",
     "zendesk.since": "2020-09-05",
     "topic.name.pattern":"zendesk-topic-\${entityName}",
     "tasks.max" : "1"
}
EOF
wait_for_ccloud_connector_up $connector_name 600

sleep 10

log "Verify we have received the data in zendesk-topic-organizations topic"
playground topic consume --topic zendesk-topic-organizations --min-expected-messages 1 --timeout 60

log "Do you want to delete the fully managed connector $connector_name ?"
check_if_continue

playground connector delete --connector $connector_name