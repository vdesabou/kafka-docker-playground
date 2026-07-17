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

log "Sending 5 regular messages to topic http-messages"
playground topic produce -t http-messages --nb-messages 5 << 'EOF'
{
    "id": "iteration.index",
    "name": "faker.internet.userName()"
}
EOF

log "Sending 3 tombstone (null value) messages to topic http-messages"
playground topic produce -t http-messages --nb-messages 3 --tombstone --forced-key "tombstone-key"

playground debug log-level set --package "org.apache.http" --level TRACE

log "Set webserver to reply with 200"
curl -X PUT -H "Content-Type: application/json" --data '{"errorCode": 200}' http://localhost:9006/set-response-error-code
curl -X PUT -H "Content-Type: application/json" --data '{"message":"Hello, World!"}' http://localhost:9006/set-response-body

log "Creating http-sink connector with the Confluent TombstoneHandler SMT (io.confluent.connect.transforms) ignoring tombstone records"
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

     "transforms": "handleTombstones",
     "transforms.handleTombstones.type": "io.confluent.connect.transforms.TombstoneHandler",
     "transforms.handleTombstones.behavior": "ignore"
}
EOF

sleep 10

log "Check the success-responses topic: only the 5 regular records should reach the HTTP server, the 3 tombstones are ignored by the SMT"
playground topic consume --topic success-responses --min-expected-messages 5 --timeout 60
