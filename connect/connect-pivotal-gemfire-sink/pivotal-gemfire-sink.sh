#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

# Need to create the docker image using https://github.com/GSSJacky/gemfire-docker

if [ ! -f ${DIR}/docker-pivotal-gemfire/pivotal-gemfire.tgz ]
then
     logerror "ERROR: ${DIR}/docker-pivotal-gemfire/ does not contain file pivotal-gemfire.tgz"
     exit 1
fi

if test -z "$(docker images -q pivotal-gemfire:latest)"
then
     log "Building pivotal-gemfire docker image..it can take a while..."
     OLDDIR=$PWD
     cd ${DIR}/docker-pivotal-gemfire
     docker build --build-arg PIVOTAL_GEMFIRE_VERSION=9.10.2 -t pivotal-gemfire:latest .
     cd ${OLDDIR}
fi

if [ -z "$KSQLDB" ]
then
     ${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"
else
     ${DIR}/../../ksqldb/environment/start.sh "${PWD}/docker-compose.plaintext.yml"
fi

log "Starting up locator"
docker exec -i pivotal-gemfire sh /opt/pivotal/workdir/startLocator.sh
log "Starting up server1"
docker exec -i pivotal-gemfire sh /opt/pivotal/workdir/startServer1.sh
log "Starting up server2"
docker exec -i pivotal-gemfire sh /opt/pivotal/workdir/startServer2.sh

sleep 8

log "Sending messages to topic input_topic"
docker exec -i connect kafka-avro-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic input_topic --property value.schema='{"type":"record","name":"myrecord","fields":[{"name":"f1","type":"string"}]}' << EOF
{"f1": "value1"}
{"f1": "value2"}
{"f1": "value3"}
EOF

log "Creating Pivotal Gemfire sink connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.confluent.connect.pivotal.gemfire.PivotalGemfireSinkConnector",
               "tasks.max": "1",
               "topics": "input_topic",
               "gemfire.locator.host":"pivotal-gemfire",
               "gemfire.locator.port":"10334",
               "gemfire.username":"",
               "gemfire.password":"",
               "gemfire.region":"exampleRegion",
               "confluent.topic.bootstrap.servers": "broker:9092",
               "confluent.topic.replication.factor": "1"
          }' \
     http://localhost:8083/connectors/pivotal-gemfire-sink/config | jq .

sleep 5

log "Check messages received in Pivotal Gemfire"
docker exec -i pivotal-gemfire gfsh  << EOF
connect --locator=localhost[10334]
query --query="select * from /exampleRegion"
EOF

