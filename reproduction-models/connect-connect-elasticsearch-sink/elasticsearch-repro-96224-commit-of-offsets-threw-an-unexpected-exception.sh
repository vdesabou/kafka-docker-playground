#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

# As of version 11.0.0, the connector uses the Elasticsearch High Level REST Client (version 7.0.1),
# which means only Elasticsearch 7.x is supported.

export ELASTIC_VERSION="6.8.3"
if version_gt $CONNECTOR_TAG "10.9.9"
then
    log "Connector version is > 11.0.0, using Elasticsearch 7.x"
    export ELASTIC_VERSION="7.12.0"
fi

for component in producer-repro-96224
do
    set +e
    log "🏗 Building jar for ${component}"
    docker run -i --rm -e KAFKA_CLIENT_TAG=$KAFKA_CLIENT_TAG -e TAG=$TAG_BASE -v "${DIR}/${component}":/usr/src/mymaven -v "$HOME/.m2":/root/.m2 -v "${DIR}/${component}/target:/usr/src/mymaven/target" -w /usr/src/mymaven maven:3.6.1-jdk-11 mvn -Dkafka.tag=$TAG -Dkafka.client.tag=$KAFKA_CLIENT_TAG package > /tmp/result.log 2>&1
    if [ $? != 0 ]
    then
        logerror "ERROR: failed to build java component "
        tail -500 /tmp/result.log
        exit 1
    fi
    set -e
done

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.repro-96224-commit-of-offsets-threw-an-unexpected-exception.yml"


log "✨ Run the avro java producer which produces to topic customer_avro"
docker exec -d producer-repro-96224 bash -c "java ${JAVA_OPTS} -jar producer-1.0.0-jar-with-dependencies.jar > /dev/null 2>&1"

sleep 60

log "Creating Elasticsearch Sink connector (Elasticsearch version is $ELASTIC_VERSION)"
if version_gt $CONNECTOR_TAG "10.9.9"
then
     # 7.x
     curl -X PUT \
          -H "Content-Type: application/json" \
          --data '{
               "connector.class": "io.confluent.connect.elasticsearch.ElasticsearchSinkConnector",
               "tasks.max": "1",
               "topics": "customer_avro",
               "key.ignore": "true",
               "connection.url": "http://elasticsearch:9200",

               "batch.size" : "1000",
               "behavior.on.malformed.documents" : "warn",
               "flush.timeout.ms" : "360000",
               "max.buffered.records" : "1000",
               "max.retries" : "6000",
               "producer.override.request.timeout.ms" : "20000",
               "producer.override.retry.backoff.ms" : "500",
               "read.timeout.ms" : "30000",
               "retry.backoff.ms" : "100"
               }' \
          http://localhost:8083/connectors/elasticsearch-sink/config | jq .
else
     # 6.x
     curl -X PUT \
          -H "Content-Type: application/json" \
          --data '{
               "connector.class": "io.confluent.connect.elasticsearch.ElasticsearchSinkConnector",
               "tasks.max": "1",
               "topics": "customer_avro",
               "key.ignore": "true",
               "connection.url": "http://elasticsearch:9200",
               "type.name": "kafka-connect",

               "batch.size" : "1000",
               "behavior.on.malformed.documents" : "warn",
               "flush.timeout.ms" : "360000",
               "max.buffered.records" : "1000",
               "max.retries" : "6000",
               "producer.override.request.timeout.ms" : "20000",
               "producer.override.retry.backoff.ms" : "500",
               "read.timeout.ms" : "30000",
               "retry.backoff.ms" : "100"
               }' \
          http://localhost:8083/connectors/elasticsearch-sink/config | jq .
fi


sleep 30

log "Check that the data is available in Elasticsearch"
curl -XGET 'http://localhost:9200/customer_avro/_search?pretty' > /tmp/result.log  2>&1
cat /tmp/result.log
grep "f1" /tmp/result.log | grep "value1"
grep "f1" /tmp/result.log | grep "value10"


