#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if [ ! -f ${DIR}/neo4j-streams-sink-tester-1.0.jar ]
then
     echo -e "\033[0;33mDownloading neo4j-streams-sink-tester-1.0.jar\033[0m"
     wget https://github.com/conker84/neo4j-streams-sink-tester/releases/download/1/neo4j-streams-sink-tester-1.0.jar
fi

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"

echo -e "\033[0;33mSending 1000 messages to topic my-topic using neo4j-streams-sink-teste\033[0m"
docker exec connect java -jar /tmp/neo4j-streams-sink-tester-1.0.jar -f AVRO -e 1000 -Dkafka.bootstrap.server=broker:9092 -Dkafka.schema.registry.url=http://schema-registry:8081


echo -e "\033[0;33mCreating NEO4J Sink connector\033[0m"
docker exec connect \
     curl -X PUT \
     -H "Content-Type: application/json" \
     --data @/tmp/contrib.sink.avro.neo4j.json \
     http://localhost:8083/connectors/neo4j-sink/config | jq .


sleep 5

echo -e "\033[0;33mVerify data is present in Neo4j http://127.0.0.1:7474 (neo4j/connect)\033[0m"
open "http://neo4j:connect@127.0.0.1:7474/"
