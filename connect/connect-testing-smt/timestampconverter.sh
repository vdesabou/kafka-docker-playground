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
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.builtin.yml"

log "Sending 10 messages (with a unix-millis 'event_time' field) to topic http-messages"
playground topic produce -t http-messages --nb-messages 10 << 'EOF'
{
    "id": "iteration.index",
    "event_time": 1700000000000
}
EOF

playground debug log-level set --package "org.apache.http" --level TRACE

log "Set webserver to reply with 200"
curl -X PUT -H "Content-Type: application/json" --data '{"errorCode": 200}' http://localhost:9006/set-response-error-code
curl -X PUT -H "Content-Type: application/json" --data '{"message":"Hello, World!"}' http://localhost:9006/set-response-body

log "Creating http-sink connector with the Apache TimestampConverter SMT (org.apache.kafka.connect.transforms) converting 'event_time' to a formatted string"
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

     "transforms": "tsConvert",
     "transforms.tsConvert.type": "org.apache.kafka.connect.transforms.TimestampConverter\$Value",
     "transforms.tsConvert.field": "event_time",
     "transforms.tsConvert.target.type": "string",
     "transforms.tsConvert.format": "yyyy-MM-dd"
}
EOF

sleep 10

log "Check the success-responses topic"
playground topic consume --topic success-responses --min-expected-messages 10 --timeout 60

log "Verify the Apache TimestampConverter SMT was applied: the unix millis became a formatted date in the body received by the HTTP server"
playground container logs --container httpserver --wait-for-log "2023-11-14"
