#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"

if [ -z "$CONNECTOR_ZIP" ]
then
    HTTP_SOURCE_CONNECTOR_ZIP="confluentinc-kafka-connect-http-v2-0.1.0-SNAPSHOT.zip"
    export CONNECTOR_ZIP="$PWD/$HTTP_SOURCE_CONNECTOR_ZIP"
fi

source ${DIR}/../../scripts/utils.sh

if [ -z "$CONNECTOR_ZIP" ]
then
    get_3rdparty_file "$HTTP_SOURCE_CONNECTOR_ZIP"

    if [ ! -f ${PWD}/$HTTP_SOURCE_CONNECTOR_ZIP ]
    then
        logerror "ERROR: ${PWD}/$HTTP_SOURCE_CONNECTOR_ZIP is missing. You must be a Confluent Employee to run this example !"
        exit 1
    fi
fi

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.oauth2.yml"

log "Creating http-source connector"
playground connector create-or-update --connector http-source  << EOF
{
    "tasks.max": "1",
    "connector.class": "io.confluent.connect.http.source.GenericHttpSourceConnector",

    "http.api.base.url": "http://httpserver:8080",

    "connection.disallow.local.ips": "false",
    "connection.disallow.private.ips": "false",

    "apis.num": "1",
    "api1.http.api.path": "/",
    "api1.topics": "http-source-topic-v2",
    "api1.http.request.headers": "Content-Type: application/json",
    "api1.test.api": "false",
    "api1.http.offset.mode": "SIMPLE_INCREMENTING",
    "api1.http.initial.offset": "0",

    "auth.type": "OAUTH2",
    "oauth2.token.url": "http://httpserver:8080/oauth/token",
    "oauth2.client.id": "kc-client",
    "oauth2.client.secret": "kc-secret"
}
EOF

sleep 3

# create token, see https://github.com/confluentinc/kafka-connect-http-demo#oauth2
token=$(curl -X POST \
  http://localhost:18080/oauth/token \
  -H 'Content-Type: application/x-www-form-urlencoded' \
  -H 'Authorization: Basic a2MtY2xpZW50OmtjLXNlY3JldA==' \
  -d 'grant_type=client_credentials&scope=any' | jq -r '.access_token')


log "Send a message to HTTP server"
curl -X PUT \
     -H "Content-Type: application/json" \
     -H "Authorization: Bearer ${token}" \
     --data '{"test":"value"}' \
     http://localhost:18080/api/messages | jq .


sleep 2

log "Verify we have received the data in http-source-topic-v2 topic"
playground topic consume --topic http-source-topic-v2 --min-expected-messages 1 --timeout 60
