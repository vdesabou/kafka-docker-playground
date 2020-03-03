#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh


${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.yml"

log "create a topic testtopic with 30 seconds segment.ms"
docker exec broker kafka-topics --create --topic testtopic --partitions 1 --replication-factor 1 --zookeeper zookeeper:2181 --config segment.ms=30000 --config cleanup.policy=compact --config min.cleanable.dirty.ratio=0.0

# --config retention.ms=30000
# --config max.compaction.lag.ms=30000

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

log "Sleeping 40 seconds"
sleep 40

docker exec broker ls -lrt /var/lib/kafka/data/testtopic-0/

docker exec broker kafka-log-dirs --describe --bootstrap-server broker:9092 --topic-list 'testtopic'

log "Verify we have received the data in testtopic topic"
timeout 60 docker exec broker kafka-console-consumer --bootstrap-server broker:9092 --topic testtopic --from-beginning --property print.key=true --property key.separator=,

# Results:

# 11:26:40 Sending message key: <key0> and value <value0> to topic testtopic
# 11:26:44 Sending message key: <key1> and value <value1> to topic testtopic
# 11:26:49 Sending message key: <key0> and value <value2> to topic testtopic
# 11:26:54 Sending message key: <key1> and value <value3> to topic testtopic
# 11:26:59 Sending message key: <key0> and value <value4> to topic testtopic


# 11:27:49 Verify we have received the data in testtopic topic
# key0,value0
# key1,value1
# key0,value2
# key1,value3
# key0,value4