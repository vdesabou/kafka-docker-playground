#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh


${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.yml"

log "create a topic testtopic with 30 seconds retention"
docker exec broker kafka-topics --create --topic testtopic --partitions 1 --replication-factor 1 --zookeeper zookeeper:2181 --config retention.ms=30000

log "Describe new topic testtopic"
docker exec zookeeper kafka-topics --describe --topic testtopic --zookeeper zookeeper:2181

sleep 1

log "Sending message to topic testtopic"
docker exec -i broker kafka-console-producer --broker-list broker:9092 --topic testtopic << EOF
This is my message
EOF

docker exec broker ls -lrt /var/lib/kafka/data/testtopic-0/

sleep 60

log "Sending message to topic testtopic"
docker exec -i broker kafka-console-producer --broker-list broker:9092 --topic testtopic << EOF
This is my message 2
EOF

sleep 10

docker exec broker ls -lrt /var/lib/kafka/data/testtopic-0/