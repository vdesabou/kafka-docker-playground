#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if ! version_gt $TAG_BASE "5.99.99"; then
    logwarn "WARN: JDK 11 is required for new versions"
    exit 111
fi

if [ ! -f ${DIR}/neo4j-streams-sink-tester-1.0.jar ]
then
     log "Downloading neo4j-streams-sink-tester-1.0.jar"
     wget -q https://github.com/conker84/neo4j-streams-sink-tester/releases/download/1/neo4j-streams-sink-tester-1.0.jar
fi

if [[ "$OSTYPE" == "darwin"* ]]
then
    # workaround for issue on linux, see https://github.com/vdesabou/kafka-docker-playground/issues/851#issuecomment-821151962
    chmod -R a+rw .
else
    # on CI, docker is run as runneradmin user, need to use sudo
    ls -lrt
    sudo chmod -R a+rw .
    ls -lrt
fi

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.yml"

log "Sending 1000 messages to topic my-topic using neo4j-streams-sink-tester"
docker exec connect java -jar /tmp/neo4j-streams-sink-tester-1.0.jar -f AVRO -e 1000 -Dkafka.bootstrap.server=broker:9092 -Dkafka.schema.registry.url=http://schema-registry:8081


log "Creating NEO4J Sink connector"
docker exec connect curl -X PUT \
     -H "Content-Type: application/json" \
     --data @/tmp/contrib.sink.avro.neo4j.json \
     http://localhost:8083/connectors/neo4j-sink/config | jq .


sleep 15

log "Verify data is present in Neo4j using cypher-shell CLI"
docker exec -i neo4j cypher-shell -u neo4j -p connect << EOF
MATCH (n) RETURN n;
EOF
docker exec -i neo4j cypher-shell -u neo4j -p connect > /tmp/result.log <<-EOF
MATCH (n) RETURN n;
EOF
cat /tmp/result.log
grep "AVRO" /tmp/result.log | grep "Surname A"

if [ -z "$GITHUB_RUN_NUMBER" ]
then
     log "Verify data is present in Neo4j http://localhost:7474 (neo4j/connect), see README"
     open "http://localhost:7474/"
fi
