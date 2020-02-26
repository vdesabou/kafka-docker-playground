#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.repro-windows.yml"

log "Creating CSV file"
echo $'id,first_name,last_name,email,gender,ip_address,last_login,account_balance,country,favorite_color\n1,Salmon,Baitman,sbaitman0@feedburner.com,Male,120.181.75.98,2015-03-01T06:01:15Z,17462.66,IT,#f09bc0\n2,Debby,Brea,dbrea1@icio.us,Female,153.239.187.49,2018-10-21T12:27:12Z,14693.49,CZ,#73893a' > csv-sftp-source1.csv

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
               "input.path": ".",
               "error.path": "/error",
               "finished.path": "/finished",
               "input.file.pattern": "csv-sftp-source(.*).csv",
               "sftp.username":"<user>",
               "sftp.password":"<password>",
               "sftp.host":"<ip>",
               "sftp.port":"2222",
               "kafka.topic": "sftp-testing-topic",
               "csv.first.row.as.header": "true",
               "schema.generation.enabled": "true"
          }' \
     http://localhost:8083/connectors/sftp-source-csv/config | jq .

log "Use your SFTP client to copy csv-sftp-source1.csv"

exit 0


# [2020-02-26 09:11:43,180] INFO Removing processing flag ./finished/csv-sftp-source1.csv.PROCESSING (io.confluent.connect.sftp.source.SftpInputFile)
# [2020-02-26 09:11:43,264] WARN Can not remove file: ./finished/csv-sftp-source1.csv.PROCESSING (io.confluent.connect.sftp.source.SftpInputFile)
# 4: File is already exclusively open.
#         at com.jcraft.jsch.ChannelSftp.throwStatusError(ChannelSftp.java:2873)
#         at com.jcraft.jsch.ChannelSftp.rm(ChannelSftp.java:1985)
#         at io.confluent.connect.sftp.connection.SftpStorage.removeFile(SftpStorage.java:100)
#         at io.confluent.connect.sftp.source.SftpInputFile.close(SftpInputFile.java:86)
#         at io.confluent.connect.sftp.source.AbstractSftpSourceTask.read(AbstractSftpSourceTask.java:162)
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



sleep 5

log "Verifying topic sftp-testing-topic"
timeout 60 docker exec connect kafka-avro-console-consumer -bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic sftp-testing-topic --from-beginning --max-messages 2