#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

${DIR}/../../environment/mdc-plaintext/start.sh "${PWD}/docker-compose.plaintext.auto-create-topics-disabled.yml"

log "Creating topic sales_NEMEA topic in Europe cluster"
docker container exec -i broker-europe bash -c "kafka-topics --create --topic sales_NEMEA --bootstrap-server broker-europe:9092"

log "Creating topic sales_SEMEA topic in Europe cluster"
docker container exec -i broker-europe bash -c "kafka-topics --create --topic sales_SEMEA --bootstrap-server broker-europe:9092"


log "Sending 10 sales in sales_NEMEA topic in Europe cluster"
seq -f "north_european_sale_%g `date +%s`" 10 | docker container exec -i connect-europe bash -c "kafka-console-producer --broker-list broker-europe:9092 --topic sales_NEMEA"

log "Sending 10 sales in sales_SEMEA topic in Europe cluster"
seq -f "south_european_sale_%g `date +%s`" 10 | docker container exec -i connect-europe bash -c "kafka-console-producer --broker-list broker-europe:9092 --topic sales_SEMEA"

log "Replicate sales_NEMEA in the US using topic.whitelist"

docker container exec connect-us \
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
          "connector.class":"io.confluent.connect.replicator.ReplicatorSourceConnector",
          "key.converter": "io.confluent.connect.replicator.util.ByteArrayConverter",
          "value.converter": "io.confluent.connect.replicator.util.ByteArrayConverter",
          "header.converter": "io.confluent.connect.replicator.util.ByteArrayConverter",
          "src.consumer.group.id": "replicate-europe-to-us",
          "src.kafka.bootstrap.servers": "broker-europe:9092",
          "dest.kafka.bootstrap.servers": "broker-us:9092",
          "confluent.topic.replication.factor": 1,
          "provenance.header.enable": true,
          "topic.whitelist": "sales_NEMEA"
          }' \
     http://localhost:8083/connectors/replicate-nemea-to-us/config | jq .

log "Replicate sales_SEMEA in the US using topic.regex"
docker container exec connect-us \
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
          "connector.class":"io.confluent.connect.replicator.ReplicatorSourceConnector",
          "key.converter": "io.confluent.connect.replicator.util.ByteArrayConverter",
          "value.converter": "io.confluent.connect.replicator.util.ByteArrayConverter",
          "header.converter": "io.confluent.connect.replicator.util.ByteArrayConverter",
          "src.consumer.group.id": "replicate-europe-to-us",
          "src.kafka.bootstrap.servers": "broker-europe:9092",
          "dest.kafka.bootstrap.servers": "broker-us:9092",
          "confluent.topic.replication.factor": 1,
          "provenance.header.enable": true,
          "topic.regex": "sales_SEMEA",
          "topic.poll.interval.ms": "10000"
          }' \
     http://localhost:8083/connectors/replicate-semea-to-us/config | jq .

sleep 60

log "Verify we have received the 10 NEMEA sales in US cluster"
docker container exec -i connect-europe bash -c "kafka-console-consumer --bootstrap-server broker-us:9092 --whitelist 'sales_NEMEA' --from-beginning --max-messages 10"

log "Verify we have received the 10 SEMEA sales in US cluster"
docker container exec -i connect-europe bash -c "kafka-console-consumer --bootstrap-server broker-us:9092 --whitelist 'sales_SEMEA' --from-beginning --max-messages 10"

log "Deleting topic sales_NEMEA in Europe cluster"
docker exec broker-europe kafka-topics --delete --topic sales_NEMEA --bootstrap-server broker-europe:9092

sleep 5

log "Verify topic is still present in US cluster"
docker exec broker-us kafka-topics --describe --topic sales_NEMEA --bootstrap-server broker-us:9092

log "Verify replicator can not find the sales_NEMEA topic anymore in th Europe cluster (the connector does not stop to produce a warning message)"
docker logs connect-us | grep ".*WARN \[replicate-nemea-to-us.*\].*"

log "Verify the connector's status is FAILED"
docker container exec connect-us curl -X GET http://localhost:8083/connectors/replicate-nemea-to-us/status | jq

log "Restarting NEMEA replictor, Connector is status FAILED and Task is RUNNING"
docker container exec connect-us curl -X POST http://localhost:8083/connectors/replicate-nemea-to-us/restart

log "Verify the connector's status is still FAILED but task is running"
docker container exec connect-us curl -X GET http://localhost:8083/connectors/replicate-nemea-to-us/status | jq

log "Deleting topic sales_SEMEA in Europe cluster"
docker exec broker-europe kafka-topics --delete --topic sales_SEMEA --bootstrap-server broker-europe:9092

sleep 10

log "Verify topic is still present in US cluster"
docker exec broker-us kafka-topics --describe --topic sales_SEMEA --bootstrap-server broker-us:9092

log "Verify replicator stops to look for sales_SEMEA topic in th Europe cluster (after topic.poll.interval.ms, the connector updates the config and stops to look for this topic."
docker logs connect-us | grep ".*WARN \[replicate-semea-to-us.*\].*"

log "Verify the connector's status is RUNNING"
docker container exec connect-us curl -X GET http://localhost:8083/connectors/replicate-semea-to-us/status | jq
