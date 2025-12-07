#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"

source ${DIR}/../../scripts/utils.sh

# https://docs.confluent.io/cloud/current/connectors/cc-http-source.html#simple-incrementing-offset-mode-with-the-atlassian-confluence-cloud-rest-api

if connect_cp_version_greater_than_8 && [ ! -z "$CONNECTOR_TAG" ] && ! version_gt $CONNECTOR_TAG "0.1.99"
then
     logwarn "minimal supported connector version is 0.2.0 for CP 8.0"
     logwarn "see https://docs.confluent.io/platform/current/connect/supported-connector-version-8.1.html#supported-connector-versions-in-cp-8-1"
     exit 111
fi

cd ../../connect/connect-http-source/
if [ ! -f jcl-over-slf4j-2.0.7.jar ]
then
     wget -q https://repo1.maven.org/maven2/org/slf4j/jcl-over-slf4j/2.0.7/jcl-over-slf4j-2.0.7.jar
fi
cd -


cd ../../connect/connect-http-source

# Copy JAR files to confluent-hub
mkdir -p ../../confluent-hub/confluentinc-kafka-connect-http-source/lib/
cp ../../connect/connect-http-source/jcl-over-slf4j-2.0.7.jar ../../confluent-hub/confluentinc-kafka-connect-http-source/lib/jcl-over-slf4j-2.0.7.jar
cd -
PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.simple-incrementing.yml"

playground debug log-level set --package "org.apache.http" --level TRACE

log "Creating http-source connector (SIMPLE_INCREMENTING) for Confluence spaces with dynamic growth"
playground connector create-or-update --connector http-source  << EOF
{
    "tasks.max": "1",
    "connector.class": "io.confluent.connect.http.HttpSourceConnector",
    "key.converter": "org.apache.kafka.connect.storage.StringConverter",
    "value.converter": "org.apache.kafka.connect.json.JsonConverter",
    "value.converter.schemas.enable": "false",
    "confluent.topic.bootstrap.servers": "broker:9092",
    "confluent.topic.replication.factor": "1",
    "topic.name.pattern":"http-topic-\${entityName}",
    "entity.names": "spaces",
    "url": "http://httpserver:9006/wiki/rest/api/space",
    "http.offset.mode": "SIMPLE_INCREMENTING",
    "http.request.parameters": "start=\${offset}&limit=1",
    "http.initial.offset": "0",
    "http.response.data.json.pointer": "/results",
    "request.interval.ms": "1000"
}
EOF

sleep 10

log "Verify we have received the initial spaces in http-topic-spaces topic (expecting at least 15 spaces, 1 per page)"
playground topic consume --topic http-topic-spaces --min-expected-messages 15 --timeout 60


# CreateTime:2025-12-01 22:34:10.116|Partition:0|Offset:0|Headers:NO_HEADERS|Key:null|Value:{"id":1000,"key":"~user1000","name":"Space 0 user1000","type":"personal","status":"current","_expandable":{"settings":"/rest/api/space/~user1000/settings","metadata":"","operations":"","lookAndFeel":"/rest/api/settings/lookandfeel?spaceKey=~user1000","identifiers":"","permissions":"","icon":"","description":"","theme":"/rest/api/space/~user1000/theme","history":"","homepage":"/rest/api/content/6000"},"_links":{"webui":"/spaces/~user1000","self":"https://example.atlassian.net/wiki/rest/api/space/~user1000"}}|ValueSchemaId:
# CreateTime:2025-12-01 22:34:11.255|Partition:0|Offset:1|Headers:NO_HEADERS|Key:null|Value:{"id":1001,"key":"~user1001","name":"Space 1 user1001","type":"personal","status":"current","_expandable":{"settings":"/rest/api/space/~user1001/settings","metadata":"","operations":"","lookAndFeel":"/rest/api/settings/lookandfeel?spaceKey=~user1001","identifiers":"","permissions":"","icon":"","description":"","theme":"/rest/api/space/~user1001/theme","history":"","homepage":"/rest/api/content/6001"},"_links":{"webui":"/spaces/~user1001","self":"https://example.atlassian.net/wiki/rest/api/space/~user1001"}}|ValueSchemaId:
# CreateTime:2025-12-01 22:34:12.406|Partition:0|Offset:2|Headers:NO_HEADERS|Key:null|Value:{"id":1002,"key":"~user1002","name":"Space 2 user1002","type":"personal","status":"current","_expandable":{"settings":"/rest/api/space/~user1002/settings","metadata":"","operations":"","lookAndFeel":"/rest/api/settings/lookandfeel?spaceKey=~user1002","identifiers":"","permissions":"","icon":"","description":"","theme":"/rest/api/space/~user1002/theme","history":"","homepage":"/rest/api/content/6002"},"_links":{"webui":"/spaces/~user1002","self":"https://example.atlassian.net/wiki/rest/api/space/~user1002"}}|ValueSchemaId:
# CreateTime:2025-12-01 22:34:13.520|Partition:0|Offset:3|Headers:NO_HEADERS|Key:null|Value:{"id":1003,"key":"~user1003","name":"Space 3 user1003","type":"personal","status":"current","_expandable":{"settings":"/rest/api/space/~user1003/settings","metadata":"","operations":"","lookAndFeel":"/rest/api/settings/lookandfeel?spaceKey=~user1003","identifiers":"","permissions":"","icon":"","description":"","theme":"/rest/api/space/~user1003/theme","history":"","homepage":"/rest/api/content/6003"},"_links":{"webui":"/spaces/~user1003","self":"https://example.atlassian.net/wiki/rest/api/space/~user1003"}}|ValueSchemaId:
# CreateTime:2025-12-01 22:34:14.641|Partition:0|Offset:4|Headers:NO_HEADERS|Key:null|Value:{"id":1004,"key":"~user1004","name":"Space 4 user1004","type":"personal","status":"current","_expandable":{"settings":"/rest/api/space/~user1004/settings","metadata":"","operations":"","lookAndFeel":"/rest/api/settings/lookandfeel?spaceKey=~user1004","identifiers":"","permissions":"","icon":"","description":"","theme":"/rest/api/space/~user1004/theme","history":"","homepage":"/rest/api/content/6004"},"_links":{"webui":"/spaces/~user1004","self":"https://example.atlassian.net/wiki/rest/api/space/~user1004"}}|ValueSchemaId: