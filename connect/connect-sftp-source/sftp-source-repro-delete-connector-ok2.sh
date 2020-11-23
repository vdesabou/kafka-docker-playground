#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.repro.yml"

docker exec sftp-server bash -c "
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
                    "cleanup.policy":"NONE",
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
                    "csv.first.row.as.header": "true",
                    "schema.generation.enabled": "true"
               }' \
          http://localhost:8083/connectors/sftp-source-csv/config | jq .

     sleep 5

     log "Process a file csv-sftp-source$i.csv"
     echo $'id,first_name,last_name,email,gender,ip_address,last_login,account_balance,country,favorite_color\n1,Salmon,Baitman,sbaitman0@feedburner.com,Male,120.181.75.98,2015-03-01T06:01:15Z,17462.66,IT,#f09bc0\n2,Debby,Brea,dbrea1@icio.us,Female,153.239.187.49,2018-10-21T12:27:12Z,14693.49,CZ,#73893a' > csv-sftp-source$i.csv
     docker cp csv-sftp-source$i.csv sftp-server:/chroot/home/foo/upload/input/
     rm -f csv-sftp-source$i.csv

     sleep 5

     log "Verifying topic sftp-testing-topic"
     timeout 60 docker exec connect kafka-avro-console-consumer -bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic sftp-testing-topic --from-beginning --max-messages 2

     log "Deleting connector sftp-source-csv"
     curl -X DELETE localhost:8083/connectors/sftp-source-csv
done
