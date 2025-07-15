#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh


PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.yml"

log "create a topic testtopic with 1 hour segment.ms, 100% dirty ratio and 10s max.compaction.lag.ms"
docker exec broker kafka-topics --create --topic testtopic --partitions 1 --replication-factor 1  --config cleanup.policy=compact --bootstrap-server broker:9092 --config segment.ms=3600000 --config min.cleanable.dirty.ratio=1.0 --config max.compaction.lag.ms=10000

log "Describe new topic testtopic"
docker exec zookeeper kafka-topics --describe --topic testtopic --bootstrap-server broker:9092

sleep 1

for i in {0..4}
do
  key=$(($i % 2))
  timestamp=$(date +%s)
  log "$timestamp - Sending message key: $key and value $i to topic testtopic"
  docker exec -i broker kafka-console-producer --bootstrap-server broker:9092 --topic testtopic --property parse.key=true --property key.separator=, << EOF
  $key,$i
EOF
  sleep 1  
done

sleep 15

log "Check files on data dir: should contain multiple log segments because max.compaction.lag.ms forced a roll"
docker exec broker ls -lrt /var/lib/kafka/data/testtopic-0/

log "Check compaction: should have reduced the log size"
docker container logs --tail=500 broker | grep "size reduction"

log "Check compaction messages: should contain 3 messages (0,2), (1,3) in a compacted segment and (0,4) in the active segment"
docker exec broker kafka-console-consumer --bootstrap-server broker:9092 --topic testtopic --from-beginning --property print.key=true --property key.separator=, --property print.timestamp=true --max-messages 3
# Note that despite having max.compaction.lag.ms without a new message, the active segment is not rolled and the compaction is not triggered which explains (0,2) and (0,4) not compacted
