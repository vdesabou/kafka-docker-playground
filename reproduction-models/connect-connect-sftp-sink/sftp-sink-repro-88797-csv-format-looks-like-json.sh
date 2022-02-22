#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

for component in producer-88797
do
    set +e
    log "🏗 Building jar for ${component}"
    docker run -i --rm -e KAFKA_CLIENT_TAG=$KAFKA_CLIENT_TAG -e TAG=$TAG_BASE -v "${DIR}/${component}":/usr/src/mymaven -v "$HOME/.m2":/root/.m2 -v "${DIR}/${component}/target:/usr/src/mymaven/target" -w /usr/src/mymaven maven:3.6.1-jdk-11 mvn -Dkafka.tag=$TAG -Dkafka.client.tag=$KAFKA_CLIENT_TAG package > /tmp/result.log 2>&1
    if [ $? != 0 ]
    then
        logerror "ERROR: failed to build java component $component"
        tail -500 /tmp/result.log
        exit 1
    fi
    set -e
done

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.repro-88797-csv-format-looks-like-json.yml"

log "Creating SFTP Sink CSV connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "topics": "customer-json-schema",
               "tasks.max": "1",
               "connector.class": "io.confluent.connect.sftp.SftpSinkConnector",
               "partitioner.class": "io.confluent.connect.storage.partitioner.DefaultPartitioner",
               "schema.generator.class": "io.confluent.connect.storage.hive.schema.DefaultSchemaGenerator",
               "flush.size": "3",
               "schema.compatibility": "NONE",
               "value.converter": "io.confluent.connect.json.JsonSchemaConverter",
               "value.converter.schema.registry.url": "http://schema-registry:8081",
               "format.class": "io.confluent.connect.sftp.sink.format.csv.CsvFormat",
               "storage.class": "io.confluent.connect.sftp.sink.storage.SftpSinkStorage",
               "sftp.host": "sftp-server",
               "sftp.port": "22",
               "sftp.username": "foo",
               "sftp.password": "pass",
               "sftp.working.dir": "/upload",
               "confluent.license": "",
               "confluent.topic.bootstrap.servers": "broker:9092",
               "confluent.topic.replication.factor": "1"
          }' \
     http://localhost:8083/connectors/sftp-sink/config | jq .


log "Sending messages to topic customer-json-schema"
log "Produce json-schema data using Java producer"
docker exec producer-88797 bash -c "java -jar producer-88797-1.0.0-jar-with-dependencies.jar"

sleep 10

log "Listing content of ./upload/topics/customer-json-schema/partition\=0/"
docker exec sftp-server bash -c "ls /home/foo/upload/topics/customer-json-schema/partition\=0/"

docker cp sftp-server:/home/foo/upload/topics/customer-json-schema/partition\=0/customer-json-schema+0+0000000000.csv /tmp/

cat /tmp/customer-json-schema+0+0000000000.csv

# Struct{surname=tThy,name=eOM,email=hV}
# Struct{surname=UZNR,name=NLW,email=cBaQ}
# Struct{surname=y,name=KxI,email=edUs}