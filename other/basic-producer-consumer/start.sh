#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

mvn package -f "./kafka-producer-application/pom.xml"
mvn package -f "./kafka-consumer-application/pom.xml"

${DIR}/../../environment/plaintext/start.sh

log "Create topic output-topic"
docker exec broker kafka-topics --create --topic output-topic --bootstrap-server broker:9092 --replication-factor 1 --partitions 1

log "Start producer"
java -jar kafka-producer-application/target/kafka-producer-application-standalone-0.0.1-jar-with-dependencies.jar kafka-producer-application/configuration/dev.properties input.txt

log "Consume topic output-topic"
playground topic consume --topic output-topic --min-expected-messages 10 --timeout 60

# log "Create topic input-topic"
# docker exec broker kafka-topics --create --topic input-topic --bootstrap-server broker:9092 --replication-factor 1 --partitions 1

log "Start consumer for topic output-topic"
java -jar kafka-consumer-application/target/kafka-consumer-application-standalone-0.0.1-jar-with-dependencies.jar kafka-consumer-application/configuration/dev.properties