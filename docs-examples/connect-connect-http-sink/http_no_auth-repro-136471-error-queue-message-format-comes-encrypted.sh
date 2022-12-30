#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.repro-136471-error-queue-message-format-comes-encrypted.yml"


log "Sending messages to topic http-messages"
# Using Heredoc
docker exec -i broker kafka-console-producer --broker-list broker:9092 --topic http-messages << EOF
{"record":"record1"}
EOF

log "-------------------------------------"
log "Running Simple (No) Authentication Example"
log "-------------------------------------"

log "Creating http-sink connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
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
               "retry.backoff.ms": "300",
               "retry.on.status.codes": "400-",
               "behavior.on.null.values": "ignore",
               "behavior.on.error": "log",
               "batch.max.size": "1",
               "http.api.url": "http://httpstat.us/404",
               "batch.max.size": "1",
               "max.retries": "1",
               "errors.tolerance": "all",
               "errors.deadletterqueue.topic.name": "dlq",
               "errors.deadletterqueue.topic.replication.factor": "1",
               "report.errors.as": "error_string"
          }' \
     http://localhost:8083/connectors/http-sink/config | jq .


sleep 10

log "Check the error-responses topic"
timeout 60 docker exec broker kafka-console-consumer --bootstrap-server broker:9092 --topic error-responses --from-beginning --max-messages 1 --property print.headers=true

#input_record_offset:0,input_record_timestamp:1672245022561,input_record_partition:0,input_record_topic:http-messages,error_message:null,exception:null,response_content:404 Not Found,status_code:404,payload:1,reason_phrase:Not Found,url:http://httpstat.us/404    "Retry time lapsed, unable to process HTTP request. HTTP Response code: 404, Reason phrase: Not Found, Url: http://httpstat.us/404, Response content: 404 Not Found, Exception: null, Error message: null"
