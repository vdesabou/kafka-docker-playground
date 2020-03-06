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

log "Installing netstat"
set +e
docker exec connect apt-get update
docker exec connect apt-get install net-tools
set -e


log "netstat -an | grep 22"
set +e
docker exec connect netstat -an | grep 22
set -e

log "Creating connector sftp-source-csv"

docker exec connect \
     curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
     "topics": "test_sftp_sink",
               "tasks.max": "1",
               "connector.class": "io.confluent.connect.sftp.SftpCsvSourceConnector",
               "cleanup.policy":"MOVE",
               "behavior.on.error":"FAIL",
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
               "schema.generation.enabled": "false",
               "key.schema": "{\"name\" : \"com.example.users.UserKey\",\"type\" : \"STRUCT\",\"isOptional\" : false,\"fieldSchemas\" : {\"id\" : {\"type\" : \"INT64\",\"isOptional\" : false}}}",
               "value.schema": "{\"name\" : \"com.example.users.User\",\"type\" : \"STRUCT\",\"isOptional\" : false,\"fieldSchemas\" : {\"id\" : {\"type\" : \"INT64\",\"isOptional\" : false},\"first_name\" : {\"type\" : \"STRING\",\"isOptional\" : true},\"last_name\" : {\"type\" : \"STRING\",\"isOptional\" : true},\"email\" : {\"type\" : \"STRING\",\"isOptional\" : true},\"gender\" : {\"type\" : \"STRING\",\"isOptional\" : true},\"ip_address\" : {\"type\" : \"STRING\",\"isOptional\" : true},\"last_login\" : {\"type\" : \"STRING\",\"isOptional\" : true},\"account_balance\" : {\"name\" : \"org.apache.kafka.connect.data.Decimal\",\"type\" : \"BYTES\",\"version\" : 1,\"parameters\" : {\"scale\" : \"2\"},\"isOptional\" : true},\"country\" : {\"type\" : \"STRING\",\"isOptional\" : true},\"favorite_color\" : {\"type\" : \"STRING\",\"isOptional\" : true}}}"
          }' \
     http://localhost:8083/connectors/sftp-source-csv/config | jq .

sleep 5

log "Process a file csv-sftp-source1.csv that does not follow schema"
echo $'1,Salmon,Baitman,sbaitman0@feedburner.com,Male,120.181.75.98,2015-03-01T06:01:15Z,17462.66,IT,#f09bc0\nNOTANDINTEGER,Debby,Brea,dbrea1@icio.us,Female,153.239.187.49,2018-10-21T12:27:12Z,14693.49,CZ,#73893a' > csv-sftp-source1.csv
docker cp csv-sftp-source1.csv sftp-server:/chroot/home/foo/upload/input/
rm -f csv-sftp-source1.csv

sleep 5

log "Process a file csv-sftp-source2.csv that is correct"
echo $'1,Salmon,Baitman,sbaitman0@feedburner.com,Male,120.181.75.98,2015-03-01T06:01:15Z,17462.66,IT,#f09bc0\2,Debby,Brea,dbrea1@icio.us,Female,153.239.187.49,2018-10-21T12:27:12Z,14693.49,CZ,#73893a' > csv-sftp-source2.csv
docker cp csv-sftp-source2.csv sftp-server:/chroot/home/foo/upload/input/
rm -f csv-sftp-source2.csv

sleep 5

log "Deleting connector sftp-source-csv"
curl -X DELETE localhost:8083/connectors/sftp-source-csv

sleep 5

log "netstat -an | grep 22"
set +e
docker exec connect netstat -an | grep 22
set -e


