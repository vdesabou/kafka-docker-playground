#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh


# for component in producer-repro-107760
# do
#     set +e
#     log "🏗 Building jar for ${component}"
#     docker run -i --rm -e KAFKA_CLIENT_TAG=$KAFKA_CLIENT_TAG -e TAG=$TAG_BASE -v "${DIR}/${component}":/usr/src/mymaven -v "$HOME/.m2":/root/.m2 -v "${DIR}/${component}/target:/usr/src/mymaven/target" -w /usr/src/mymaven maven:3.6.1-jdk-11 mvn -Dkafka.tag=$TAG -Dkafka.client.tag=$KAFKA_CLIENT_TAG package > /tmp/result.log 2>&1
#     if [ $? != 0 ]
#     then
#         logerror "ERROR: failed to build java component "
#         tail -500 /tmp/result.log
#         exit 1
#     fi
#     set -e
# done

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.repro-107760-jsonparseexception-with-double-backslashs.yml"

#log "✨ Run the avro java producer which produces to topic a-topic-1"
#docker exec producer-repro-107760 bash -c "java ${JAVA_OPTS} -jar producer-1.0.0-jar-with-dependencies.jar"

# log "produce with kafkajs in background"
# docker exec -i client-kafkajs node /usr/src/app/producer.js > /dev/null 2>&1 &

log "Sending messages to topic a-topic-1"
cat repro-107760-payload-1.json | docker exec -i broker kafka-console-producer --broker-list broker:9092 --topic a-topic-1

OUTPUT_FILE="${CONNECT_CONTAINER_HOME_DIR}/data/ouput/file.json"

log "Creating FileStream Sink connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "tasks.max": "1",
               "connector.class": "FileStreamSink",
               "topics": "a-topic-1",
               "file": "/tmp/output.json",
               "key.converter": "org.apache.kafka.connect.storage.StringConverter",
               "value.converter": "org.apache.kafka.connect.json.JsonConverter",
               "value.converter.schemas.enable": "false"
          }' \
     http://localhost:8083/connectors/a-topic-1-sink/config | jq .


sleep 5

log "Verify we have received the data in file"
docker exec connect cat /tmp/output.json

log "Verify data with kafka-console-consumer"
timeout 60 docker exec connect kafka-console-consumer --bootstrap-server broker:9092 --topic a-topic-1 --from-beginning --max-messages 1
# {"xpath":"href=\\#day"}

log "Verify data with kafkacat"
docker exec kafkacat kafkacat -b broker:9092 -t a-topic-1 -o 0 -p 0 -c 1 -C -f '\nKey (%K bytes): %k\t\nValue (%S bytes): %s\nTimestamp: %T\tPartition: %p\tOffset: %o\n--\n'
# {"xpath": "href=\\#day"}



log "Sending messages to topic a-topic-2"
cat repro-107760-payload-2.json | docker exec -i broker kafka-console-producer --broker-list broker:9092 --topic a-topic-2

OUTPUT_FILE="${CONNECT_CONTAINER_HOME_DIR}/data/ouput/file.json"

log "Creating FileStream Sink connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "tasks.max": "1",
               "connector.class": "FileStreamSink",
               "topics": "a-topic-2",
               "file": "/tmp/output.json",
               "key.converter": "org.apache.kafka.connect.storage.StringConverter",
               "value.converter": "org.apache.kafka.connect.json.JsonConverter",
               "value.converter.schemas.enable": "false"
          }' \
     http://localhost:8083/connectors/a-topic-2-sink/config | jq .


sleep 5

log "Verify we have received the data in file"
docker exec connect cat /tmp/output.json

log "Verify data with kafka-console-consumer"
timeout 60 docker exec connect kafka-console-consumer --bootstrap-server broker:9092 --topic a-topic-2 --from-beginning --max-messages 1
# {"xpath":"href=\\#day"}

log "Verify data with kafkacat"
docker exec kafkacat kafkacat -b broker:9092 -t a-topic-2 -o 0 -p 0 -c 1 -C -f '\nKey (%K bytes): %k\t\nValue (%S bytes): %s\nTimestamp: %T\tPartition: %p\tOffset: %o\n--\n'
# {"xpath": "href=\\#day"}


log "Sending messages to topic a-topic-3"
cat repro-107760-payload-3.json | docker exec -i broker kafka-console-producer --broker-list broker:9092 --topic a-topic-3

OUTPUT_FILE="${CONNECT_CONTAINER_HOME_DIR}/data/ouput/file.json"

log "Creating FileStream Sink connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "tasks.max": "1",
               "connector.class": "FileStreamSink",
               "topics": "a-topic-3",
               "file": "/tmp/output.json",
               "key.converter": "org.apache.kafka.connect.storage.StringConverter",
               "value.converter": "org.apache.kafka.connect.json.JsonConverter",
               "value.converter.schemas.enable": "false"
          }' \
     http://localhost:8083/connectors/a-topic-3-sink/config | jq .


sleep 5

log "Verify we have received the data in file"
docker exec connect cat /tmp/output.json

log "Verify data with kafka-console-consumer"
timeout 60 docker exec connect kafka-console-consumer --bootstrap-server broker:9092 --topic a-topic-3 --from-beginning --max-messages 1
# {"xpath":"href=\\#day"}

log "Verify data with kafkacat"
docker exec kafkacat kafkacat -b broker:9092 -t a-topic-3 -o 0 -p 0 -c 1 -C -f '\nKey (%K bytes): %k\t\nValue (%S bytes): %s\nTimestamp: %T\tPartition: %p\tOffset: %o\n--\n'
# {"xpath": "href=\\#day"}