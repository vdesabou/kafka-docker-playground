#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

for component in json-producer
do
     set +e
     log "🏗 Building jar for ${component}"
     docker run -i --rm -e KAFKA_CLIENT_TAG=$KAFKA_CLIENT_TAG -e TAG=$TAG_BASE -v "${DIR}/${component}":/usr/src/mymaven -v "$HOME/.m2":/root/.m2 -v "$PWD/../../scripts/settings.xml:/tmp/settings.xml" -v "${DIR}/${component}/target:/usr/src/mymaven/target" -w /usr/src/mymaven maven:3.6.1-jdk-11 mvn -s /tmp/settings.xml -Dkafka.tag=$TAG -Dkafka.client.tag=$KAFKA_CLIENT_TAG package > /tmp/result.log 2>&1
     if [ $? != 0 ]
     then
          logerror "ERROR: failed to build java component $component"
          tail -500 /tmp/result.log
          exit 1
     fi
     set -e
done

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"

log "Creating Couchbase cluster"
docker exec couchbase bash -c "/opt/couchbase/bin/couchbase-cli cluster-init --cluster-username Administrator --cluster-password password --services=data,index,query"
log "Creating Couchbase bucket travel-data"
docker exec couchbase bash -c "/opt/couchbase/bin/couchbase-cli bucket-create --cluster localhost:8091 --username Administrator --password password --bucket travel-data --bucket-type couchbase --bucket-ramsize 100"

log "Sending messages to topic couchbase-sink-example"
docker exec json-producer bash -c "java -jar json-producer-1.0.0-SNAPSHOT-jar-with-dependencies.jar"

log "Creating Couchbase sink connector"
playground connector create-or-update --connector couchbase-sink << EOF
{
               "connector.class": "com.couchbase.connect.kafka.CouchbaseSinkConnector",
               "tasks.max": "2",
               "topics": "couchbase-sink-example",
               "couchbase.seed.nodes": "couchbase",
               "couchbase.bootstrap.timeout": "2000ms",
               "couchbase.bucket": "travel-data",
               "couchbase.username": "Administrator",
               "couchbase.password": "password",
               "couchbase.persist.to": "NONE",
               "couchbase.replicate.to": "NONE",
               "couchbase.document.id": "/airport",
               "key.converter": "org.apache.kafka.connect.storage.StringConverter",
               "value.converter": "org.apache.kafka.connect.json.JsonConverter",
               "value.converter.schemas.enable": "false"
          }
EOF

sleep 10

log "Verify data is in Couchbase"
docker exec couchbase bash -c "cbc cat CDG -U couchbase://localhost/travel-data -u Administrator -P password" > /tmp/result.log  2>&1
cat /tmp/result.log
grep "airport" /tmp/result.log
