#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"

source ${DIR}/../../scripts/utils.sh

for component in producer
do
     set +e
     log "🏗 Building jar for ${component}"
     docker run -i --rm -e KAFKA_CLIENT_TAG=$KAFKA_CLIENT_TAG -e TAG=$TAG_BASE -v "${DIR}/${component}":/usr/src/mymaven -v "$HOME/.m2":/root/.m2 -v "${DIR}/${component}/target:/usr/src/mymaven/target" -w /usr/src/mymaven maven:3.6.1-jdk-11 mvn -Dkafka.tag=$TAG -Dkafka.client.tag=$KAFKA_CLIENT_TAG package > /tmp/result.log 2>&1
     if [ $? != 0 ]
     then
          logerror "ERROR: failed to build java component $component"
          tail -500 /tmp/result.log
          exit 1
     fi
     set -e
done

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"


log "create a topic testtopic with 30 seconds retention"
docker exec broker kafka-topics --create --topic testtopic --partitions 1 --replication-factor 1 --bootstrap-server broker:9092 --config retention.ms=30000

log "Describe new topic testtopic"
docker exec zookeeper kafka-topics --describe --topic testtopic --bootstrap-server broker:9092

sleep 1

log "Run the Java producer, logs are in producer.log."
docker exec producer bash -c "java -jar producer-1.0.0-jar-with-dependencies.jar" > producer.log 2>&1 &

sleep 60

log "Showing segments: 00000000000000000000.index should have been deleted by now"
docker exec broker ls -lrt /var/lib/kafka/data/testtopic-0/

# With microsecond timestamp 1581583089003000L
# total 8
# -rw-r--r-- 1 appuser appuser        0 Jan  7 14:34 leader-epoch-checkpoint
# -rw-r--r-- 1 appuser appuser 10485760 Jan  7 14:34 00000000000000000000.index
# -rw-r--r-- 1 appuser appuser       43 Jan  7 14:34 partition.metadata
# -rw-r--r-- 1 appuser appuser 10485756 Jan  7 14:34 00000000000000000000.timeindex
# -rw-r--r-- 1 appuser appuser      462 Jan  7 14:34 00000000000000000000.log

# With millisecond timestamp 1581583089003L
# total 20
# -rw-r--r-- 1 appuser appuser       43 Jan  7 14:37 partition.metadata
# -rw-r--r-- 1 appuser appuser      462 Jan  7 14:37 00000000000000000000.log.deleted
# -rw-r--r-- 1 appuser appuser       12 Jan  7 14:37 00000000000000000000.timeindex.deleted
# -rw-r--r-- 1 appuser appuser        0 Jan  7 14:37 00000000000000000000.index.deleted
# -rw-r--r-- 1 appuser appuser       56 Jan  7 14:37 00000000000000000006.snapshot
# -rw-r--r-- 1 appuser appuser        0 Jan  7 14:37 00000000000000000006.log
# -rw-r--r-- 1 appuser appuser        8 Jan  7 14:37 leader-epoch-checkpoint
# -rw-r--r-- 1 appuser appuser 10485756 Jan  7 14:38 00000000000000000006.timeindex

log "Configure topic testtopic with message.timestamp.type=LogAppendTime"
docker exec broker kafka-configs --alter --topic testtopic --add-config message.timestamp.type=LogAppendTime --bootstrap-server broker:9092

log "Run the Java producer, logs are in producer.log."
docker exec producer bash -c "java -jar producer-1.0.0-jar-with-dependencies.jar" > producer.log 2>&1 &

sleep 60

log "Showing segments: 00000000000000000000.index should have been deleted by now"
docker exec broker ls -lrt /var/lib/kafka/data/testtopic-0/

# it does not trigger deletion:

# total 8
# -rw-r--r-- 1 appuser appuser       43 Jan 10 08:31 partition.metadata
# -rw-r--r-- 1 appuser appuser        0 Jan 10 08:31 leader-epoch-checkpoint
# -rw-r--r-- 1 appuser appuser 10485756 Jan 10 08:31 00000000000000000000.timeindex
# -rw-r--r-- 1 appuser appuser 10485760 Jan 10 08:31 00000000000000000000.index
# -rw-r--r-- 1 appuser appuser      924 Jan 10 08:39 00000000000000000000.log