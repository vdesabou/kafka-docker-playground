#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"

docker exec sftp-server bash -c "
mkdir -p /chroot/home/foo/upload/input
mkdir -p /chroot/home/foo/upload/error
mkdir -p /chroot/home/foo/upload/finished

chown -R foo /chroot/home/foo/upload
"

echo $'id,first_name,last_name,email,gender,ip_address,last_login,account_balance,country,favorite_color\n1,Salmon,Baitman,sbaitman0@feedburner.com,Male,120.181.75.98,2015-03-01T06:01:15Z,17462.66,IT,#f09bc0\n2,Debby,Brea,dbrea1@icio.us,Female,153.239.187.49,2018-10-21T12:27:12Z,14693.49,CZ,#73893a' > csv-sftp-source.csv
docker cp csv-sftp-source.csv sftp-server:/chroot/home/foo/upload/input/
rm -f csv-sftp-source.csv

log "Creating CSV SFTP Source connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
        "topics": "test_sftp_sink",
               "tasks.max": "1",
               "connector.class": "io.confluent.connect.sftp.SftpCsvSourceConnector",
               "cleanup.policy":"NONE",
               "behavior.on.error":"IGNORE",
               "input.path": "/home/foo/upload/input1",
               "error.path": "/home/foo/upload/error",
               "finished.path": "/home/foo/upload/finished",
               "input.file.pattern": "csv-sftp-source.csv",
               "sftp.username":"foo",
               "sftp.password":"pass",
               "sftp.host":"sftp-server",
               "sftp.port":"22",
               "kafka.topic": "sftp-testing-topic",
               "csv.first.row.as.header": "true",
               "schema.generation.enabled": "true"
          }' \
     http://localhost:8083/connectors/sftp-source-csv/config | jq .

log "get the status"
curl --request GET \
  --url http://localhost:8083/connectors/sftp-source-csv/status \
  --header 'accept: application/json' | jq

# {
#   "name": "sftp-source-csv",
#   "connector": {
#     "state": "FAILED",
#     "worker_id": "connect:8083",
#     "trace": "org.apache.kafka.connect.errors.ConnectException: Sftp directory for 'input.path' '/home/foo/upload/input1' does not exist \n\tat io.confluent.connect.sftp.source.SftpDirectoryPermission.directoryExist(SftpDirectoryPermission.java:66)\n\tat io.confluent.connect.sftp.source.SftpDirectoryPermission.ensureReadable(SftpDirectoryPermission.java:44)\n\tat io.confluent.connect.sftp.SftpCsvSourceConnector.start(SftpCsvSourceConnector.java:52)\n\tat org.apache.kafka.connect.runtime.WorkerConnector.doStart(WorkerConnector.java:186)\n\tat org.apache.kafka.connect.runtime.WorkerConnector.start(WorkerConnector.java:211)\n\tat org.apache.kafka.connect.runtime.WorkerConnector.doTransitionTo(WorkerConnector.java:350)\n\tat org.apache.kafka.connect.runtime.WorkerConnector.doTransitionTo(WorkerConnector.java:333)\n\tat org.apache.kafka.connect.runtime.WorkerConnector.doRun(WorkerConnector.java:141)\n\tat org.apache.kafka.connect.runtime.WorkerConnector.run(WorkerConnector.java:118)\n\tat java.base/java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:515)\n\tat java.base/java.util.concurrent.FutureTask.run(FutureTask.java:264)\n\tat java.base/java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1128)\n\tat java.base/java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:628)\n\tat java.base/java.lang.Thread.run(Thread.java:834)\nCaused by: 2: No such file\n\tat com.jcraft.jsch.ChannelSftp.throwStatusError(ChannelSftp.java:2873)\n\tat com.jcraft.jsch.ChannelSftp._stat(ChannelSftp.java:2225)\n\tat com.jcraft.jsch.ChannelSftp._stat(ChannelSftp.java:2242)\n\tat com.jcraft.jsch.ChannelSftp.stat(ChannelSftp.java:2199)\n\tat io.confluent.connect.sftp.source.SftpDirectoryPermission.directoryExist(SftpDirectoryPermission.java:62)\n\t... 13 more\n"
#   },
#   "tasks": [],
#   "type": "source"
# }


log "add the missing dir"
docker exec sftp-server bash -c "
mkdir -p /chroot/home/foo/upload/input1
chown -R foo /chroot/home/foo/upload
"


log "Try to pause (equivalent of control center pause button)"
curl --request PUT \
  --url http://localhost:8083/connectors/sftp-source-csv/pause

# [2021-04-15 14:36:38,175] INFO [Worker clientId=connect-1, groupId=connect-cluster] Connector sftp-source-csv target state change (org.apache.kafka.connect.runtime.distributed.DistributedHerder)
# [2021-04-15 14:36:38,175] INFO Setting connector sftp-source-csv state to PAUSED (org.apache.kafka.connect.runtime.Worker)
# [2021-04-15 14:36:38,175] ERROR [Worker clientId=connect-1, groupId=connect-cluster] Failed to transition connector to target state (org.apache.kafka.connect.runtime.distributed.DistributedHerder)
# org.apache.kafka.connect.errors.ConnectException: WorkerConnector{id=sftp-source-csv} Cannot transition connector to PAUSED since it has failed
#         at org.apache.kafka.connect.runtime.WorkerConnector.doTransitionTo(WorkerConnector.java:326)
#         at org.apache.kafka.connect.runtime.WorkerConnector.doRun(WorkerConnector.java:141)
#         at org.apache.kafka.connect.runtime.WorkerConnector.run(WorkerConnector.java:118)
#         at java.base/java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:515)
#         at java.base/java.util.concurrent.FutureTask.run(FutureTask.java:264)
#         at java.base/java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1128)
#         at java.base/java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:628)
#         at java.base/java.lang.Thread.run(Thread.java:834)

