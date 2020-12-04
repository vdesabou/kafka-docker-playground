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

if [ -z "$KSQLDB" ]
then
     ${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"
else
     ${DIR}/../../ksqldb/environment/start.sh "${PWD}/docker-compose.plaintext.yml"
fi

SINCE="2020-09-05"

log "Creating Zendesk Source connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
                    "connector.class": "io.confluent.connect.zendesk.ZendeskSourceConnector",
                    "topic.name.pattern":"zendesk-topic-${entityName}",
                    "tasks.max": "1",
                    "poll.interval.ms": 1000,
                    "zendesk.auth.type": "basic",
                    "zendesk.url": "'"$ZENDESK_URL"'",
                    "zendesk.user": "'"$ZENDESK_USERNAME"'",
                    "zendesk.password": "'"$ZENDESK_PASSWORD"'",
                    "zendesk.tables": "tickets",
                    "zendesk.since": "'"$SINCE"'",
                    "key.converter": "org.apache.kafka.connect.storage.StringConverter",
                    "value.converter": "org.apache.kafka.connect.json.JsonConverter",
                    "value.converter.schemas.enable": "false",
                    "confluent.license": "",
                    "confluent.topic.bootstrap.servers": "broker:9092",
                    "confluent.topic.replication.factor": "1",
                    "errors.tolerance": "all",
                    "errors.log.enable": true,
                    "errors.log.include.messages": true
          }' \
     http://localhost:8083/connectors/zendesk-source/config | jq .


sleep 10

log "Verify we have received the data in zendesk-topic-tickets topic"
timeout 60 docker exec broker kafka-console-consumer -bootstrap-server broker:9092 --topic zendesk-topic-tickets --from-beginning --max-messages 1