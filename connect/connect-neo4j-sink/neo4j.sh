#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if [ ! -f ${DIR}/neo4j-streams-sink-tester-1.0.jar ]
then
     log "Downloading neo4j-streams-sink-tester-1.0.jar"
     wget https://github.com/conker84/neo4j-streams-sink-tester/releases/download/1/neo4j-streams-sink-tester-1.0.jar
fi

if [ -z "$CI" ]
then
    # not running with github actions
    # workaround for issue on linux, see https://github.com/vdesabou/kafka-docker-playground/issues/851#issuecomment-821151962
    chmod -R a+rw .
else
    # docker is run as runneradmin user, need to use sudo
    ls -lrt
    sudo chmod -R a+rw .
    ls -lrt
fi

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"

log "Sending 1000 messages to topic my-topic using neo4j-streams-sink-tester"
docker exec connect java -jar /tmp/neo4j-streams-sink-tester-1.0.jar -f AVRO -e 1000 -Dkafka.bootstrap.server=broker:9092 -Dkafka.schema.registry.url=http://schema-registry:8081


log "Creating NEO4J Sink connector"
docker exec connect curl -X PUT \
     -H "Content-Type: application/json" \
     --data @/tmp/contrib.sink.avro.neo4j.json \
     http://localhost:8083/connectors/neo4j-sink/config | jq .


sleep 5

log "Verify data is present in Neo4j using cypher-shell CLI"
docker exec -i neo4j cypher-shell -u neo4j -p connect > /tmp/result.log  2>&1 <<-EOF
MATCH (n) RETURN n;
EOF
cat /tmp/result.log
grep "AVRO" /tmp/result.log | grep "Surname A"

if [ -z "$CI" ]
then
     log "Verify data is present in Neo4j http://localhost:7474 (neo4j/connect), see README"
     open "http://localhost:7474/"
fi