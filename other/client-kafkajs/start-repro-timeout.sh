#!/bin/bash

set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

docker-compose -f docker-compose-repro-timeout.yml down -v --remove-orphans
docker-compose -f docker-compose-repro-timeout.yml up -d --build

${DIR}/../../scripts/wait-for-connect-and-controlcenter.sh -a -b

log "Create a topic kafkajs"
docker exec broker1 kafka-topics --create --topic kafkajs --partitions 3 --replication-factor 3 --bootstrap-server broker:9092


log "Starting consumer. Logs are in consumer.log."
docker exec -i client-kafkajs node /usr/src/app/consumer.js > consumer.log 2>&1 &

log "Starting producer. Logs are in producer.log."
docker exec -i client-kafkajs node /usr/src/app/producer.js > producer.log 2>&1 &

log "Sleeping 15 seconds"
sleep 15

ip=$(docker inspect -f '{{.Name}} - {{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $(docker ps -aq) | grep client-kafkajs | cut -d " " -f 3)
log "Blocking IP address $ip corresponding to kafkaJS client"
docker exec -e ip=$ip --privileged --user root broker1 sh -c "iptables -A OUTPUT -p tcp -d $ip -j DROP"


log "Grepping for WARN|ERROR|Metadata|timed out|disconnect"
tail -f producer.log | egrep "WARN|ERROR|Metadata|timed out|disconnect" > results.log 2>&1 &

log "let the test run 5 minutes"
sleep 300

log "Unblocking IP address $ip corresponding to kafkaJS client"
docker exec -e ip=$ip --privileged --user root broker1 sh -c "iptables -D OUTPUT -p tcp -d $ip -j DROP"

log "let the test run 5 minutes"
sleep 300