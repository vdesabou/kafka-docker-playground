#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if [ ! -f ${DIR}/producer/target/producer-1.0.0-jar-with-dependencies.jar ]
then
     log "Building jar for producer"
     docker run -it --rm -e TAG=$TAG_BASE -e KAFKA_CLIENT_TAG=$KAFKA_CLIENT_TAG -v "${DIR}/producer":/usr/src/mymaven -v "$HOME/.m2":/root/.m2 -v "${DIR}/producer/target:/usr/src/mymaven/target" -w /usr/src/mymaven maven:3.6.1-jdk-11 mvn package
fi

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.yml"

log "create a topic testtopic with 30 seconds retention"
docker exec broker kafka-topics --create --topic testtopic --partitions 1 --replication-factor 1 --zookeeper zookeeper:2181 --config retention.ms=30000

# log "create a topic testtopic with 30 seconds retention and message.timestamp.type=LogAppendTime"
# docker exec broker kafka-topics --create --topic testtopic --partitions 1 --replication-factor 1 --zookeeper zookeeper:2181 --config retention.ms=30000 --config message.timestamp.type=LogAppendTime

log "Describe new topic testtopic"
docker exec zookeeper kafka-topics --describe --topic testtopic --zookeeper zookeeper:2181

sleep 1

log "Run the Java producer, it sends one request per second and uses old timestamps. Logs are in producer.log."
docker exec producer bash -c "java -jar producer-1.0.0-jar-with-dependencies.jar" > producer.log 2>&1 &

sleep 60

docker exec broker ls -lrt /var/lib/kafka/data/testtopic-0/