#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"

docker exec -t sftp-server bash -c "
mkdir -p /home/foo/upload/error
mkdir -p /home/foo/upload/finished

chown -R foo /home/foo/upload
"


log "Creating CSV SFTP Source connector"
docker exec connect \
     curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
        "topics": "test_sftp_sink",
               "tasks.max": "1",
               "connector.class": "io.confluent.connect.sftp.SftpCsvSourceConnector",
               "cleanup.policy":"MOVE",
               "behavior.on.error":"LOG",
               "input.path": "/upload",
               "error.path": "/upload/error",
               "finished.path": "/upload/finished",
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

sleep 5

log "Changing owner to root"
docker exec -t sftp-server bash -c "
chown -R root /home/foo/upload
"

log "injecting CSV file"
echo $'id,first_name,last_name,email,gender,ip_address,last_login,account_balance,country,favorite_color\n1,Salmon,Baitman,sbaitman0@feedburner.com,Male,120.181.75.98,2015-03-01T06:01:15Z,17462.66,IT,#f09bc0\n2,Debby,Brea,dbrea1@icio.us,Female,153.239.187.49,2018-10-21T12:27:12Z,14693.49,CZ,#73893a' > csv-sftp-source.csv
docker cp csv-sftp-source.csv sftp-server:/home/foo/upload/
rm -f csv-sftp-source.csv

sleep 5

docker container logs --tail=200 connect

# [2020-02-19 17:39:54,405] ERROR WorkerSourceTask{id=sftp-source-csv-0} Task threw an uncaught and unrecoverable exception (org.apache.kafka.connect.runtime.WorkerTask)
# java.lang.NullPointerException
#         at io.confluent.connect.sftp.source.AbstractSftpSourceTask.read(AbstractSftpSourceTask.java:208)
#         at io.confluent.connect.sftp.source.AbstractSftpSourceTask.poll(AbstractSftpSourceTask.java:124)
#         at org.apache.kafka.connect.runtime.WorkerSourceTask.poll(WorkerSourceTask.java:265)
#         at org.apache.kafka.connect.runtime.WorkerSourceTask.execute(WorkerSourceTask.java:232)
#         at org.apache.kafka.connect.runtime.WorkerTask.doRun(WorkerTask.java:177)
#         at org.apache.kafka.connect.runtime.WorkerTask.run(WorkerTask.java:227)
#         at java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:511)
#         at java.util.concurrent.FutureTask.run(FutureTask.java:266)
#         at java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1149)
#         at java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:624)
#         at java.lang.Thread.run(Thread.java:748)


# With fix

# [2020-02-20 10:59:16,778] WARN Exception encountered processing line -1 of io.confluent.connect.sftp.source.SftpInputFile@540adee. (io.confluent.connect.sftp.source.AbstractSftpSourceTask)
# [2020-02-20 10:59:18,289] ERROR Error occurred, logging exception for behavior.on.error=LOG :  (io.confluent.connect.sftp.source.AbstractSftpSourceTask)
# org.apache.kafka.connect.errors.ConnectException: Can not get input stream from sftp path: /upload/csv-sftp-source.csv
#         at io.confluent.connect.sftp.source.SftpInputFile.openStream(SftpInputFile.java:61)
#         at io.confluent.connect.sftp.source.AbstractSftpSourceTask.read(AbstractSftpSourceTask.java:183)
#         at io.confluent.connect.sftp.source.AbstractSftpSourceTask.poll(AbstractSftpSourceTask.java:124)
#         at org.apache.kafka.connect.runtime.WorkerSourceTask.poll(WorkerSourceTask.java:265)
#         at org.apache.kafka.connect.runtime.WorkerSourceTask.execute(WorkerSourceTask.java:232)
#         at org.apache.kafka.connect.runtime.WorkerTask.doRun(WorkerTask.java:177)
#         at org.apache.kafka.connect.runtime.WorkerTask.run(WorkerTask.java:227)
#         at java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:511)
#         at java.util.concurrent.FutureTask.run(FutureTask.java:266)
#         at java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1149)
#         at java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:624)
#         at java.lang.Thread.run(Thread.java:748)
# Caused by: 3: Permission denied
#         at com.jcraft.jsch.ChannelSftp.throwStatusError(ChannelSftp.java:2873)
#         at com.jcraft.jsch.ChannelSftp.put(ChannelSftp.java:768)
#         at com.jcraft.jsch.ChannelSftp.put(ChannelSftp.java:709)
#         at com.jcraft.jsch.ChannelSftp.put(ChannelSftp.java:703)
#         at io.confluent.connect.sftp.source.SftpInputFile.openStream(SftpInputFile.java:59)
#         ... 11 more
# [2020-02-20 11:00:15,196] INFO WorkerSourceTask{id=sftp-source-csv-0} Committing offsets (org.apache.kafka.connect.runtime.WorkerSourceTask)
# [2020-02-20 11:00:15,197] INFO WorkerSourceTask{id=sftp-source-csv-0} flushing 0 outstanding messages for offset commit (org.apache.kafka.connect.runtime.WorkerSourceTask)
# [2020-02-20 11:01:15,131] INFO WorkerSourceTask{id=sftp-source-csv-0} Committing offsets (org.apache.kafka.connect.runtime.WorkerSourceTask)

exit 0

log "Changing owner to foo"
docker exec -t sftp-server bash -c "
chown -R foo /home/foo/upload
"

log "Restarting the task"
docker exec connect curl -X POST http://localhost:8083/connectors/sftp-source-csv/tasks/0/restart

sleep 5

log "Verifying topic sftp-testing-topic"
timeout 60 docker exec connect kafka-avro-console-consumer -bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic sftp-testing-topic --from-beginning --max-messages 2