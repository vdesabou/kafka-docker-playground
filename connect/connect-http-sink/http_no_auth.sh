#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if [ ! -f jcl-over-slf4j-2.0.7.jar ]
then
     wget https://repo1.maven.org/maven2/org/slf4j/jcl-over-slf4j/2.0.7/jcl-over-slf4j-2.0.7.jar
fi

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"


log "Sending messages to topic http-messages"
playground topic produce -t http-messages --nb-messages 10 << 'EOF'
%g
EOF

playground debug log-level set --package "org.apache.http" --level TRACE

log "Set webserver to reply with 200"
curl -X PUT -H "Content-Type: application/json" --data '{"errorCode": 200}' http://localhost:9006

log "Creating http-sink connector"
playground connector create-or-update --connector http-sink << EOF
{
     "topics": "http-messages",
     "tasks.max": "1",
     "connector.class": "io.confluent.connect.http.HttpSinkConnector",
     "key.converter": "org.apache.kafka.connect.storage.StringConverter",
     "value.converter": "org.apache.kafka.connect.storage.StringConverter",
     "confluent.topic.bootstrap.servers": "broker:9092",
     "confluent.topic.replication.factor": "1",
     "reporter.bootstrap.servers": "broker:9092",
     "reporter.error.topic.name": "error-responses",
     "reporter.error.topic.replication.factor": 1,
     "reporter.result.topic.name": "success-responses",
     "reporter.result.topic.replication.factor": 1,
     "http.api.url": "http://httpserver:9006",
     "batch.max.size": "10"
}
EOF


sleep 10

log "Check the success-responses topic"
playground topic consume --topic success-responses --min-expected-messages 10 --timeout 60
# input_record_offset:0,input_record_timestamp:1645173514858,input_record_partition:0,input_record_topic:http-messages    "{\"id\":1,\"message\":\"1,2,3,4,5,6,7,8,9,10\"}"
# input_record_offset:1,input_record_timestamp:1645173514881,input_record_partition:0,input_record_topic:http-messages    "{\"id\":1,\"message\":\"1,2,3,4,5,6,7,8,9,10\"}"
# input_record_offset:2,input_record_timestamp:1645173514882,input_record_partition:0,input_record_topic:http-messages    "{\"id\":1,\"message\":\"1,2,3,4,5,6,7,8,9,10\"}"
# input_record_offset:3,input_record_timestamp:1645173514882,input_record_partition:0,input_record_topic:http-messages    "{\"id\":1,\"message\":\"1,2,3,4,5,6,7,8,9,10\"}"
# input_record_offset:4,input_record_timestamp:1645173514882,input_record_partition:0,input_record_topic:http-messages    "{\"id\":1,\"message\":\"1,2,3,4,5,6,7,8,9,10\"}"
# input_record_offset:5,input_record_timestamp:1645173514882,input_record_partition:0,input_record_topic:http-messages    "{\"id\":1,\"message\":\"1,2,3,4,5,6,7,8,9,10\"}"
# input_record_offset:6,input_record_timestamp:1645173514882,input_record_partition:0,input_record_topic:http-messages    "{\"id\":1,\"message\":\"1,2,3,4,5,6,7,8,9,10\"}"
# input_record_offset:7,input_record_timestamp:1645173514882,input_record_partition:0,input_record_topic:http-messages    "{\"id\":1,\"message\":\"1,2,3,4,5,6,7,8,9,10\"}"
# input_record_offset:8,input_record_timestamp:1645173514882,input_record_partition:0,input_record_topic:http-messages    "{\"id\":1,\"message\":\"1,2,3,4,5,6,7,8,9,10\"}"
# input_record_offset:9,input_record_timestamp:1645173514882,input_record_partition:0,input_record_topic:http-messages    "{\"id\":1,\"message\":\"1,2,3,4,5,6,7,8,9,10\"}"
# Processed a total of 10 messages