#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

docker-compose down -v --remove-orphans
docker-compose up -d
${DIR}/../../scripts/wait-for-connect-and-controlcenter.sh "connect1"
${DIR}/../../scripts/wait-for-connect-and-controlcenter.sh "connect2"


log "Creating SFTP Sink connector with 4 tasks"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
        "topics": "test_sftp_sink",
               "tasks.max": "4",
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

sleep 5

log "Getting tasks placement"
curl --request GET \
  --url http://localhost:8083/connectors/sftp-sink/status \
  --header 'accept: application/json' | jq

docker container stop broker2
docker container stop connect2
docker container start connect2

${DIR}/../../scripts/wait-for-connect-and-controlcenter.sh "connect2"

log "Getting tasks placement"
curl --request GET \
  --url http://localhost:8083/connectors/sftp-sink/status \
  --header 'accept: application/json' | jq

# FIXTHIS
# {
#   "name": "sftp-sink",
#   "connector": {
#     "state": "UNASSIGNED",
#     "worker_id": "connect2:8083"
#   },
#   "tasks": [
#     {
#       "id": 0,
#       "state": "UNASSIGNED",
#       "worker_id": "connect2:8083"
#     },
#     {
#       "id": 1,
#       "state": "RUNNING",
#       "worker_id": "connect1:8083"
#     },
#     {
#       "id": 2,
#       "state": "UNASSIGNED",
#       "worker_id": "connect2:8083"
#     },
#     {
#       "id": 3,
#       "state": "RUNNING",
#       "worker_id": "connect1:8083"
#     }
#   ],
#   "type": "sink"
# }