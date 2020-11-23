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
     log "(Re-)creating connector sftp-source-json"

     curl -X PUT \
          -H "Content-Type: application/json" \
          --data '{
               "topics": "test_sftp_sink",
               "tasks.max": "1",
               "connector.class": "io.confluent.connect.sftp.SftpSchemaLessJsonSourceConnector",
               "behavior.on.error":"IGNORE",
               "input.path": "/home/foo/upload/input",
               "error.path": "/home/foo/upload/error",
               "finished.path": "/home/foo/upload/finished",
               "input.file.pattern": "json-sftp-source(.*).json",
               "sftp.username":"foo",
               "sftp.password":"pass",
               "sftp.host":"sftp-server",
               "sftp.port":"22",
               "kafka.topic": "sftp-testing-topic",
               "value.converter": "org.apache.kafka.connect.storage.StringConverter"
               }' \
          http://localhost:8083/connectors/sftp-source-json/config | jq .

     sleep 5

     log "Process a file json-sftp-source$i.json"
     echo $'{"id":1,"first_name":"Roscoe","last_name":"Brentnall","email":"rbrentnall0@mediafire.com","gender":"Male","ip_address":"202.84.142.254","last_login":"2018-02-12T06:26:23Z","account_balance":1450.68,"country":"CZ","favorite_color":"#4eaefa"}\n{"id":2,"first_name":"Gregoire","last_name":"Fentem","email":"gfentem1@nsw.gov.au","gender":"Male","ip_address":"221.159.106.63","last_login":"2015-03-27T00:29:56Z","account_balance":1392.37,"country":"ID","favorite_color":"#e8f686"}' > json-sftp-source$i.json
     docker cp json-sftp-source$i.json sftp-server:/chroot/home/foo/upload/input/
     rm -f json-sftp-source$i.json

     sleep 5

     log "Verifying topic sftp-testing-topic"
     timeout 60 docker exec broker kafka-console-consumer -bootstrap-server broker:9092 --topic sftp-testing-topic --from-beginning --max-messages 2

     log "Deleting connector sftp-source-json"
     curl -X DELETE localhost:8083/connectors/sftp-source-json
done
