#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"

source ${DIR}/../../scripts/utils.sh

for component in producer consumer
do
     set +e
     log "🏗 Building jar for ${component}"
     docker run -i --rm -e KAFKA_CLIENT_TAG=$KAFKA_CLIENT_TAG -e TAG=$TAG_BASE -v "${PWD}/${component}":/usr/src/mymaven -v "$HOME/.m2":/root/.m2 -v "$PWD/../../scripts/settings.xml:/tmp/settings.xml" -v "${PWD}/${component}/target:/usr/src/mymaven/target" -w /usr/src/mymaven maven:3.9.11-eclipse-temurin-11-alpine mvn -s /tmp/settings.xml -Dkafka.tag=$TAG -Dkafka.client.tag=$KAFKA_CLIENT_TAG package > /tmp/result.log 2>&1
     if [ $? != 0 ]
     then
          logerror "❌ failed to build java component $component"
          tail -500 /tmp/result.log
          exit 1
     fi
     set -e
done

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.yml"


log "create a topic testtopic with 30 seconds retention"
docker exec broker kafka-topics --create --topic testtopic --partitions 1 --replication-factor 1 --bootstrap-server broker:9092 --config retention.ms=30000 --config message.timestamp.type=LogAppendTime 

log "Describe new topic testtopic"
docker exec zookeeper kafka-topics --describe --topic testtopic --bootstrap-server broker:9092

sleep 1

log "Run the Java producer, logs are in producer.log."
docker exec producer bash -c "java -jar producer-1.0.0-jar-with-dependencies.jar" > producer.log 2>&1 &

sleep 60

log "Showing segments: 00000000000000000000.index should have been deleted by now"
docker exec broker ls -lrt /var/lib/kafka/data/testtopic-0/

# total 20
# -rw-r--r-- 1 appuser appuser  43 Jan 10 09:40 partition.metadata
# -rw-r--r-- 1 appuser appuser 462 Jan 10 09:40 00000000000000000000.log.deleted
# -rw-r--r-- 1 appuser appuser  12 Jan 10 09:41 00000000000000000000.timeindex.deleted
# -rw-r--r-- 1 appuser appuser   0 Jan 10 09:41 00000000000000000000.index.deleted
# -rw-r--r-- 1 appuser appuser  56 Jan 10 09:41 00000000000000000006.snapshot
# -rw-r--r-- 1 appuser appuser   8 Jan 10 09:41 leader-epoch-checkpoint
# -rw-r--r-- 1 appuser appuser   0 Jan 10 09:41 00000000000000000006.log


log "Run the Java consumer. Logs are in consumer.log."
docker exec consumer bash -c "java -jar consumer-1.0.0-jar-with-dependencies.jar" > consumer.log 2>&1 &


# [2022-01-10 09:54:26,519] INFO Received testtopic#0 offset = 6, key = null , value = message 0 , value = 1641808466506 (com.github.vdesabou.SimpleConsumer)
# [2022-01-10 09:54:27,514] INFO Received testtopic#0 offset = 7, key = null , value = message 1 , value = 1641808467512 (com.github.vdesabou.SimpleConsumer)
# [2022-01-10 09:54:28,517] INFO Received testtopic#0 offset = 8, key = null , value = message 2 , value = 1641808468515 (com.github.vdesabou.SimpleConsumer)
# [2022-01-10 09:54:29,521] INFO Received testtopic#0 offset = 9, key = null , value = message 3 , value = 1641808469520 (com.github.vdesabou.SimpleConsumer)
# [2022-01-10 09:54:30,532] INFO Received testtopic#0 offset = 10, key = null , value = message 4 , value = 1641808470522 (com.github.vdesabou.SimpleConsumer)
# [2022-01-10 09:54:31,528] INFO Received testtopic#0 offset = 11, key = null , value = message 5 , value = 1641808471527 (com.github.vdesabou.SimpleConsumer)