#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh


${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.yml"

log "create a topic testtopic with 30 seconds segment.ms"
docker exec broker kafka-topics --create --topic testtopic --partitions 1 --replication-factor 1 --zookeeper zookeeper:2181 --config segment.ms=30000 --config cleanup.policy=compact --config min.cleanable.dirty.ratio=0.0

log "Describe new topic testtopic"
docker exec zookeeper kafka-topics --describe --topic testtopic --zookeeper zookeeper:2181

sleep 1

i=0
while [ $i -le 4 ]
do
  log "Sending message key: <key$(($i % 2))> and value <value$i> to topic testtopic"
docker exec -i broker kafka-console-producer --broker-list broker:9092 --topic testtopic --property parse.key=true --property key.separator=, << EOF
key$(($i % 2)),value$i
EOF
  sleep 1
  ((i++))
done

log "Check files on data dir: current log segment should be 0"
docker exec broker ls -lrt /var/lib/kafka/data/testtopic-0/

log "Sleeping 40 seconds"
sleep 40

log "Check files on data dir: current log segment is still 0 as idle"
docker exec broker ls -lrt /var/lib/kafka/data/testtopic-0/

# docker exec broker kafka-log-dirs --describe --bootstrap-server broker:9092 --topic-list 'testtopic'

log "Compaction times: if no ouput, there was no compaction"
set +e
docker container logs --tail=500 broker | grep kafka-log-cleaner-thread

log "Check data in topic: there was no compaction"
timeout 10 docker exec broker kafka-console-consumer --bootstrap-server broker:9092 --topic testtopic --from-beginning --property print.key=true --property key.separator=,

log "Inject one more message"
docker exec -i broker kafka-console-producer --broker-list broker:9092 --topic testtopic --property parse.key=true --property key.separator=, << EOF
key1,value5
EOF

sleep 2

log "Check files on data dir: log segment should be rolled"
docker exec broker ls -lrt /var/lib/kafka/data/testtopic-0/

sleep 20

log "Compaction times: check that compaction happened"
set +e
docker container logs --tail=500 broker | grep kafka-log-cleaner-thread

log "Check data in topic: there was compaction"
timeout 10 docker exec broker kafka-console-consumer --bootstrap-server broker:9092 --topic testtopic --from-beginning --property print.key=true --property key.separator=,
