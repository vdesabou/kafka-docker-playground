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

cd ../../connect/connect-http-v2-source/
if [ ! -f jcl-over-slf4j-2.0.7.jar ]
then
     wget -q https://repo1.maven.org/maven2/org/slf4j/jcl-over-slf4j/2.0.7/jcl-over-slf4j-2.0.7.jar
fi
cd -

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.simple-incrementing.yml"

playground debug log-level set --package "org.apache.http" --level TRACE

log "Creating http-source connector (SIMPLE_INCREMENTING) for Confluence spaces with dynamic growth"
playground connector create-or-update --connector http-source  << EOF
{
    "tasks.max": "1",
    "connector.class": "io.confluent.connect.http.source.GenericHttpSourceConnector",

    "connection.disallow.local.ips": "false",
    "connection.disallow.private.ips": "false",

    "http.api.base.url": "http://httpserver:9006",

    "apis.num": "1",
    "api1.http.api.path": "/wiki/rest/api/space",
    "api1.topics": "http-topic-spaces",
    "api1.http.request.headers": "Content-Type: application/json",
    "api1.test.api": "false",

    "api1.http.offset.mode": "SIMPLE_INCREMENTING",
    "api1.http.request.parameters": "start=\${offset}&limit=1",
    "api1.http.initial.offset": "0",
    "api1.http.response.data.json.pointer": "/results",
    "api1.request.interval.ms": "1000",

    "reporter.bootstrap.servers": "broker:9092",
    "reporter.error.topic.name": "error-responses",
    "reporter.error.topic.replication.factor": 1,
    "reporter.result.topic.name": "success-responses",
    "reporter.result.topic.replication.factor": 1,
    "reporter.result.topic.value.format": "string"
}
EOF

sleep 10

log "Verify we have received the initial spaces in http-topic-spaces topic (expecting at least 15 spaces, 1 per page)"
playground topic consume --topic http-topic-spaces --min-expected-messages 15 --timeout 60