log "Try to resume (equivalent of control center pause play)"
curl --request PUT \
  --url http://localhost:8083/connectors/sftp-source-csv/resume

# [2021-04-15 14:35:53,930] INFO [Worker clientId=connect-1, groupId=connect-cluster] Connector sftp-source-csv target state change (org.apache.kafka.connect.runtime.distributed.DistributedHerder)
# [2021-04-15 14:35:53,931] INFO Setting connector sftp-source-csv state to STARTED (org.apache.kafka.connect.runtime.Worker)
# [2021-04-15 14:35:53,931] ERROR [Worker clientId=connect-1, groupId=connect-cluster] Failed to transition connector to target state (org.apache.kafka.connect.runtime.distributed.DistributedHerder)
# org.apache.kafka.connect.errors.ConnectException: WorkerConnector{id=sftp-source-csv} Cannot transition connector to STARTED since it has failed
#         at org.apache.kafka.connect.runtime.WorkerConnector.doTransitionTo(WorkerConnector.java:326)
#         at org.apache.kafka.connect.runtime.WorkerConnector.doRun(WorkerConnector.java:141)
#         at org.apache.kafka.connect.runtime.WorkerConnector.run(WorkerConnector.java:118)
#         at java.base/java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:515)
#         at java.base/java.util.concurrent.FutureTask.run(FutureTask.java:264)
#         at java.base/java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1128)
#         at java.base/java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:628)
#         at java.base/java.lang.Thread.run(Thread.java:834)

log "Try to restart (no equivalent for control center, it works fine)"
curl --request POST \
  --url http://localhost:8083/connectors/sftp-source-csv/restart


# [2021-04-15 14:38:31,513] INFO Stopping connector sftp-source-csv (org.apache.kafka.connect.runtime.Worker)
# [2021-04-15 14:38:31,513] INFO Scheduled shutdown for WorkerConnector{id=sftp-source-csv} (org.apache.kafka.connect.runtime.WorkerConnector)
# [2021-04-15 14:38:31,514] INFO Completed shutdown for WorkerConnector{id=sftp-source-csv} (org.apache.kafka.connect.runtime.WorkerConnector)
# [2021-04-15 14:38:31,515] INFO [Worker clientId=connect-1, groupId=connect-cluster] Starting connector sftp-source-csv (org.apache.kafka.connect.runtime.distributed.DistributedHerder)
# [2021-04-15 14:38:31,515] INFO Creating connector sftp-source-csv of type io.confluent.connect.sftp.SftpCsvSourceConnector (org.apache.kafka.connect.runtime.Worker)
# [2021-04-15 14:38:31,516] INFO SourceConnectorConfig values:
#         config.action.reload = restart
#         connector.class = io.confluent.connect.sftp.SftpCsvSourceConnector
#         errors.log.enable = false
#         errors.log.include.messages = false
#         errors.retry.delay.max.ms = 60000
#         errors.retry.timeout = 0
#         errors.tolerance = none
#         header.converter = null
#         key.converter = null
#         name = sftp-source-csv
#         predicates = []
#         tasks.max = 1
#         topic.creation.groups = []
#         transforms = []
#         value.converter = null
#  (org.apache.kafka.connect.runtime.SourceConnectorConfig)
# [2021-04-15 14:38:31,517] INFO EnrichedConnectorConfig values:
#         config.action.reload = restart
#         connector.class = io.confluent.connect.sftp.SftpCsvSourceConnector
#         errors.log.enable = false
#         errors.log.include.messages = false
#         errors.retry.delay.max.ms = 60000
#         errors.retry.timeout = 0
#         errors.tolerance = none
#         header.converter = null
#         key.converter = null
#         name = sftp-source-csv
#         predicates = []
#         tasks.max = 1
#         topic.creation.groups = []
#         transforms = []
#         value.converter = null
#  (org.apache.kafka.connect.runtime.ConnectorConfig$EnrichedConnectorConfig)
# [2021-04-15 14:38:31,518] INFO Instantiated connector sftp-source-csv with version 0.0.0.0 of type class io.confluent.connect.sftp.SftpCsvSourceConnector (org.apache.kafka.connect.runtime.Worker)
# [2021-04-15 14:38:31,519] INFO Finished creating connector sftp-source-csv (org.apache.kafka.connect.runtime.Worker)


log "get the status"
curl --request GET \
  --url http://localhost:8083/connectors/sftp-source-csv/status \
  --header 'accept: application/json' | jq


# {
#   "name": "sftp-source-csv",
#   "connector": {
#     "state": "RUNNING",
#     "worker_id": "connect:8083"
#   },
#   "tasks": [
#     {
#       "id": 0,
#       "state": "RUNNING",
#       "worker_id": "connect:8083"
#     }
#   ],
#   "type": "source"
# }
