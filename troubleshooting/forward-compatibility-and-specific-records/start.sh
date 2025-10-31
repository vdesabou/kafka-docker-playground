#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

for component in producer-v1 producer-v2 consumer-v1 consumer-v2
do
     set +e
     log "🏗 Building jar for ${component}"
     docker run -i --rm -e KAFKA_CLIENT_TAG=$KAFKA_CLIENT_TAG -e TAG=$TAG_BASE -v "${PWD}/${component}":/usr/src/mymaven -v "$HOME/.m2":/root/.m2 -v "$PWD/../../scripts/settings.xml:/tmp/settings.xml" -v "${PWD}/${component}/target:/usr/src/mymaven/target" -w /usr/src/mymaven maven:3.9.11-eclipse-temurin-11-alpine mvn -s /tmp/settings.xml -Dkafka.tag=$TAG -Dkafka.client.tag=$KAFKA_CLIENT_TAG package > /tmp/result.log 2>&1
     if [ $? != 0 ]
     then
          logerror "❌ failed to build java component $component"
          tail -500 /tmp/result.log
          exit 1
     fi
     set -e
done

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.yml"

docker exec broker kafka-topics --create --topic customer-avro --partitions 1 --replication-factor 1 --bootstrap-server broker:9092

log "Set global compatibility mode to FORWARD"
curl --request PUT \
  --url http://localhost:8081/config \
  --header 'Content-Type: application/vnd.schemaregistry.v1+json' \
  --data '{
    "compatibility": "FORWARD"
}'

log "Verify global compatibility mode"
curl --request GET \
  --url http://localhost:8081/config

log "Run the Java consumer. Logs are in consumer.log."
docker exec consumer-v1 bash -c "java -jar consumer-v1-1.0.0-jar-with-dependencies.jar" > consumer.log 2>&1 &

sleep 15

log "Run the Java producer-v1"
docker exec producer-v1 bash -c "java -jar producer-v1-1.0.0-jar-with-dependencies.jar"

log "Run the Java producer-v2, it adds a mandatory field country"
docker exec producer-v2 bash -c "java -jar producer-v2-1.0.0-jar-with-dependencies.jar"

log "Stop the consumer-v1"
docker stop consumer-v1

sleep 5

log "Reset offset for customer-avro-app"

docker exec broker kafka-consumer-groups --bootstrap-server broker:9092 --group customer-avro-app --describe
docker exec broker kafka-consumer-groups --bootstrap-server broker:9092 --group customer-avro-app --to-earliest --topic customer-avro --reset-offsets --dry-run
docker exec broker kafka-consumer-groups --bootstrap-server broker:9092 --group customer-avro-app --to-earliest --topic customer-avro --reset-offsets --execute
docker exec broker kafka-consumer-groups --bootstrap-server broker:9092 --group customer-avro-app --describe

log "Run the Java consumer-v2"
docker exec consumer-v2 bash -c "java -jar consumer-v2-1.0.0-jar-with-dependencies.jar" > consumer_after_reset.log 2>&1 &