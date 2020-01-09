#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"


echo -e "\033[0;33mCreating SFTP Sink connector\033[0m"
docker exec connect \
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


echo -e "\033[0;33mSending messages to topic test_sftp_sink\033[0m"
seq -f "{\"f1\": \"value%g\"}" 10 | docker exec -i schema-registry kafka-avro-console-producer --broker-list broker:9092 --topic test_sftp_sink --property value.schema='{"type":"record","name":"myrecord","fields":[{"name":"f1","type":"string"}]}'

sleep 10

echo -e "\033[0;33mListing content of ./upload/topics/test_sftp_sink/partition\=0/\033[0m"
ls ./upload/topics/test_sftp_sink/partition\=0/


docker run -v /tmp:/tmp actions/avro-tools tojson ./upload/topics/test_sftp_sink/partition\=0/test_sftp_sink+0+0000000000.avro