#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

# The HTTP sink connector needs jcl-over-slf4j on its classpath
cd ${DIR}
if [ ! -f jcl-over-slf4j-2.0.7.jar ]
then
     wget -q https://repo1.maven.org/maven2/org/slf4j/jcl-over-slf4j/2.0.7/jcl-over-slf4j-2.0.7.jar
fi
mkdir -p ${DIR}/../../confluent-hub/confluentinc-kafka-connect-http/lib/
cp ${DIR}/jcl-over-slf4j-2.0.7.jar ${DIR}/../../confluent-hub/confluentinc-kafka-connect-http/lib/
cd - > /dev/null

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.yml"

log "Sending 5 messages with category 'keep' to topic http-messages"
playground topic produce -t http-messages --nb-messages 5 << 'EOF'
{
    "id": "iteration.index",
    "category": "keep",
    "name": "faker.internet.userName()"
}
EOF

log "Sending 5 messages with category 'drop' to topic http-messages"
playground topic produce -t http-messages --nb-messages 5 << 'EOF'
{
    "id": "iteration.index",
    "category": "drop",
    "name": "faker.internet.userName()"
}
EOF

playground debug log-level set --package "org.apache.http" --level TRACE

log "Set webserver to reply with 200"
curl -X PUT -H "Content-Type: application/json" --data '{"errorCode": 200}' http://localhost:9006/set-response-error-code
curl -X PUT -H "Content-Type: application/json" --data '{"message":"Hello, World!"}' http://localhost:9006/set-response-body

log "Creating http-sink connector with the Confluent Filter SMT (io.confluent.connect.transforms) keeping only records where category == 'keep'"
playground connector create-or-update --connector http-sink  << EOF
{
     "topics": "http-messages",
     "tasks.max": "1",
     "connector.class": "io.confluent.connect.http.HttpSinkConnector",
     "key.converter": "org.apache.kafka.connect.storage.StringConverter",
     "value.converter":"org.apache.kafka.connect.json.JsonConverter",
     "value.converter.schemas.enable":"false",
     "confluent.topic.bootstrap.servers": "broker:9092",
     "confluent.topic.replication.factor": "1",
     "reporter.bootstrap.servers": "broker:9092",
     "reporter.error.topic.name": "error-responses",
     "reporter.error.topic.replication.factor": 1,
     "reporter.result.topic.name": "success-responses",
     "reporter.result.topic.replication.factor": 1,
     "reporter.result.topic.value.format": "string",
     "http.api.url": "http://httpserver:9006",
     "request.body.format" : "json",
     "headers": "Content-Type: application/json",

     "transforms": "keepOnly",
     "transforms.keepOnly.type": "io.confluent.connect.transforms.Filter\$Value",
     "transforms.keepOnly.filter.condition": "\$[?(@.category == 'keep')]",
     "transforms.keepOnly.filter.type": "include",
     "transforms.keepOnly.missing.or.null.behavior": "exclude"
}
EOF

sleep 10

log "Check the success-responses topic: only the 5 'keep' records should have reached the HTTP server"
playground topic consume --topic success-responses --min-expected-messages 5 --timeout 60

log "Verify the Confluent Filter SMT was applied: the HTTP server received 'keep' records"
playground container logs --container httpserver --wait-for-log "keep"
