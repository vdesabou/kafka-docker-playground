#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if ! version_gt $TAG_BASE "5.3.99"; then
    logwarn "WARN: proxy options are available since CP 5.4 only"
    exit 111
fi

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.proxy.yml"

IP=$(docker inspect -f '{{.Name}} - {{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $(docker ps -aq) | grep schema-registry | cut -d " " -f 3)
log "Blocking schema-registry $IP from connect to make sure proxy is used"
docker exec --privileged --user root connect bash -c "iptables -A INPUT -p tcp -s $IP -j DROP"

log "producing using --property proxy.host=nginx-proxy -property proxy.port=8888"
seq -f "{\"f1\": \"value%g\"}" 10 | docker exec -i connect kafka-avro-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic a-topic --property proxy.host=nginx-proxy -property proxy.port=8888 --property value.schema='{"type":"record","name":"myrecord","fields":[{"name":"f1","type":"string"}]}'

log "producing using --property schema.registry.proxy.host=nginx-proxy -property schema.registry.proxy.port=8888"
seq -f "{\"f1\": \"value%g\"}" 10 | docker exec -i connect kafka-avro-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic a-topic --property schema.registry.proxy.host=nginx-proxy -property schema.registry.proxy.port=8888 --property value.schema='{"type":"record","name":"myrecord","fields":[{"name":"f1","type":"string"}]}'

log "Verify data was sent to broker using --property proxy.host=nginx-proxy -property proxy.port=8888"
timeout 60 docker exec connect kafka-avro-console-consumer -bootstrap-server broker:9092 --property proxy.host=nginx-proxy -property proxy.port=8888 --property schema.registry.url=http://schema-registry:8081 --topic a-topic --from-beginning --max-messages 20

log "Verify data was sent to broker using --property schema.proxy.host=nginx-proxy -property schema.proxy.port=8888"
timeout 60 docker exec connect kafka-avro-console-consumer -bootstrap-server broker:9092 --property schema.registry.proxy.host=nginx-proxy -property schema.registry.proxy.port=8888 --property schema.registry.url=http://schema-registry:8081 --topic a-topic --from-beginning --max-messages 20


log "Creating FileStream Sink connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "tasks.max": "1",
               "connector.class": "FileStreamSink",
               "topics": "a-topic",
               "file": "/tmp/output.json",
               "key.converter": "org.apache.kafka.connect.storage.StringConverter",
               "value.converter": "io.confluent.connect.avro.AvroConverter",
               "value.converter.schema.registry.url": "http://schema-registry:8081",
               "value.converter.proxy.host": "nginx-proxy",
               "value.converter.proxy.port": "8888"
          }' \
     http://localhost:8083/connectors/filestream-sink/config | jq .


sleep 5

log "Verify we have received the data in file"
docker exec connect cat /tmp/output.json