#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.repro.yml"

docker exec -t sftp-server bash -c "
mkdir -p /chroot/home/foo/upload/input
mkdir -p /chroot/home/foo/upload/error
mkdir -p /chroot/home/foo/upload/finished

chown -R foo /chroot/home/foo/upload
"

for i in $(seq 1 5)
do
     log "(Re-)creating connector sftp-source-csv"

     curl -X PUT \
          -H "Content-Type: application/json" \
          --data '{
          "topics": "test_sftp_sink",
                    "tasks.max": "1",
                    "connector.class": "io.confluent.connect.sftp.SftpCsvSourceConnector",
                    "cleanup.policy":"MOVE",
                    "behavior.on.error":"LOG",
                    "input.path": "/home/foo/upload/input",
                    "error.path": "/home/foo/upload/error",
                    "finished.path": "/home/foo/upload/finished",
                    "input.file.pattern": "csv-sftp-source(.*).csv",
                    "sftp.username":"foo",
                    "sftp.password":"pass",
                    "sftp.host":"sftp-server",
                    "sftp.port":"22",
                    "kafka.topic": "sftp-testing-topic",
               "csv.first.row.as.header": "false",
               "key.schema": "{\"name\" : \"com.example.users.UserKey\",\"type\" : \"STRUCT\",\"isOptional\" : false,\"fieldSchemas\" : {\"id\" : {\"type\" : \"INT64\",\"isOptional\" : false}}}",
               "value.schema": "{\"name\" : \"com.example.users.User\",\"type\" : \"STRUCT\",\"isOptional\" : false,\"fieldSchemas\" : {\"id\" : {\"type\" : \"INT64\",\"isOptional\" : false},\"first_name\" : {\"type\" : \"STRING\",\"isOptional\" : true},\"last_name\" : {\"type\" : \"STRING\",\"isOptional\" : true},\"email\" : {\"type\" : \"STRING\",\"isOptional\" : true},\"gender\" : {\"type\" : \"STRING\",\"isOptional\" : true},\"ip_address\" : {\"type\" : \"STRING\",\"isOptional\" : true},\"last_login\" : {\"type\" : \"STRING\",\"isOptional\" : true},\"account_balance\" : {\"name\" : \"org.apache.kafka.connect.data.Decimal\",\"type\" : \"BYTES\",\"version\" : 1,\"parameters\" : {\"scale\" : \"2\"},\"isOptional\" : true},\"country\" : {\"type\" : \"STRING\",\"isOptional\" : true},\"favorite_color\" : {\"type\" : \"STRING\",\"isOptional\" : true}}}"
               }' \
          http://localhost:8083/connectors/sftp-source-csv/config | jq .

     sleep 5

     log "Process a file csv-sftp-source$i.csv"
     echo $'1,Salmon,Baitman,sbaitman0@feedburner.com,Male,120.181.75.98,2015-03-01T06:01:15Z,17462.66,IT,#f09bc0\n2,Debby,Brea,dbrea1@icio.us,Female,153.239.187.49,2018-10-21T12:27:12Z,14693.49,CZ,#73893a' > csv-sftp-source$i.csv
     docker cp csv-sftp-source$i.csv sftp-server:/chroot/home/foo/upload/input/
     rm -f csv-sftp-source$i.csv

     sleep 5

     log "Verifying topic sftp-testing-topic"
     timeout 60 docker exec connect kafka-avro-console-consumer -bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic sftp-testing-topic --from-beginning --max-messages 2

     log "Deleting connector sftp-source-csv"
     curl -X DELETE localhost:8083/connectors/sftp-source-csv
done
