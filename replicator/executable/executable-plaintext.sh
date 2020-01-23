#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

${DIR}/../../environment/mdc-plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"

echo "Sending sales in Europe cluster"
seq -f "european_sale_%g ${RANDOM}" 10 | docker container exec -i broker-europe kafka-console-producer --broker-list localhost:9092 --topic sales_EUROPE

echo "Sending sales in US cluster"
seq -f "us_sale_%g ${RANDOM}" 10 | docker container exec -i broker-us kafka-console-producer --broker-list localhost:9092 --topic sales_US

echo "Consolidating all sales in the US (logs are in /tmp/replicator.log):"

# run in detach mode -d
docker exec -d connect-us bash -c 'replicator --consumer.config /etc/kafka/consumer-us.properties --producer.config /etc/kafka/producer-us.properties  --replication.config /etc/kafka/replication-us.properties  --cluster.id replicate-europe-to-us --whitelist sales_EUROPE > /tmp/replicator.log 2>&1'

echo "Consolidating all sales in Europe (logs are in /tmp/replicator.log):"

# run in detach mode -d
docker exec -d connect-europe bash -c 'replicator --consumer.config /etc/kafka/consumer-europe.properties --producer.config /etc/kafka/producer-europe.properties  --replication.config /etc/kafka/replication-europe.properties  --cluster.id replicate-us-to-europe --whitelist sales_US  > /tmp/replicator.log 2>&1'

echo "sleeping 240 seconds"
sleep 240

echo "Verify we have received the data in all the sales_ topics in EUROPE"
timeout 60 docker container exec broker-europe kafka-console-consumer --bootstrap-server localhost:9092 --whitelist "sales_.*" --from-beginning --max-messages 20 --property metadata.max.age.ms 30000

echo "Verify we have received the data in all the sales_ topics in the US"
timeout 60 docker container exec broker-us kafka-console-consumer --bootstrap-server localhost:9092 --whitelist "sales_.*" --from-beginning --max-messages 20 --property metadata.max.age.ms 30000

echo "Copying replicator logs to /tmp/replicator-europe.log and /tmp/replicator-us.log"
docker cp connect-europe:/tmp/replicator.log /tmp/replicator-europe.log
docker cp connect-us:/tmp/replicator.log /tmp/replicator-us.log