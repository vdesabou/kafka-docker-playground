#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.repro-95314-converted-csv-file-is-not-in-comma-separated-format.yml"

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
               "sftp.username": "foo",
               "sftp.password": "pass",
               "sftp.working.dir": "/upload",
               "confluent.license": "",
               "confluent.topic.bootstrap.servers": "broker:9092",
               "confluent.topic.replication.factor": "1",
               "value.converter": "org.apache.kafka.connect.json.JsonConverter",
               "value.converter.schemas.enable": "false"
          }' \
     http://localhost:8083/connectors/sftp-sink-csv/config | jq .

log "sending records"
docker exec -i broker kafka-console-producer --broker-list broker:9092 --topic test_sftp_sink << EOF
{"u_name": "scissors", "u_price": 2.75, "u_quantity": 3}
{"u_name": "tape", "u_price": 0.99, "u_quantity": 10}
{"u_name": "notebooks", "u_price": 1.99, "u_quantity": 5}
EOF

sleep 10

log "Listing content of ./upload/topics/test_sftp_sink/partition\=0/"
docker exec sftp-server bash -c "ls /home/foo/upload/topics/test_sftp_sink/partition\=0/"

docker cp sftp-server:/home/foo/upload/topics/test_sftp_sink/partition\=0/test_sftp_sink+0+0000000000.csv /tmp/

cat /tmp/test_sftp_sink+0+0000000000.csv

# {u_name=scissors, u_price=2.75, u_quantity=3}
# {u_name=tape, u_price=0.99, u_quantity=10}
# {u_name=notebooks, u_price=1.99, u_quantity=5}