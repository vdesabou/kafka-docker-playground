#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

export ENABLE_KCAT=1
CLI=${1:-kafka-console-producer}

if [ "$CLI" != "kafka-console-producer" ] && [ "$CLI" != "kcat" ]
then
     logerror "CLI should be either kafka-console-producer (default) or kcat"
     exit 1
fi

playground start-environment --environment plaintext --docker-compose-override-file "${PWD}/docker-compose.plaintext.yml"

log "Sending messages to topic http-messages"
playground topic produce -t http-messages --nb-messages 10 << 'EOF'
%g
EOF

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
               "http.api.url": "http://http-service-no-auth:8080/api/messages",
               "batch.max.size": "10"
          }
EOF


sleep 10

log "Confirm that the data was sent to the HTTP endpoint."
curl localhost:8080/api/messages | jq . > /tmp/result.log  2>&1
cat /tmp/result.log
grep "10" /tmp/result.log

log "Check the success-responses topic"
playground topic consume --topic success-responses --min-expected-messages 10 --timeout 60

log "Show connect-configs"
docker exec -i broker kafka-console-consumer --bootstrap-server localhost:9092 --topic connect-configs --from-beginning --property print.key=true --timeout-ms 10000 1> /tmp/connect-configs.backup
cat /tmp/connect-configs.backup

log "Stopping worker"
docker stop connect

if [ "$CLI" = "kafka-console-producer" ]
then
     log "Sending string null (kafka-console-producer is not able to send tombstone, coming in https://cwiki.apache.org/confluence/pages/viewpage.action?pageId=199527475)"
docker exec -i broker kafka-console-producer --broker-list broker:9092 --topic connect-configs --property parse.key=true --property key.separator=, << EOF
connector-http-sink,null
EOF
else
     log "Sending tombstone with kcat"
     echo 'connector-http-sink#' | docker exec -i kcat kcat -b broker:9092 -t connect-configs -P -Z -K#
fi

log "Starting worker"
docker start connect

../../scripts/wait-for-connect-and-controlcenter.sh

sleep 30

log "Get connector status"
curl http://localhost:8083/connectors?expand=status&expand=info | jq .

# {}

sleep 2

log "Show connect-configs"
docker exec -i broker kafka-console-consumer --bootstrap-server localhost:9092 --topic connect-configs --from-beginning --property print.key=true --timeout-ms 10000 1> /tmp/connect-configs.backup
cat /tmp/connect-configs.backup

log "re-create connector"
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
               "http.api.url": "http://http-service-no-auth:8080/api/messages",
               "batch.max.size": "10"
          }
EOF

sleep 5

log "Get connector status"
curl http://localhost:8083/connectors?expand=status&expand=info | jq .

log "Sending messages to topic http-messages"
playground topic produce -t http-messages --nb-messages 10 << 'EOF'
%g
EOF

log "Check the success-responses topic"
playground topic consume --topic success-responses --min-expected-messages 20 --timeout 60

log "Show connect-configs"
docker exec -i broker kafka-console-consumer --bootstrap-server localhost:9092 --topic connect-configs --from-beginning --property print.key=true --timeout-ms 10000 1> /tmp/connect-configs.backup
cat /tmp/connect-configs.backup


# with kakfa-console-producer:

# [2022-03-14 09:34:31,029] INFO Successfully processed removal of connector 'http-sink' (org.apache.kafka.connect.storage.KafkaConfigBackingStore:633)


# with kcat:

# [2022-03-14 09:43:27,120] INFO Successfully processed removal of connector 'http-sink' (org.apache.kafka.connect.storage.KafkaConfigBackingStore:633)


# Conclusion: same behaviour