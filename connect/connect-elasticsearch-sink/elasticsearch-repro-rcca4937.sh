#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

for component in producer-v1
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


# As of version 11.0.0, the connector uses the Elasticsearch High Level REST Client (version 7.0.1),
# which means only Elasticsearch 7.x is supported.

export ELASTIC_VERSION="6.8.3"
if version_gt $CONNECTOR_TAG "10.9.9"
then
    log "Connector version is > 11.0.0, using Elasticsearch 7.x"
    export ELASTIC_VERSION="7.12.0"
fi

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.repro-rcca-4937.yml"

log "Run the Java producer-v1, with problematic header (byte[] { -17, -65,  -65 }), see KAFKA-10574"
docker exec producer-v1 bash -c "java -jar producer-v1-1.0.0-jar-with-dependencies.jar"

log "Creating Elasticsearch Sink connector (Elasticsearch version is $ELASTIC_VERSION"
if version_gt $CONNECTOR_TAG "10.9.9"
then
     # 7.x
     curl -X PUT \
          -H "Content-Type: application/json" \
          --data '{
               "connector.class": "io.confluent.connect.elasticsearch.ElasticsearchSinkConnector",
               "tasks.max": "1",
               "topics": "test-elasticsearch-sink",
               "key.ignore": "true",
               "connection.url": "http://elasticsearch:9200"
               }' \
          http://localhost:8083/connectors/elasticsearch-sink/config | jq .
else
     # 6.x
     curl -X PUT \
          -H "Content-Type: application/json" \
          --data '{
               "connector.class": "io.confluent.connect.elasticsearch.ElasticsearchSinkConnector",
               "tasks.max": "1",
               "topics": "test-elasticsearch-sink",
               "key.ignore": "true",
               "connection.url": "http://elasticsearch:9200",
               "type.name": "kafka-connect"
               }' \
          http://localhost:8083/connectors/elasticsearch-sink/config | jq .
fi


# log "Sending messages to topic test-elasticsearch-sink"
# seq -f "{\"f1\": \"value%g\"}" 10 | docker exec -i connect kafka-avro-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic test-elasticsearch-sink --property value.schema='{"type":"record","name":"myrecord","fields":[{"name":"f1","type":"string"}]}'

sleep 10

log "Check that the data is available in Elasticsearch"
curl -XGET 'http://localhost:9200/test-elasticsearch-sink/_search?pretty' > /tmp/result.log  2>&1
cat /tmp/result.log
grep "f1" /tmp/result.log | grep "value1"
grep "f1" /tmp/result.log | grep "value10"


