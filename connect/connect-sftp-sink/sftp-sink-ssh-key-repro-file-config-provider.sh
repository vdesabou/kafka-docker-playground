#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.repro-file-config-provider.yml"

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
               "format.class": "io.confluent.connect.sftp.sink.format.csv.CsvFormat",
               "storage.class": "io.confluent.connect.sftp.sink.storage.SftpSinkStorage",
               "sftp.host": "sftp-server",
               "sftp.port": "22",
               "sftp.username": "${file:/tmp/secrets.properties:SFTP_USER_NAME}",
               "sftp.password": "${file:/tmp/secrets.properties:SFTP_USER_PASSWORD}",
               "tls.private.key": "${file:/tmp/secrets.properties:SSH_PRIVATE_KEY}",
               "tls.public.key": "${file:/tmp/secrets.properties:SFTP_PUBLIC_KEY}",
               "tls.passphrase": "${file:/tmp/secrets.properties:SSH_PRIVATE_KEY_PASSPHRASE}",
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