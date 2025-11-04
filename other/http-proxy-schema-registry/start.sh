#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if ! version_gt $TAG_BASE "5.3.99"; then
    logwarn "proxy options are available since CP 5.4 only"
    exit 111
fi

for component in producer
do
    set +e
    log "🏗 Building jar for ${component}"
    docker run -i --rm -e KAFKA_CLIENT_TAG=$KAFKA_CLIENT_TAG -e TAG=$TAG_BASE -v "${PWD}/${component}":/usr/src/mymaven -v "$HOME/.m2":/root/.m2 -v "$PWD/../../scripts/settings.xml:/tmp/settings.xml" -v "${PWD}/${component}/target:/usr/src/mymaven/target" -w /usr/src/mymaven maven:3.9.11-eclipse-temurin-11 mvn -s /tmp/settings.xml -Dkafka.tag=$TAG -Dkafka.client.tag=$KAFKA_CLIENT_TAG package > /tmp/result.log 2>&1
    if [ $? != 0 ]
    then
        logerror "❌ failed to build java component $component"
        tail -500 /tmp/result.log
        exit 1
    fi
    set -e
done

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.proxy.yml"

IP=$(docker inspect -f '{{.Name}} - {{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $(docker ps -aq) | grep schema-registry | cut -d " " -f 3)
log "Blocking schema-registry $IP from connect to make sure proxy is used"
docker exec --privileged --user root connect bash -c "iptables -A INPUT -p tcp -s $IP -j DROP"

log "producing using --property proxy.host=nginx-proxy -property proxy.port=8888"
seq -f "{\"f1\": \"value%g\"}" 10 | docker exec -i connect kafka-avro-console-producer --bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic a-topic --property proxy.host=nginx-proxy -property proxy.port=8888 --property value.schema='{"type":"record","name":"myrecord","fields":[{"name":"f1","type":"string"}]}'

log "producing using --property schema.registry.proxy.host=nginx-proxy -property schema.registry.proxy.port=8888"
seq -f "{\"f1\": \"value%g\"}" 10 | docker exec -i connect kafka-avro-console-producer --bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic a-topic --property schema.registry.proxy.host=nginx-proxy -property schema.registry.proxy.port=8888 --property value.schema='{"type":"record","name":"myrecord","fields":[{"name":"f1","type":"string"}]}'

log "Verify data was sent to broker using --property proxy.host=nginx-proxy -property proxy.port=8888"
timeout 60 docker exec connect kafka-avro-console-consumer -bootstrap-server broker:9092 --property proxy.host=nginx-proxy -property proxy.port=8888 --property schema.registry.url=http://schema-registry:8081 --topic a-topic --from-beginning --max-messages 20

log "Verify data was sent to broker using --property schema.proxy.host=nginx-proxy -property schema.proxy.port=8888"
timeout 60 docker exec connect kafka-avro-console-consumer -bootstrap-server broker:9092 --property schema.registry.proxy.host=nginx-proxy -property schema.registry.proxy.port=8888 --property schema.registry.url=http://schema-registry:8081 --topic a-topic --from-beginning --max-messages 20


log "Creating FileStream Sink connector"
playground connector create-or-update --connector filestream-sink  << EOF
{
    "tasks.max": "1",
    "connector.class": "org.apache.kafka.connect.file.FileStreamSinkConnector",
    "topics": "a-topic",
    "file": "/tmp/output.json",
    "key.converter": "org.apache.kafka.connect.storage.StringConverter",
    "value.converter": "io.confluent.connect.avro.AvroConverter",
    "value.converter.schema.registry.url": "http://schema-registry:8081",
    "value.converter.proxy.host": "nginx-proxy",
    "value.converter.proxy.port": "8888"
}
EOF


sleep 5

log "Verify we have received the data in file"
docker exec connect cat /tmp/output.json


log "Produce avro data using Java producer"
docker exec producer bash -c "java -jar producer-1.0.0-jar-with-dependencies.jar"

log "Verify data was sent to broker using --property proxy.host=nginx-proxy -property proxy.port=8888"
timeout 60 docker exec connect kafka-avro-console-consumer -bootstrap-server broker:9092 --property proxy.host=nginx-proxy -property proxy.port=8888 --property schema.registry.url=http://schema-registry:8081 --topic customer-avro --from-beginning --max-messages 10

# {"count":-5106534569952410475,"first_name":"eOMtThyhVNL","last_name":"WUZNRcBaQKxIye","address":"dUsF"}
# {"count":-167885730524958550,"first_name":"wdkelQbxe","last_name":"TeQOvaScfqIO","address":"OmaaJxkyvRnLR"}
# {"count":4672433029010564658,"first_name":"YtGKbgicZaH","last_name":"CB","address":"RQDSxVLhpfQG"}
# {"count":-7216359497931550918,"first_name":"TMDYpsBZx","last_name":"vfBoeygjbUMaA","address":"IKK"}
# {"count":-3581075550420886390,"first_name":"IkknjWEXJUfPxx","last_name":"Q","address":"H"}
# {"count":-2298228485105199876,"first_name":"eW","last_name":"KEJdpH","address":"YZGhtgdntugzv"}
# {"count":-5237980416576129062,"first_name":"vKAXLhMLl","last_name":"NgNfZB","address":"dyFG"}
# {"count":1326634973105178603,"first_name":"Raj","last_name":"VfJN","address":"onEnOin"}
# {"count":-3758321679654915806,"first_name":"ZjUfzQh","last_name":"dgL","address":"LfDTDGspD"}
# {"count":-7771300887898959616,"first_name":"b","last_name":"QvBQYuxiXX","address":"VytGCxzVll"}