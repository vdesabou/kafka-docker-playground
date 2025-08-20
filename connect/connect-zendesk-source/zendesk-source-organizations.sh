#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if connect_cp_version_greater_than_8 && [ ! -z "$CONNECTOR_TAG" ] && ! version_gt $CONNECTOR_TAG "1.2.99"
then
     logwarn "minimal supported connector version is 1.3.0 for CP 8.0"
     logwarn "see https://docs.confluent.io/platform/current/connect/supported-connector-version-8.0.html#supported-connector-versions-in-cp-8-0"
     exit 111
fi

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

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.yml"

SINCE="2020-09-05"

log "Creating Zendesk Source connector"
playground connector create-or-update --connector zendesk-source  << EOF
{
     "connector.class": "io.confluent.connect.zendesk.ZendeskSourceConnector",
     "topic.name.pattern":"zendesk-topic-\${entityName}",
     "tasks.max": "1",
     "poll.interval.ms": 1000,
     "zendesk.auth.type": "basic",
     "zendesk.url": "$ZENDESK_URL",
     "zendesk.user": "$ZENDESK_USERNAME",
     "zendesk.password": "$ZENDESK_PASSWORD",
     "zendesk.tables": "organizations",
     "zendesk.since": "$SINCE",
     "key.converter": "org.apache.kafka.connect.storage.StringConverter",
     "value.converter": "org.apache.kafka.connect.json.JsonConverter",
     "value.converter.schemas.enable": "false",
     "confluent.license": "",
     "confluent.topic.bootstrap.servers": "broker:9092",
     "confluent.topic.replication.factor": "1",
     "errors.tolerance": "all",
     "errors.log.enable": true,
     "errors.log.include.messages": true
}
EOF


sleep 10

log "Verify we have received the data in zendesk-topic-organizations topic"
playground topic consume --topic zendesk-topic-organizations --min-expected-messages 1 --timeout 60