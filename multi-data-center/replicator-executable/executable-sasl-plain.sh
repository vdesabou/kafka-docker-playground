#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if ! version_gt $TAG_BASE "5.3.99"; then
    log "Removing rest.extension.classes from properties files, otherwise getting Failed to find any class that implements interface org.apache.kafka.connect.rest.ConnectRestExtension and which name matches io.confluent.connect.replicator.monitoring.ReplicatorMonitoringExtension"
    head -n -1 replication-europe.properties > /tmp/temp.properties ; mv /tmp/temp.properties replication-europe.properties
    head -n -1 replication-us.properties > /tmp/temp.properties ; mv /tmp/temp.properties replication-us.properties
fi

playground start-environment --environment mdc-sasl-plain --docker-compose-override-file "${PWD}/docker-compose.mdc-sasl-plain.replicator.yml"

log "Sending sales in Europe cluster"
seq -f "european_sale_%g ${RANDOM}" 10 | docker container exec -i broker-europe kafka-console-producer --bootstrap-server localhost:9092 --topic sales_EUROPE --producer.config /etc/kafka/client.properties

log "Sending sales in US cluster"
seq -f "us_sale_%g ${RANDOM}" 10 | docker container exec -i broker-us kafka-console-producer --bootstrap-server localhost:9092 --topic sales_US --producer.config /etc/kafka/client.properties

playground container restart -c replicator-europe
playground container restart -c replicator-us

wait_container_ready replicator-us
wait_container_ready replicator-europe

sleep 120

log "Verify we have received the data in all the sales_ topics in EUROPE"
docker container exec broker-europe timeout 120 kafka-console-consumer --bootstrap-server localhost:9092 --include "sales_.*" --from-beginning --max-messages 20 --property metadata.max.age.ms 30000 --consumer.config /etc/kafka/client.properties

log "Verify we have received the data in all the sales_ topics in the US"
docker container exec broker-us timeout 120 kafka-console-consumer --bootstrap-server localhost:9092 --include "sales_.*" --from-beginning --max-messages 20 --property metadata.max.age.ms 30000 --consumer.config /etc/kafka/client.properties
