#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"

if [ -z "$CONNECTOR_ZIP" ]
then
    HTTP_V2_CONNECTOR_ZIP="confluentinc-kafka-connect-http-v2-0.1.0-rc-acd8307-cloud.zip"
    export CONNECTOR_ZIP="$PWD/$HTTP_V2_CONNECTOR_ZIP"
fi

source ${DIR}/../../scripts/cli/src/lib/utils_function.sh

if [ ! -z "$HTTP_V2_CONNECTOR_ZIP" ]
then
    get_3rdparty_file "$HTTP_V2_CONNECTOR_ZIP"

    if [ ! -f ${PWD}/$HTTP_V2_CONNECTOR_ZIP ]
    then
        logerror "ERROR: ${PWD}/$HTTP_V2_CONNECTOR_ZIP is missing. You must be a Confluent Employee to run this example !"
        exit 1
    fi
fi

source ${DIR}/../../scripts/utils.sh

cd ../../connect/connect-http-v2-sink/
if [ ! -f jcl-over-slf4j-2.0.7.jar ]
then
     wget -q https://repo1.maven.org/maven2/org/slf4j/jcl-over-slf4j/2.0.7/jcl-over-slf4j-2.0.7.jar
fi
cd -

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.oauth2.yml"


log "Sending messages to topic http-messages"
playground topic produce -t http-messages --nb-messages 10 << 'EOF'
{
    "_meta": {
        "topic": "",
        "key": "",
        "relationships": []
    },
    "nested": {
        "phone": "faker.phone.imei()",
        "website": "faker.internet.domainName()"
    },
    "id": "iteration.index",
    "name": "faker.internet.userName()",
    "email": "faker.internet.exampleEmail()",
    "phone": "faker.phone.imei()",
    "website": "faker.internet.domainName()",
    "city": "faker.location.city()",
    "company": "faker.company.name()"
}
EOF

playground debug log-level set --package "org.apache.http" --level TRACE

log "Set webserver to reply with 200"
curl -X PUT -H "Content-Type: application/json" --data '{"errorCode": 200}' http://localhost:9006/set-response-error-code
# curl -X PUT -H "Content-Type: application/json" --data '{"delay": 2000}' http://localhost:9006/set-response-time
# curl -X PUT -H "Content-Type: application/json" --data '{"message":"Hello, World!"}' http://localhost:9006/set-response-body

log "Creating http-sink connector"
playground connector create-or-update --connector http-sink  << EOF
{
    "tasks.max": "1",

    "confluent.topic.bootstrap.servers": "broker:9092",
    "confluent.topic.replication.factor": "1",
    "reporter.bootstrap.servers": "broker:9092",
    "reporter.error.topic.name": "error-responses",
    "reporter.error.topic.replication.factor": 1,
    "reporter.result.topic.name": "success-responses",
    "reporter.result.topic.replication.factor": 1,
    "reporter.result.topic.value.format": "string",

    "value.converter":"org.apache.kafka.connect.json.JsonConverter",
    "value.converter.schemas.enable":"false",

    "connector.class": "io.confluent.connect.http.sink.GenericHttpSinkConnector",
    "topics": "http-messages",

    "http.api.base.url": "http://httpserver:9006",

    "connection.disallow.local.ips": "false",
    "connection.disallow.private.ips": "false",

    "_api1.http.request.method": "POST",
    "_api1.http.request.timeout.ms": "5000",
    "_api1.max.retries": "3",
    "_api1.retry.backoff.ms": "300",
    "_api1.retry.on.status.codes": "400,401,402,403,405-500",
    "_max.poll.records": "50",
    "apis.num": "1",
    "api1.http.api.path": "/",
    "api1.topics": "http-messages",
    "api1.request.body.format" : "JSON",
    "api1.http.request.headers": "Content-Type: application/json",
    "api1.test.api": "false",

    "auth.type": "OAUTH2",
    "oauth2.token.url": "http://httpserver:9006/oauth/token",
    "oauth2.client.id": "confidentialApplication",
    "oauth2.client.secret": "topSecret",
    "oauth2.token.property": "accessToken"
}
EOF


sleep 10

# create token, see https://github.com/pedroetb/node-oauth2-server-example#with-client_credentials-grant-1
# token=$(curl -X POST \
#   http://localhost:9006/oauth/token \
#   -H 'Content-Type: application/x-www-form-urlencoded' \
#   -H 'Authorization: Basic Y29uZmlkZW50aWFsQXBwbGljYXRpb246dG9wU2VjcmV0' \
#   -d 'grant_type=client_credentials&scope=any' | jq -r '.accessToken')

# "oauth2.client.auth.mode": "headers"
# [2023-09-17T07:50:23.898Z] POST to /oauth/token
# headers:
# {
#   authorization: 'Basic Y29uZmlkZW50aWFsQXBwbGljYXRpb246dG9wU2VjcmV0',
#   'content-type': 'application/x-www-form-urlencoded',
#   'content-length': '39',
#   host: 'httpserver:9006',
#   connection: 'Keep-Alive',
#   'user-agent': 'Apache-HttpClient/4.5.13 (Java/11.0.20)',
#   'accept-encoding': 'gzip,deflate'
# }
# body:
# { grant_type: 'client_credentials', scope: 'any' }


# "oauth2.client.auth.mode": "url"
# [2023-09-17T07:48:00.625Z] POST to /oauth/token
# headers:
# {
#   'content-type': 'application/x-www-form-urlencoded',
#   'content-length': '97',
#   host: 'httpserver:9006',
#   connection: 'Keep-Alive',
#   'user-agent': 'Apache-HttpClient/4.5.13 (Java/11.0.20)',
#   'accept-encoding': 'gzip,deflate'
# }
# body:
# {
#   grant_type: 'client_credentials',
#   scope: 'any',
#   client_id: 'confidentialApplication',
#   client_secret: 'topSecret'
# }

playground topic consume --topic success-responses --min-expected-messages 10 --timeout 60
