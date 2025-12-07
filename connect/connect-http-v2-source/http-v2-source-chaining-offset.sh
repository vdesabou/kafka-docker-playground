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


cd ../../connect/connect-http-v2-source

# Copy JAR files to confluent-hub
mkdir -p ../../confluent-hub/confluentinc-kafka-connect-http-v2/lib/
cp ../../connect/connect-http-v2-source/jcl-over-slf4j-2.0.7.jar ../../confluent-hub/confluentinc-kafka-connect-http-v2/lib/jcl-over-slf4j-2.0.7.jar
cd -
PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.chaining-offset.yml"

playground debug log-level set --package "org.apache.http" --level TRACE

log "Creating http-source connector with chaining offset mode (Elasticsearch search_after pagination)"
playground connector create-or-update --connector http-source  << EOF
{
    "tasks.max": "1",
    "connector.class": "io.confluent.connect.http.source.GenericHttpSourceConnector",

    "connection.disallow.local.ips": "false",
    "connection.disallow.private.ips": "false",

    "http.api.base.url": "http://httpserver:9006",

    "apis.num": "1",
    "api1.http.api.path": "/test-index/_search",
    "api1.topics": "http-source-topic-v2",
    "api1.http.request.headers": "Content-Type: application/json",
    "api1.test.api": "false",
    "api1.http.offset.mode": "CHAINING",
    "api1.http.request.method": "POST",
    "api1.http.request.body": "{\\"size\\": 100, \\"sort\\": [{\\"@time\\": \\"asc\\"}], \\"search_after\\": [\${offset}]}",
    "api1.http.initial.offset": "1647948000000",
    "api1.http.response.data.json.pointer": "/hits/hits",
    "api1.http.offset.json.pointer": "/sort/0",
    "api1.request.interval.ms": "5000",

    "reporter.bootstrap.servers": "broker:9092",
    "reporter.error.topic.name": "error-responses",
    "reporter.error.topic.replication.factor": 1,
    "reporter.result.topic.name": "success-responses",
    "reporter.result.topic.replication.factor": 1,
    "reporter.result.topic.value.format": "string"
}
EOF

log "Wait 5 seconds for connector to start and fetch initial batch"
sleep 5

playground topic consume --topic http-source-topic-v2 --min-expected-messages 3 --timeout 10

log "The connector should fetch new data every 5 seconds"
