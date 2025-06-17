#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if ! version_gt $TAG_BASE "5.3.99"; then
    log "Removing rest.extension.classes from properties files, otherwise getting Failed to find any class that implements interface org.apache.kafka.connect.rest.ConnectRestExtension and which name matches io.confluent.connect.replicator.monitoring.ReplicatorMonitoringExtension"
    head -n -1 replication-europe.properties > /tmp/temp.properties ; mv /tmp/temp.properties replication-europe.properties
    head -n -1 replication-us.properties > /tmp/temp.properties ; mv /tmp/temp.properties replication-us.properties
fi

${DIR}/../../environment/mdc-kerberos/start.sh "${PWD}/docker-compose.mdc-kerberos.yml"

log "Sending sales in Europe cluster"
seq -f "european_sale_%g ${RANDOM}" 10 | docker container exec -i client bash -c 'kinit -k -t /var/lib/secret/kafka-client.key kafka_producer && kafka-console-producer --bootstrap-server broker-europe:9092 --topic sales_EUROPE --producer.config /etc/kafka/producer-europe.properties'

log "Sending sales in US cluster"
seq -f "us_sale_%g ${RANDOM}" 10 | docker container exec -i client bash -c 'kinit -k -t /var/lib/secret/kafka-client.key kafka_producer && kafka-console-producer --bootstrap-server broker-us:9092 --topic sales_US --producer.config /etc/kafka/producer-us.properties'

log "Starting replicator instances"
docker compose -f ../../environment/mdc-plaintext/docker-compose.yml -f ../../environment/mdc-kerberos/docker-compose.kerberos.yml -f docker-compose.mdc-kerberos.replicator.yml up -d --quiet-pull

docker container exec -i replicator-us bash -c 'kinit -k -t /var/lib/secret/kafka-connect.key connect'
docker container exec -i replicator-europe bash -c 'kinit -k -t /var/lib/secret/kafka-connect.key connect'

wait_container_ready  replicator-us
wait_container_ready  replicator-europe

sleep 120

log "Verify we have received the data in all the sales_ topics in EUROPE"
docker container exec -i client bash -c 'kinit -k -t /var/lib/secret/kafka-client.key kafka_consumer && timeout 120 kafka-console-consumer --bootstrap-server broker-europe:9092 --include "sales_.*" --from-beginning --max-messages 20 --property metadata.max.age.ms 30000 --consumer.config /etc/kafka/consumer-europe.properties'

log "Verify we have received the data in all the sales_ topics in the US"
docker container exec -i client bash -c 'kinit -k -t /var/lib/secret/kafka-client.key kafka_consumer && timeout 120 kafka-console-consumer --bootstrap-server broker-us:9092 --include "sales_.*" --from-beginning --max-messages 20 --property metadata.max.age.ms 30000 --consumer.config /etc/kafka/consumer-us.properties'
