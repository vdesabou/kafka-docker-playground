#!/bin/bash

set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

docker-compose down -v --remove-orphans
docker-compose up -d --build

${DIR}/../../scripts/wait-for-connect-and-controlcenter.sh -a -b

log "Create a topic kafkajs"
docker exec broker1 kafka-topics --create --topic kafkajs --partitions 3 --replication-factor 3 --bootstrap-server broker:9092


log "Starting consumer. Logs are in consumer.log."
docker exec -i client-kafkajs node /usr/src/app/consumer.js > consumer.log 2>&1 &

log "Starting producer"
docker exec -i client-kafkajs node /usr/src/app/producer.js > producer.log 2>&1 &

exit 0

docker exec --privileged --user root client-kafkajs sh -c "iptables -A OUTPUT -p tcp --dport 9092 -j DROP"
docker exec --privileged --user root client-kafkajs sh -c "iptables -D OUTPUT -p tcp --dport 9092 -j DROP"