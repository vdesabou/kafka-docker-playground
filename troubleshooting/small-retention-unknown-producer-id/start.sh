#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
export TAG=5.3.1
source ${DIR}/../../scripts/utils.sh

log "Using CP 5.3.1"
for component in producer consumer spring
do
     set +e
     log "🏗 Building jar for ${component}"
     docker run -i --rm -e KAFKA_CLIENT_TAG=$KAFKA_CLIENT_TAG -e TAG=$TAG_BASE -v "${PWD}/${component}":/usr/src/mymaven -v "$HOME/.m2":/root/.m2 -v "$PWD/../../scripts/settings.xml:/tmp/settings.xml" -v "${PWD}/${component}/target:/usr/src/mymaven/target" -w /usr/src/mymaven maven:3.6.1-jdk-11 mvn -s /tmp/settings.xml -Dkafka.tag=$TAG -Dkafka.client.tag=$KAFKA_CLIENT_TAG package > /tmp/result.log 2>&1
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
docker exec broker kafka-topics --create --topic testtopic --partitions 1 --replication-factor 1 --bootstrap-server broker:9092 --config retention.ms=30000 --config message.timestamp.type=CreateTime

log "create a topic outputtesttopic with 30 seconds retention"
docker exec broker kafka-topics --create --topic outputtesttopic --partitions 1 --replication-factor 1 --bootstrap-server broker:9092 --config retention.ms=30000 --config message.timestamp.type=CreateTime

log "Describe new topic testtopic"
docker exec zookeeper kafka-topics --describe --topic testtopic --bootstrap-server broker:9092

# not working, so hardcoding timestamp in record with 1581583089003 i.e 02/13/2020 @ 8:38am (UTC)
#log "Change timezone to US/Eastern in producer"
#docker exec producer bash -c "mv /etc/localtime /etc/localtime.bak && ln -s /usr/share/zoneinfo/US/Eastern /etc/localtime"

sleep 1

log "Run the Java producer, logs are in producer.log."
docker exec producer bash -c "java -jar producer-1.0.0-jar-with-dependencies.jar" > producer.log 2>&1 &

# log "Run the Java consumer"
# docker exec consumer bash -c "java -jar consumer-1.0.0-jar-with-dependencies.jar"
log "Run the Spring consumer"
docker exec spring bash -c "java -jar spring-kafka-hello-world-0.0.1-SNAPSHOT.jar"

# docker exec broker kafka-console-consumer --bootstrap-server broker:9092 --topic outputtesttopic --from-beginning --property print.key=true --property print.timestamp=true