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

log "Replicate in the US"

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
          "topic.regex": "sales.*"
          }' \
     http://localhost:8083/connectors/replicate-europe-to-us/config | jq .

sleep 60

log "Verify we have received the 10 NEMEA sales in US cluster"
docker container exec -i connect-europe bash -c "kafka-console-consumer --bootstrap-server broker-us:9092 --whitelist 'sales_NEMEA' --from-beginning --max-messages 10"

log "Verify we have received the 10 SEMEA sales in US cluster"
docker container exec -i connect-europe bash -c "kafka-console-consumer --bootstrap-server broker-us:9092 --whitelist 'sales_SEMEA' --from-beginning --max-messages 10"

log "Deleting topic sales_NEMEA in Europe cluster"
docker exec broker-europe kafka-topics --delete --topic sales_NEMEA --bootstrap-server broker-europe:9092

sleep 10

log "Verify topic is still present in US cluster"
docker exec broker-us kafka-topics --describe --topic sales_NEMEA --bootstrap-server broker-us:9092

log "Verify replicator can not find the sales_NEMEA topic anymore in th Europe cluster "
docker logs connect-us | grep ".*WARN.*Received unknown topic or partition error in fetch for partition sales_NEMEA.*"

log "Verify replication continues, sending 10 new sales in sales_SEMEA topic in Europe cluster"
seq -f "south_european_sale_new_%g `date +%s`" 10 | docker container exec -i connect-europe bash -c "kafka-console-producer --broker-list broker-europe:9092 --topic sales_SEMEA"

sleep 10

log "Verify we have received the 10 new SEMEA sales in US cluster"
docker container exec -i connect-europe bash -c "kafka-console-consumer --bootstrap-server broker-us:9092 --whitelist 'sales_SEMEA' --from-beginning --max-messages 20"

log "Re-creating topic sales_NEMEA topic in Europe cluster"
docker container exec -i broker-europe bash -c "kafka-topics --create --topic sales_NEMEA --bootstrap-server broker-europe:9092"

log "Verify replication continues, sending 10 new sales in sales_NEMEA topic in Europe cluster"
seq -f "north_european_sale_new_%g `date +%s`" 10 | docker container exec -i connect-europe bash -c "kafka-console-producer --broker-list broker-europe:9092 --topic sales_NEMEA"

sleep 10

log "Verify we have received the 10 NEMEA sales in US cluster"
docker container exec -i connect-europe bash -c "kafka-console-consumer --bootstrap-server broker-us:9092 --whitelist 'sales_NEMEA' --from-beginning --max-messages 20"
