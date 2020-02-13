#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if [ ! -f ${DIR}/producer/target/producer-1.0.0-jar-with-dependencies.jar ]
then
     log "Building jar for producer"
     docker run -it --rm -e TAG=$TAG -e KAFKA_CLIENT_TAG=$KAFKA_CLIENT_TAG -v "${DIR}/producer":/usr/src/mymaven -v "$HOME/.m2":/root/.m2 -v "${DIR}/producer/target:/usr/src/mymaven/target" -w /usr/src/mymaven maven:3.6.1-jdk-8 mvn package
fi

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.yml"

log "create a topic testtopic with 30 seconds retention and 15 seconds segment"
docker exec broker kafka-topics --create --topic testtopic --partitions 1 --replication-factor 1 --zookeeper zookeeper:2181 --config segment.ms=15000 --config retention.ms=30000 --config message.timestamp.type=CreateTime

# not working, so hardcoding timestamp in record with 1581583089003 i.e 02/13/2020 @ 8:38am (UTC)
#log "Change timezone to US/Eastern in producer"
#docker exec producer bash -c "mv /etc/localtime /etc/localtime.bak && ln -s /usr/share/zoneinfo/US/Eastern /etc/localtime"

sleep 1

log "Run the Java producer"
LOG1="/tmp/log.1"
docker exec producer bash -c "java -jar producer-1.0.0-jar-with-dependencies.jar" > $LOG1 2>&1

# docker exec broker kafka-console-consumer --bootstrap-server broker:9092 --topic testtopic --property print.key=true --property print.timestamp=true