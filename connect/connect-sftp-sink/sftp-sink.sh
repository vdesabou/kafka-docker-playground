#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"


echo "Creating SFTP Sink connector"
docker exec connect \
     curl -X POST \
     -H "Content-Type: application/json" \
     --data '{
        "name": "sftp-sink",
        "config": {
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
          }}' \
     http://localhost:8083/connectors | jq .


echo "Sending messages to topic test_sftp_sink"
seq -f "{\"f1\": \"value%g\"}" 10 | docker exec -i schema-registry kafka-avro-console-producer --broker-list broker:9092 --topic test_sftp_sink --property value.schema='{"type":"record","name":"myrecord","fields":[{"name":"f1","type":"string"}]}'

sleep 10

echo "Listing content of ./upload/topics/test_sftp_sink/partition\=0/"
ls ./upload/topics/test_sftp_sink/partition\=0/

# brew install avro-tools
avro-tools tojson ./upload/topics/test_sftp_sink/partition\=0/test_sftp_sink+0+0000000000.avro