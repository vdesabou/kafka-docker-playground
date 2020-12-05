#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

GITHUB_ACCESS_TOKEN=${GITHUB_ACCESS_TOKEN:-$1}

if [ -z "$GITHUB_ACCESS_TOKEN" ]
then
     logerror "GITHUB_ACCESS_TOKEN is not set. Export it as environment variable or pass it as argument"
     exit 1
fi

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"

log "Creating Github Source connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
                    "connector.class": "io.confluent.connect.github.GithubSourceConnector",
                    "topic.name.pattern":"github-topic-${entityName}",
                    "tasks.max": "1",
                    "github.service.url":"https://api.github.com",
                    "github.repositories":"apache/kafka",
                    "github.tables":"stargazers",
                    "github.since":"2019-01-01",
                    "github.access.token": "'"$GITHUB_ACCESS_TOKEN"'",
                    "key.converter": "io.confluent.connect.avro.AvroConverter",
                    "key.converter.schema.registry.url":"http://schema-registry:8081",
                    "value.converter": "io.confluent.connect.avro.AvroConverter",
                    "value.converter.schema.registry.url":"http://schema-registry:8081",
                    "confluent.license": "",
                    "confluent.topic.bootstrap.servers": "broker:9092",
                    "confluent.topic.replication.factor": "1"
          }' \
     http://localhost:8083/connectors/github-source/config | jq .


sleep 10

log "Verify we have received the data in github-topic-stargazers topic"
timeout 60 docker exec connect kafka-avro-console-consumer -bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic github-topic-stargazers --from-beginning --property print.key=true --max-messages 1