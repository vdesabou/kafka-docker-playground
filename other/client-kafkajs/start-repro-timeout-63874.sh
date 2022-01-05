#!/bin/bash

set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

docker-compose -f docker-compose-repro-timeout-63874.yml down -v --remove-orphans
docker-compose -f docker-compose-repro-timeout-63874.yml up -d --build

# make sure control-center is not disabled
unset DISABLE_CONTROL_CENTER

${DIR}/../../scripts/wait-for-connect-and-controlcenter.sh -a -b

log "Create a topic kafkajs"
docker exec broker1 bash -c "KAFKA_OPTS="";kafka-topics --create --topic kafkajs --partitions 3 --replication-factor 3 --bootstrap-server broker:9092"

log "Starting consumer. Logs are in consumer.log."
docker exec -i client-kafkajs node /usr/src/app/consumer.js > consumer.log 2>&1 &

log "Starting producer. Logs are in producer.log."
docker exec -i client-kafkajs node /usr/src/app/producer.js > producer.log 2>&1 &

log "Sleeping 60 seconds"
sleep 60

ip=$(docker inspect -f '{{.Name}} - {{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $(docker ps -aq) | grep client-kafkajs | cut -d " " -f 3)
log "Simulate a 45 seconds network issue with broker1 by blocking output traffic from broker1 to kafkaJS producer container"
docker exec -e ip=$ip --privileged --user root broker1 sh -c "KAFKA_OPTS="";iptables -A OUTPUT -p tcp -d $ip -j DROP"

sleep 45

log "Setting back traffic to normal"
docker exec -e ip=$ip --privileged --user root broker1 sh -c "KAFKA_OPTS="";iptables -D OUTPUT -p tcp -d $ip -j DROP"

log "let the test run 1 minute"
sleep 60

log "Stop broker1"
docker stop broker1

log "Wait 60 seconds"
sleep 60

log "Start broker1"
docker start broker1