# [2020-03-05 11:18:55,737] WARN Exception encountered processing line 2 of io.confluent.connect.sftp.source.SftpInputFile@284d238e. (io.confluent.connect.sftp.source.AbstractSftpSourceTask)
# org.apache.kafka.connect.errors.ConnectException: Exception thrown while parsing data for 'id'. linenumber=2
# 	at io.confluent.connect.sftp.source.SftpCsvSourceTask.parseField(SftpCsvSourceTask.java:206)
# 	at io.confluent.connect.sftp.source.SftpCsvSourceTask.process(SftpCsvSourceTask.java:161)
# 	at io.confluent.connect.sftp.source.AbstractSftpSourceTask.read(AbstractSftpSourceTask.java:202)
# 	at io.confluent.connect.sftp.source.AbstractSftpSourceTask.poll(AbstractSftpSourceTask.java:131)
# 	at org.apache.kafka.connect.runtime.WorkerSourceTask.poll(WorkerSourceTask.java:265)
# 	at org.apache.kafka.connect.runtime.WorkerSourceTask.execute(WorkerSourceTask.java:232)
# 	at org.apache.kafka.connect.runtime.WorkerTask.doRun(WorkerTask.java:177)
# 	at org.apache.kafka.connect.runtime.WorkerTask.run(WorkerTask.java:227)
# 	at java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:511)
# 	at java.util.concurrent.FutureTask.run(FutureTask.java:266)
# 	at java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1149)
# 	at java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:624)
# 	at java.lang.Thread.run(Thread.java:748)
# Caused by: org.apache.kafka.connect.errors.DataException: Could not parse 'NOTANDINTEGER' to 'Long'
# 	at com.github.jcustenborder.kafka.connect.utils.data.Parser.parseString(Parser.java:113)
# 	at io.confluent.connect.sftp.source.SftpCsvSourceTask.parseField(SftpCsvSourceTask.java:196)
# 	... 12 more
# Caused by: java.lang.NumberFormatException: For input string: "NOTANDINTEGER"
# 	at java.lang.NumberFormatException.forInputString(NumberFormatException.java:65)
# 	at java.lang.Long.parseLong(Long.java:589)
# 	at java.lang.Long.parseLong(Long.java:631)
# 	at com.github.jcustenborder.kafka.connect.utils.data.type.Int64TypeParser.parseString(Int64TypeParser.java:24)
# 	at com.github.jcustenborder.kafka.connect.utils.data.Parser.parseString(Parser.java:109)
# 	... 13 more
# [2020-03-05 11:18:55,829] DEBUG SFTP Session created successfully (io.confluent.connect.sftp.connection.SftpConnection)
# [2020-03-05 11:18:57,056] ERROR Error during processing, moving /upload/input/csv-sftp-source.csv to /upload/error. (io.confluent.connect.sftp.source.SftpCleanupPolicy)
# [2020-03-05 11:18:57,057] TRACE Moving input file /upload/input/csv-sftp-source.csv to output directory /upload/error. (io.confluent.connect.sftp.source.SftpCleanupPolicy)
# [2020-03-05 11:18:57,058] ERROR Error occurred, logging exception for behavior.on.error=LOG :  (io.confluent.connect.sftp.source.AbstractSftpSourceTask)
# org.apache.kafka.connect.errors.ConnectException: Exception thrown while parsing data for 'id'. linenumber=2
# 	at io.confluent.connect.sftp.source.SftpCsvSourceTask.parseField(SftpCsvSourceTask.java:206)
# 	at io.confluent.connect.sftp.source.SftpCsvSourceTask.process(SftpCsvSourceTask.java:161)
# 	at io.confluent.connect.sftp.source.AbstractSftpSourceTask.read(AbstractSftpSourceTask.java:202)
# 	at io.confluent.connect.sftp.source.AbstractSftpSourceTask.poll(AbstractSftpSourceTask.java:131)
# 	at org.apache.kafka.connect.runtime.WorkerSourceTask.poll(WorkerSourceTask.java:265)
# 	at org.apache.kafka.connect.runtime.WorkerSourceTask.execute(WorkerSourceTask.java:232)
# 	at org.apache.kafka.connect.runtime.WorkerTask.doRun(WorkerTask.java:177)
# 	at org.apache.kafka.connect.runtime.WorkerTask.run(WorkerTask.java:227)
# 	at java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:511)
# 	at java.util.concurrent.FutureTask.run(FutureTask.java:266)
# 	at java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1149)
# 	at java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:624)
# 	at java.lang.Thread.run(Thread.java:748)
# Caused by: org.apache.kafka.connect.errors.DataException: Could not parse 'NOTANDINTEGER' to 'Long'
# 	at com.github.jcustenborder.kafka.connect.utils.data.Parser.parseString(Parser.java:113)
# 	at io.confluent.connect.sftp.source.SftpCsvSourceTask.parseField(SftpCsvSourceTask.java:196)
# 	... 12 more
# Caused by: java.lang.NumberFormatException: For input string: "NOTANDINTEGER"
# 	at java.lang.NumberFormatException.forInputString(NumberFormatException.java:65)
# 	at java.lang.Long.parseLong(Long.java:589)
# 	at java.lang.Long.parseLong(Long.java:631)
# 	at com.github.jcustenborder.kafka.connect.utils.data.type.Int64TypeParser.parseString(Int64TypeParser.java:24)
# 	at com.github.jcustenborder.kafka.connect.utils.data.Parser.parseString(Parser.java:109)
# 	... 13 more