#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if ! version_gt $TAG_BASE "5.4.99"; then
    logwarn "WARN: JSON Schema is available since CP 5.5 only"
    exit 111
fi

for component in producer
do
    set +e
    log "🏗 Building jar for ${component}"
    docker run -i --rm -e KAFKA_CLIENT_TAG=$KAFKA_CLIENT_TAG -e TAG=$TAG_BASE -v "${DIR}/${component}":/usr/src/mymaven -v "$HOME/.m2":/root/.m2 -v "$PWD/../../scripts/settings.xml:/tmp/settings.xml" -v "${DIR}/${component}/target:/usr/src/mymaven/target" -w /usr/src/mymaven maven:3.6.1-jdk-11 mvn -s /tmp/settings.xml -Dkafka.tag=$TAG -Dkafka.client.tag=$KAFKA_CLIENT_TAG package > /tmp/result.log 2>&1
    if [ $? != 0 ]
    then
        logerror "ERROR: failed to build java component $component"
        tail -500 /tmp/result.log
        exit 1
    fi
    set -e
done

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.java-producer.yml"

log "Produce json-schema data using Java producer"
docker exec producer bash -c "java -jar producer-1.0.0-jar-with-dependencies.jar"

log "Verify we have received the json-schema data in customer-json-schema topic"
playground topic consume --topic customer-json-schema --min-expected-messages 5

log "Produce json-schema data using kafka-json-schema-console-producer"
seq -f "{\"f1\": \"value%g\"}" 10 | docker exec -i connect kafka-json-schema-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic json-schema-topic --property value.schema='{"type":"object","properties":{"f1":{"type":"string"}}}'

log "Verify we have received the json-schema data in json-schema-topic topic"
playground topic consume --topic json-schema-topic --min-expected-messages 5
