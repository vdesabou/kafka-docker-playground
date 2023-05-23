#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

mkdir -p ${DIR}/data/input
mkdir -p ${DIR}/data/error
mkdir -p ${DIR}/data/finished

# workaround for issue on linux, see https://github.com/vdesabou/kafka-docker-playground/issues/851#issuecomment-821151962
chmod -R a+rw ${DIR}/data

if [[ "$TAG" == *ubi8 ]] || version_gt $TAG_BASE "5.9.0"
then
     export CONNECT_CONTAINER_HOME_DIR="/home/appuser"
else
     export CONNECT_CONTAINER_HOME_DIR="/root"
fi

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"

if [ ! -f "${DIR}/data/input/csv-spooldir-source.csv" ]
then
     log "Generating data"
     curl -k "https://api.mockaroo.com/api/58605010?count=1000&key=25fd9c80" > "${DIR}/data/input/csv-spooldir-source.csv"
fi

INPUT_PATH="${CONNECT_CONTAINER_HOME_DIR}/data/input/"
ERROR_PATH="${CONNECT_CONTAINER_HOME_DIR}/data/error/"
FINISHED_PATH="${CONNECT_CONTAINER_HOME_DIR}/data/finished/"

log "Creating CSV Spool Dir Source connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
          "tasks.max": "1",
          "connector.class": "com.github.jcustenborder.kafka.connect.spooldir.SpoolDirCsvSourceConnector",
          "input.file.pattern": "csv-spooldir-source.csv",
          "input.path": "'"$INPUT_PATH"'",
          "error.path": "'"$ERROR_PATH"'",
          "finished.path": "'"$FINISHED_PATH"'",
          "halt.on.error": "false",
          "topic": "spooldir-csv-topic",
          "csv.first.row.as.header": "true",
          "key.schema": "{\n  \"name\" : \"com.example.users.UserKey\",\n  \"type\" : \"STRUCT\",\n  \"isOptional\" : false,\n  \"fieldSchemas\" : {\n    \"id\" : {\n      \"type\" : \"INT64\",\n      \"isOptional\" : false\n    }\n  }\n}",
          "value.schema": "{\n  \"name\" : \"com.example.users.User\",\n  \"type\" : \"STRUCT\",\n  \"isOptional\" : false,\n  \"fieldSchemas\" : {\n    \"id\" : {\n      \"type\" : \"INT64\",\n      \"isOptional\" : false\n    },\n    \"first_name\" : {\n      \"type\" : \"STRING\",\n      \"isOptional\" : true\n    },\n    \"last_name\" : {\n      \"type\" : \"STRING\",\n      \"isOptional\" : true\n    },\n    \"email\" : {\n      \"type\" : \"STRING\",\n      \"isOptional\" : true\n    },\n    \"gender\" : {\n      \"type\" : \"STRING\",\n      \"isOptional\" : true\n    },\n    \"ip_address\" : {\n      \"type\" : \"STRING\",\n      \"isOptional\" : true\n    },\n    \"last_login\" : {\n      \"type\" : \"STRING\",\n      \"isOptional\" : true\n    },\n    \"account_balance\" : {\n      \"name\" : \"org.apache.kafka.connect.data.Decimal\",\n      \"type\" : \"BYTES\",\n      \"version\" : 1,\n      \"parameters\" : {\n        \"scale\" : \"2\"\n      },\n      \"isOptional\" : true\n    },\n    \"country\" : {\n      \"type\" : \"STRING\",\n      \"isOptional\" : true\n    },\n    \"favorite_color\" : {\n      \"type\" : \"STRING\",\n      \"isOptional\" : true\n    }\n  }\n}"
     }}' \
     http://localhost:8083/connectors/spool-dir/config | jq .

sleep 5

log "Verify we have received the data in spooldir-csv-topic topic"
playground topic consume --topic spooldir-csv-topic --min-expected-messages 10

log "Creating SFTP Sink connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "topics": "test_sftp_sink",
               "tasks.max": "1",
               "connector.class": "io.confluent.connect.sftp.SftpSinkConnector",
               "partitioner.class": "io.confluent.connect.storage.partitioner.DefaultPartitioner",
               "schema.generator.class": "io.confluent.connect.storage.hive.schema.DefaultSchemaGenerator",
               "flush.size": "3",
               "schema.compatibility": "NONE",
               "format.class": "io.confluent.connect.sftp.sink.format.avro.AvroFormat",
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


log "Sending messages to topic test_sftp_sink"
seq -f "{\"f1\": \"value%g\"}" 10 | docker exec -i connect kafka-avro-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic test_sftp_sink --property value.schema='{"type":"record","name":"myrecord","fields":[{"name":"f1","type":"string"}]}'

sleep 10

log "Listing content of ./upload/topics/test_sftp_sink/partition\=0/"
docker exec sftp-server bash -c "ls /home/foo/upload/topics/test_sftp_sink/partition\=0/"

docker cp sftp-server:/home/foo/upload/topics/test_sftp_sink/partition\=0/test_sftp_sink+0+0000000000.avro /tmp/

docker run --rm -v /tmp:/tmp vdesabou/avro-tools tojson /tmp/test_sftp_sink+0+0000000000.avro


log "Remove /usr/share/confluent-hub-components/jcustenborder-kafka-connect-spooldir"
docker exec connect rm -rf /usr/share/confluent-hub-components/jcustenborder-kafka-connect-spooldir

log "restart connect container"
docker container restart connect


log "Now check connect cluster status in Control Center http://127.0.0.1:9021"
