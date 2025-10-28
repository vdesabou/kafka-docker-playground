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

cd ../../connect/connect-http-v2-sink/
if [ ! -f jcl-over-slf4j-2.0.7.jar ]
then
     wget -q https://repo1.maven.org/maven2/org/slf4j/jcl-over-slf4j/2.0.7/jcl-over-slf4j-2.0.7.jar
fi
cd -

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.yml"


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
curl -X PUT -H "Content-Type: application/json" --data '{"message":"Hello, World!"}' http://localhost:9006/set-response-body

# curl -X PUT -H "Content-Type: application/json" --data '{"delay": 2000}' http://localhost:9006/set-response-time

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

    "api1.http.request.method": "POST",
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
    "api1.test.api": "false"
}
EOF

sleep 10

log "Check the success-responses topic"
playground topic consume --topic success-responses --min-expected-messages 10 --timeout 60