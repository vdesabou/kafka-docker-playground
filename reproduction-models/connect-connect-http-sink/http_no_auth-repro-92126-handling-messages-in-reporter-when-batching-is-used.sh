#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh


for component in consumer-repro-92126
do
     set +e
     log "🏗 Building jar for ${component}"
     docker run -i --rm -e KAFKA_CLIENT_TAG=$KAFKA_CLIENT_TAG -e TAG=$TAG_BASE -v "${DIR}/${component}":/usr/src/mymaven -v "$HOME/.m2":/root/.m2 -v "${DIR}/${component}/target:/usr/src/mymaven/target" -w /usr/src/mymaven maven:3.6.1-jdk-11 mvn -Dkafka.tag=$TAG -Dkafka.client.tag=$KAFKA_CLIENT_TAG package > /tmp/result.log 2>&1
     if [ $? != 0 ]
     then
          logerror "ERROR: failed to build java component $component"
          tail -500 /tmp/result.log
          exit 1
     fi
     set -e
done

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.repro-92126-handling-messages-in-reporter-when-batching-is-used.yml"

log "Creating connectorA connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
          "topics": "http-messages",
          "tasks.max": "1",
          "connector.class": "io.confluent.connect.http.HttpSinkConnector",
          "key.converter": "org.apache.kafka.connect.storage.StringConverter",
          "value.converter": "org.apache.kafka.connect.storage.StringConverter",
          "confluent.topic.bootstrap.servers": "broker:9092",
          "confluent.topic.replication.factor": "1",
          "reporter.bootstrap.servers": "broker:9092",
          "reporter.error.topic.name": "errorA",
          "reporter.error.topic.replication.factor": 1,
          "reporter.result.topic.name": "successA",
          "reporter.result.topic.replication.factor": 1,
          "http.api.url": "http://http-service-no-auth:8080/api/messages",
          "batch.max.size": "10"
          }' \
     http://localhost:8083/connectors/connectorA/config | jq .

log "Creating connectorB connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
          "topics": "http-messages",
          "tasks.max": "1",
          "connector.class": "io.confluent.connect.http.HttpSinkConnector",
          "key.converter": "org.apache.kafka.connect.storage.StringConverter",
          "value.converter": "org.apache.kafka.connect.storage.StringConverter",
          "confluent.topic.bootstrap.servers": "broker:9092",
          "confluent.topic.replication.factor": "1",
          "reporter.bootstrap.servers": "broker:9092",
          "reporter.error.topic.name": "errorB",
          "reporter.error.topic.replication.factor": 1,
          "reporter.result.topic.name": "successB",
          "reporter.result.topic.replication.factor": 1,
          "http.api.url": "http://http-service-no-auth:8080/api/messages",
          "batch.max.size": "15"
          }' \
     http://localhost:8083/connectors/connectorB/config | jq .

sleep 10

# log "Check the successA topic"
# timeout 60 docker exec broker kafka-console-consumer --bootstrap-server broker:9092 --topic successB --from-beginning --max-messages 10 --property print.headers=true

log "Run the Java consumer. Logs are in consumer.log."
docker exec consumer-repro-92126 bash -c "java -jar consumer-1.0.0-jar-with-dependencies.jar" > consumer.log 2>&1 &

sleep 20

log "Sending 150 messages to topic http-messages"
seq 150 | docker exec -i broker kafka-console-producer --broker-list broker:9092 --topic http-messages
