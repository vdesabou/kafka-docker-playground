#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

for component in producer-repro-107846
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

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.repro-107846-not-batching-records-as-expected.yml"

log "✨ Run the avro java producer which produces to topic customer_avro"
docker exec producer-repro-107846 bash -c "java ${JAVA_OPTS} -jar producer-1.0.0-jar-with-dependencies.jar"

log "-------------------------------------"
log "Running Simple (No) Authentication Example"
log "-------------------------------------"

log "Creating http-sink connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "topics": "customer_avro",
               "tasks.max": "1",
               "connector.class": "io.confluent.connect.http.HttpSinkConnector",
               "key.converter": "org.apache.kafka.connect.storage.StringConverter",
               "value.converter": "io.confluent.connect.avro.AvroConverter",
               "value.converter.schema.registry.url": "http://schema-registry:8081",
               "confluent.topic.bootstrap.servers": "broker:9092",
               "confluent.topic.replication.factor": "1",
               "reporter.bootstrap.servers": "broker:9092",
               "reporter.error.topic.name": "error-responses",
               "reporter.error.topic.replication.factor": 1,
               "reporter.result.topic.name": "success-responses",
               "reporter.result.topic.replication.factor": 1,
               "http.api.url": "http://http-service-no-auth:8080/api/messages",
               "request.body.format": "json",
               "batch.json.as.array": "true",
               "batch.max.size": "10",
               "transforms": "dropMyHeader",
               "transforms.dropMyHeader.type": "org.apache.kafka.connect.transforms.DropHeaders",
               "transforms.dropMyHeader.headers": "MyHeader"
          }' \
     http://localhost:8083/connectors/http-sink/config | jq .


sleep 10

log "Confirm that the data was sent to the HTTP endpoint."
curl localhost:8080/api/messages | jq . > /tmp/result.log  2>&1
cat /tmp/result.log
grep "10" /tmp/result.log

log "Check the success-responses topic"
timeout 60 docker exec broker kafka-console-consumer --bootstrap-server broker:9092 --topic success-responses --from-beginning --max-messages 10 --property print.headers=true
# input_record_offset:0,input_record_timestamp:1654161389868,input_record_partition:0,input_record_topic:customer_avro    "{\"id\":1,\"message\":\"[{\\\"count\\\":-5106534569952410475}]\"}"
# input_record_offset:1,input_record_timestamp:1654161391307,input_record_partition:0,input_record_topic:customer_avro    "{\"id\":2,\"message\":\"[{\\\"count\\\":-167885730524958550}]\"}"
# input_record_offset:2,input_record_timestamp:1654161392308,input_record_partition:0,input_record_topic:customer_avro    "{\"id\":3,\"message\":\"[{\\\"count\\\":4672433029010564658}]\"}"
# input_record_offset:3,input_record_timestamp:1654161393309,input_record_partition:0,input_record_topic:customer_avro    "{\"id\":4,\"message\":\"[{\\\"count\\\":-7216359497931550918}]\"}"
# input_record_offset:4,input_record_timestamp:1654161394313,input_record_partition:0,input_record_topic:customer_avro    "{\"id\":5,\"message\":\"[{\\\"count\\\":-3581075550420886390}]\"}"
# input_record_offset:5,input_record_timestamp:1654161395314,input_record_partition:0,input_record_topic:customer_avro    "{\"id\":6,\"message\":\"[{\\\"count\\\":-2298228485105199876}]\"}"
# input_record_offset:6,input_record_timestamp:1654161396315,input_record_partition:0,input_record_topic:customer_avro    "{\"id\":7,\"message\":\"[{\\\"count\\\":-5237980416576129062}]\"}"
# input_record_offset:7,input_record_timestamp:1654161397319,input_record_partition:0,input_record_topic:customer_avro    "{\"id\":8,\"message\":\"[{\\\"count\\\":1326634973105178603}]\"}"
# input_record_offset:8,input_record_timestamp:1654161398321,input_record_partition:0,input_record_topic:customer_avro    "{\"id\":9,\"message\":\"[{\\\"count\\\":-3758321679654915806}]\"}"
# input_record_offset:9,input_record_timestamp:1654161399323,input_record_partition:0,input_record_topic:customer_avro    "{\"id\":10,\"message\":\"[{\\\"count\\\":-7771300887898959616}]\"}"
# Processed a total of 10 messages

# There is no batching when header key is different for every message:
#                 String headerValue = "value" + id;
#                 record.headers().add(new RecordHeader("key",headerValue.getBytes()));