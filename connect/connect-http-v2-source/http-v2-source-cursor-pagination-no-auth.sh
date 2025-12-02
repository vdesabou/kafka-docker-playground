#!/bin/bash
set -e

# https://docs.confluent.io/cloud/current/connectors/cc-http-source.html#cursor-pagination-offset-mode-with-the-gcs-list-objects-rest-api
# This example demonstrates cursor pagination with Google Cloud Storage API-style responses
# The HTTP server returns paginated data with the following structure:
# {
#   "kind": "storage#objects",
#   "nextPageToken": "CkV0b3BpY3MvZGVtby9MS9ob3V...=",
#   "items": [ {...}, {...}, ... ]
# }
# The connector makes requests to http://httpserver:9006/storage/v1/b/test-bucket/o?pageToken=<token>
# and uses the nextPageToken from the response to fetch subsequent pages


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
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.cursor-pagination.no-auth.yml"

playground debug log-level set --package "org.apache.http" --level TRACE

log "Creating http-source connector with cursor pagination (Google Cloud Storage API style)"
playground connector create-or-update --connector http-source  << EOF
{
    "tasks.max": "1",
    "connector.class": "io.confluent.connect.http.source.GenericHttpSourceConnector",

    "connection.disallow.local.ips": "false",
    "connection.disallow.private.ips": "false",

    "http.api.base.url": "http://httpserver:9006",

    "apis.num": "1",
    "api1.http.api.path": "/storage/v1/b/test-bucket/o",
    "api1.topics": "http-source-topic-v2",
    "api1.http.request.headers": "Content-Type: application/json",
    "api1.test.api": "false",

    "api1.http.offset.mode": "CURSOR_PAGINATION",
    "api1.http.request.method": "GET",
    "api1.http.request.parameters": "pageToken=\${offset}",
    "api1.http.response.data.json.pointer": "/items",
    "api1.http.next.page.json.pointer": "/nextPageToken",
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

log "Verify we have received the data in http-source-topic-v2 topic (expecting 15 messages across 3 pages)"
playground topic consume --topic http-source-topic-v2 --min-expected-messages 15 --timeout 60
