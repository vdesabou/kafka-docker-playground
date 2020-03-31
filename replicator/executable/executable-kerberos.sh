#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

${DIR}/../../environment/mdc-kerberos/start.sh "${PWD}/docker-compose.kerberos.yml" -a -b

log "Sending sales in Europe cluster"
seq -f "european_sale_%g ${RANDOM}" 10 | docker container exec -i client bash -c 'kinit -k -t /var/lib/secret/kafka-client.key kafka_producer && kafka-console-producer --broker-list broker-europe:9092 --topic sales_EUROPE --producer.config /etc/kafka/producer-europe.properties'

log "Sending sales in US cluster"
seq -f "us_sale_%g ${RANDOM}" 10 | docker container exec -i client bash -c 'kinit -k -t /var/lib/secret/kafka-client.key kafka_producer && kafka-console-producer --broker-list broker-us:9092 --topic sales_US --producer.config /etc/kafka/producer-us.properties'

log "Consolidating all sales in the US (logs are in /tmp/replicator.log):"
docker container exec -i connect-us bash -c 'kinit -k -t /var/lib/secret/kafka-connect.key connect'
# run in detach mode -d
docker exec -d connect-us bash -c 'replicator --consumer.config /etc/kafka/consumer-us.properties --producer.config /etc/kafka/producer-us.properties  --replication.config /etc/kafka/replication-us.properties  --cluster.id replicate-europe-to-us --whitelist sales_EUROPE > /tmp/replicator.log 2>&1'

log "Consolidating all sales in Europe (logs are in /tmp/replicator.log):"
docker container exec -i connect-europe bash -c 'kinit -k -t /var/lib/secret/kafka-connect.key connect'
# run in detach mode -d
docker exec -d connect-europe bash -c 'replicator --consumer.config /etc/kafka/consumer-europe.properties --producer.config /etc/kafka/producer-europe.properties  --replication.config /etc/kafka/replication-europe.properties  --cluster.id replicate-us-to-europe --whitelist sales_US > /tmp/replicator.log 2>&1'

log "sleeping 240 seconds"
sleep 240

log "Verify we have received the data in all the sales_ topics in EUROPE"
timeout 60 docker container exec -i client bash -c 'kinit -k -t /var/lib/secret/kafka-client.key kafka_consumer && kafka-console-consumer --bootstrap-server broker-europe:9092 --whitelist "sales_.*" --from-beginning --max-messages 20 --property metadata.max.age.ms 30000 --consumer.config /etc/kafka/consumer-europe.properties'

log "Verify we have received the data in all the sales_ topics in the US"
timeout 60 docker container exec -i client bash -c 'kinit -k -t /var/lib/secret/kafka-client.key kafka_consumer && kafka-console-consumer --bootstrap-server broker-us:9092 --whitelist "sales_.*" --from-beginning --max-messages 20 --property metadata.max.age.ms 30000 --consumer.config /etc/kafka/consumer-us.properties'

log "Copying replicator logs to /tmp/replicator-europe.log and /tmp/replicator-us.log"
docker cp connect-europe:/tmp/replicator.log /tmp/replicator-europe.log
docker cp connect-us:/tmp/replicator.log /tmp/replicator-us.log