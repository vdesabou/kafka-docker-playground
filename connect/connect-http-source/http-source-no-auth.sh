#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"

HTTP_SOURCE_CONNECTOR_ZIP="confluentinc-kafka-connect-http-source-0.2.0-SNAPSHOT.zip"
export CONNECTOR_ZIP="$PWD/$HTTP_SOURCE_CONNECTOR_ZIP"

source ${DIR}/../../scripts/utils.sh


get_3rdparty_file "$HTTP_SOURCE_CONNECTOR_ZIP"

if [ ! -f ${PWD}/$HTTP_SOURCE_CONNECTOR_ZIP ]
then
     logerror "ERROR: ${PWD}/$HTTP_SOURCE_CONNECTOR_ZIP is missing. You must be a Confluent Employee to run this example !"
     exit 1
fi



${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.no-auth.yml"

log "Creating http-source connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "tasks.max": "1",
               "connector.class": "io.confluent.connect.http.HttpSourceConnector",
               "key.converter": "org.apache.kafka.connect.storage.StringConverter",
               "value.converter": "org.apache.kafka.connect.storage.StringConverter",
               "confluent.topic.bootstrap.servers": "broker:9092",
               "confluent.topic.replication.factor": "1",
               "url": "http://httpserver:8080/api/messages",
               "topic.name.pattern":"http-topic-${entityName}",
               "entity.names": "messages",
               "http.offset.mode": "SIMPLE_INCREMENTING",
               "http.initial.offset": "1"
          }' \
     http://localhost:8083/connectors/http-source/config | jq .


sleep 3

log "Send a message to HTTP server"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{"test":"value"}' \
     http://localhost:8080/api/messages | jq .


sleep 2

log "Verify we have received the data in http-topic-messages topic"
timeout 60 docker exec connect kafka-console-consumer -bootstrap-server broker:9092 --topic http-topic-messages --from-beginning --property print.key=true --max-messages 1
