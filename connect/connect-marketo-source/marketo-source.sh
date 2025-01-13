#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

cd ../../connect/connect-marketo-source/
if [ ! -f jcl-over-slf4j-2.0.7.jar ]
then
     wget -q https://repo1.maven.org/maven2/org/slf4j/jcl-over-slf4j/2.0.7/jcl-over-slf4j-2.0.7.jar
fi
cd -

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

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.yml"

log "Creating an access token"
ACCESS_TOKEN=$(docker exec connect \
   curl -s -X GET \
    "${MARKETO_ENDPOINT_URL}/identity/oauth/token?grant_type=client_credentials&client_id=$MARKETO_CLIENT_ID&client_secret=$MARKETO_CLIENT_SECRET" | jq -r .access_token)

log "Create 3 leads to Marketo"
for((i=0;i<3;i++))
do
     LEAD_FIRSTNAME="John_$RANDOM_${i}"
     LEAD_LASTNAME="Doe_$RANDOM_${i}"

     log "Lead: $LEAD_FIRSTNAME $LEAD_LASTNAME"
     docker exec connect \
     curl -s -X POST \
     "${MARKETO_ENDPOINT_URL}/rest/v1/leads.json?access_token=$ACCESS_TOKEN" \
     -H 'Accept: application/json' \
     -H 'Content-Type: application/json' \
     -H 'cache-control: no-cache' \
     -d "{ \"action\":\"createOrUpdate\", \"lookupField\":\"email\", \"input\":[ { \"lastName\":\"$LEAD_LASTNAME\", \"firstName\":\"$LEAD_FIRSTNAME\", \"middleName\":null, \"email\":\"$LEAD_FIRSTNAME.$LEAD_LASTNAME@email.com\" } ]}"
done

if [[ "$OSTYPE" == "darwin"* ]]
then
     SINCE=$(date -v-8H  +%Y-%m-%dT%H:%M:%SZ)
else
     SINCE=$(date -d '8 hour ago'  +%Y-%m-%dT%H:%M:%SZ)
fi

# playground debug log-level set --package "org.apache.http" --level TRACE

playground topic create --topic marketo_leads

log "Creating Marketo Source connector"
playground connector create-or-update --connector marketo-source  << EOF
{
     "connector.class": "io.confluent.connect.marketo.MarketoSourceConnector",
     "tasks.max": "1",
     "poll.interval.ms": 1000,
     "topic.name.pattern": "marketo_\${entityName}",
     "marketo.url": "$MARKETO_ENDPOINT_URL",
     "marketo.since": "$SINCE",
     "entity.names": "leads",
     "oauth2.client.id": "$MARKETO_CLIENT_ID",
     "oauth2.client.secret": "$MARKETO_CLIENT_SECRET",
     "key.converter": "org.apache.kafka.connect.storage.StringConverter",
     "value.converter": "org.apache.kafka.connect.json.JsonConverter",
     "value.converter.schemas.enable": "false",
     "confluent.license": "",
     "confluent.topic.bootstrap.servers": "broker:9092",
     "confluent.topic.replication.factor": "1"
}
EOF

sleep 10

log "Verify we have received the data in marketo_leads topic"
playground topic consume --topic marketo_leads --min-expected-messages 1 --timeout 600