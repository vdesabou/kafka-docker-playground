#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

MARKETO_ENDPOINT_URL=${MARKETO_ENDPOINT_URL:-$1}
MARKETO_CLIENT_ID=${MARKETO_CLIENT_ID:-$2}
MARKETO_CLIENT_SECRET=${MARKETO_CLIENT_SECRET:-$3}

if [ -z "$MARKETO_ENDPOINT_URL" ]
then
     logerror "MARKETO_ENDPOINT_URL is not set. Export it as environment variable or pass it as argument"
     exit 1
fi

if [[ "$MARKETO_ENDPOINT_URL" = *rest ]]
then
    logerror "MARKETO_ENDPOINT_URL should not end with "rest" Example: https://<instance-id>.mktorest.com/ "
    exit 1
fi

if [ -z "$MARKETO_CLIENT_ID" ]
then
     logerror "MARKETO_CLIENT_ID is not set. Export it as environment variable or pass it as argument"
     exit 1
fi

if [ -z "$MARKETO_CLIENT_SECRET" ]
then
     logerror "MARKETO_CLIENT_SECRET is not set. Export it as environment variable or pass it as argument"
     exit 1
fi

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"

log "Creating an access token"
ACCESS_TOKEN=$(docker exec connect \
   curl -X GET \
    "${MARKETO_ENDPOINT_URL}/identity/oauth/token?grant_type=client_credentials&client_id=$MARKETO_CLIENT_ID&client_secret=$MARKETO_CLIENT_SECRET" | jq -r .access_token)

log "Create one lead to Marketo"
docker exec connect \
   curl -X POST \
    "${MARKETO_ENDPOINT_URL}/rest/v1/leads.json?access_token=$ACCESS_TOKEN" \
    -H 'Accept: application/json' \
    -H 'Content-Type: application/json' \
    -H 'cache-control: no-cache' \
    -d '{ "action":"createOrUpdate", "lookupField":"email", "input":[ { "lastName":"john", "firstName":"doe", "middleName":null, "email":"john.doe@email.com" } ]}'

# since last hour

if [[ "$OSTYPE" == "darwin"* ]]
then
     SINCE=$(date -v-1H  +%Y-%m-%dT%H:%M:%SZ)
else
     SINCE=$(date -d '1 hour ago'  +%Y-%m-%dT%H:%M:%SZ)
fi

log "Creating Marketo Source connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
                    "connector.class": "io.confluent.connect.marketo.MarketoSourceConnector",
                    "tasks.max": "1",
                    "poll.interval.ms": 1000,
                    "topic.name.pattern": "marketo_${entityName}",
                    "marketo.url": "'"$MARKETO_ENDPOINT_URL"'",
                    "marketo.since": "'"$SINCE"'",
                    "entity.names": "leads",
                    "oauth2.client.id": "'"$MARKETO_CLIENT_ID"'",
                    "oauth2.client.secret": "'"$MARKETO_CLIENT_SECRET"'",
                    "key.converter": "org.apache.kafka.connect.storage.StringConverter",
                    "value.converter": "org.apache.kafka.connect.json.JsonConverter",
                    "value.converter.schemas.enable": "false",
                    "confluent.license": "",
                    "confluent.topic.bootstrap.servers": "broker:9092",
                    "confluent.topic.replication.factor": "1"
          }' \
     http://localhost:8083/connectors/marketo-source/config | jq .

log "Sleeping 5 minutes (leads are pulled with a delay of 5 minutes between consecutive pulls)"
sleep 300

log "Verify we have received the data in marketo_leads topic"
timeout 60 docker exec connect kafka-console-consumer -bootstrap-server broker:9092 --topic marketo_leads --from-beginning --max-messages 1