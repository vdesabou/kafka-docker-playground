#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

for component in producer
do
    set +e
    log "🏗 Building jar for ${component}"
    docker run -i --rm -e KAFKA_CLIENT_TAG=$KAFKA_CLIENT_TAG -e TAG=$TAG_BASE -v "${DIR}/${component}":/usr/src/mymaven -v "$HOME/.m2":/root/.m2 -v "${DIR}/${component}/target:/usr/src/mymaven/target" -w /usr/src/mymaven --platform=linux/amd64 maven:3.6.1-jdk-11 mvn -Dkafka.tag=$TAG -Dkafka.client.tag=$KAFKA_CLIENT_TAG package > /tmp/result.log 2>&1
    if [ $? != 0 ]
    then
        logerror "ERROR: failed to build java component $component"
        tail -500 /tmp/result.log
        exit 1
    fi
    set -e
done

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.java-producer.yml"

log "Produce avro data using Java producer"
docker exec producer bash -c "java -jar producer-1.0.0-jar-with-dependencies.jar"

log "Verify we have received the avro data in customer-avro topic"
timeout 60 docker exec connect kafka-avro-console-consumer -bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic customer-avro --from-beginning --max-messages 5

log "Produce avro data using kafka-avro-console-producer"
seq -f "{\"f1\": \"value%g\"}" 10 | docker exec -i connect kafka-avro-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic avro-topic --property value.schema='{"type":"record","name":"myrecord","fields":[{"name":"f1","type":"string"}]}'

log "Verify we have received the avro data in avro-topic topic"
timeout 60 docker exec connect kafka-avro-console-consumer -bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic avro-topic --from-beginning --max-messages 5
