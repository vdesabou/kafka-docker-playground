#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if connect_cp_version_greater_than_8 && [ ! -z "$CONNECTOR_TAG" ] && ! version_gt $CONNECTOR_TAG "2.1.9"
then
     logwarn "minimal supported connector version is 2.1.10 for CP 8.0"
     logwarn "see https://docs.confluent.io/platform/current/connect/supported-connector-version-8.1.html#supported-connector-versions-in-cp-8-1"
     exit 111
fi

CONNECTOR_GITHUB_ACCESS_TOKEN=${CONNECTOR_GITHUB_ACCESS_TOKEN:-$1}

if [ -z "$CONNECTOR_GITHUB_ACCESS_TOKEN" ]
then
     logerror "CONNECTOR_GITHUB_ACCESS_TOKEN is not set. Export it as environment variable or pass it as argument"
     exit 1
fi

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.yml"

if version_gt $CONNECTOR_TAG "1.9.9"
then
     playground connector create-or-update --connector github-source  << EOF
{
     "connector.class": "io.confluent.connect.github.GithubSourceConnector",
     "topic.name.pattern":"github-topic-\${resourceName}",
     "tasks.max": "1",
     "github.service.url":"https://api.github.com",
     "github.repositories":"apache/kafka",
     "github.resources":"stargazers",
     "github.since":"2019-01-01",
     "github.access.token": "$CONNECTOR_GITHUB_ACCESS_TOKEN",
     "key.converter": "io.confluent.connect.avro.AvroConverter",
     "key.converter.schema.registry.url":"http://schema-registry:8081",
     "value.converter": "io.confluent.connect.avro.AvroConverter",
     "value.converter.schema.registry.url":"http://schema-registry:8081",
     "confluent.license": "",
     "confluent.topic.bootstrap.servers": "broker:9092",
     "confluent.topic.replication.factor": "1",
     "errors.tolerance": "all",
     "errors.log.enable": "true",
     "errors.log.include.messages": "true"
}
EOF
else
     playground connector create-or-update --connector github-source  << EOF
{
     "connector.class": "io.confluent.connect.github.GithubSourceConnector",
     "topic.name.pattern":"github-topic-\${entityName}",
     "tasks.max": "1",
     "github.service.url":"https://api.github.com",
     "github.repositories":"apache/kafka",
     "github.tables":"stargazers",
     "github.since":"2019-01-01",
     "github.access.token": "$CONNECTOR_GITHUB_ACCESS_TOKEN",
     "key.converter": "io.confluent.connect.avro.AvroConverter",
     "key.converter.schema.registry.url":"http://schema-registry:8081",
     "value.converter": "io.confluent.connect.avro.AvroConverter",
     "value.converter.schema.registry.url":"http://schema-registry:8081",
     "confluent.license": "",
     "confluent.topic.bootstrap.servers": "broker:9092",
     "confluent.topic.replication.factor": "1",
     "errors.tolerance": "all",
     "errors.log.enable": "true",
     "errors.log.include.messages": "true"
}
EOF
fi

sleep 10

log "Verify we have received the data in github-topic-stargazers topic"
playground topic consume --topic github-topic-stargazers --min-expected-messages 1 --timeout 60