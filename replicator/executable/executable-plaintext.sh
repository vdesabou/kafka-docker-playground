#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"

${DIR}/../../environment/mdc-plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"

echo "Sending sales in Europe cluster"
seq -f "european_sale_%g ${RANDOM}" 10 | docker container exec -i broker-europe kafka-console-producer --broker-list localhost:9092 --topic sales_EUROPE

echo "Sending sales in US cluster"
seq -f "us_sale_%g ${RANDOM}" 10 | docker container exec -i broker-us kafka-console-producer --broker-list localhost:9092 --topic sales_US

echo Consolidating all sales in the US

# run in detach mode -d
docker exec -d connect-us bash -c 'replicator --consumer.config /etc/kafka/consumer-us.properties --producer.config /etc/kafka/producer-us.properties  --replication.config /etc/kafka/replication-us.properties  --cluster.id replicate-europe-to-us --whitelist sales_EUROPE'

echo Consolidating all sales in Europe

# run in detach mode -d
docker exec -d connect-europe bash -c 'replicator --consumer.config /etc/kafka/consumer-europe.properties --producer.config /etc/kafka/producer-europe.properties  --replication.config /etc/kafka/replication-europe.properties  --cluster.id replicate-us-to-europe --whitelist sales_US'

echo "sleeping 120 seconds"
sleep 120

echo "Verify we have received the data in all the sales_ topics in EUROPE"
docker container exec broker-europe kafka-console-consumer --bootstrap-server broker-europe:9092 --whitelist "sales_.*" --from-beginning --max-messages 20 --property metadata.max.age.ms 30000

echo "Verify we have received the data in all the sales_ topics in the US"
docker container exec broker-europe kafka-console-consumer --bootstrap-server broker-europe:9092 --whitelist "sales_.*" --from-beginning --max-messages 20 --property metadata.max.age.ms 30000

