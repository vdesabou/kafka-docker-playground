#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

for component in producer-v1 producer-v2 consumer-v1
do
     if [ ! -f ${DIR}/${component}/target/${component}-1.0.0-jar-with-dependencies.jar ]
     then
          log "Building jar for ${component}"
          docker run -i --rm -e KAFKA_CLIENT_TAG=$KAFKA_CLIENT_TAG -e TAG=$TAG_BASE -v "${DIR}/${component}":/usr/src/mymaven -v "$HOME/.m2":/root/.m2 -v "${DIR}/${component}/target:/usr/src/mymaven/target" -w /usr/src/mymaven maven:3.6.1-jdk-11 mvn package
     fi
done

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.yml"

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

# log "Run the Java consumer. Logs are in consumer.log."
# docker exec consumer-v1 bash -c "java -jar consumer-v1-1.0.0-jar-with-dependencies.jar" > consumer.log 2>&1 &

log "Run the Java producer-v1"
docker exec producer-v1 bash -c "java -jar producer-v1-1.0.0-jar-with-dependencies.jar"

docker exec consumer-v1 bash -c "java -jar consumer-v1-1.0.0-jar-with-dependencies.jar"

log "Run the Java producer-v2, it adds a mandatory field country"
docker exec producer-v2 bash -c "java -jar producer-v2-1.0.0-jar-with-dependencies.jar"



docker exec broker kafka-consumer-groups --bootstrap-server broker:9092 --group customer-avro-app --describe
docker exec broker kafka-consumer-groups --bootstrap-server broker:9092 --group customer-avro-app --to-earliest --topic customer --reset-offsets --dry-run
docker exec broker kafka-consumer-groups --bootstrap-server broker:9092 --group customer-avro-app --to-earliest --topic customer --reset-offsets --execute