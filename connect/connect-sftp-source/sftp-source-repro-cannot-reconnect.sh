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
               "csv.first.row.as.header": "true",
               "schema.generation.enabled": "true"
          }' \
     http://localhost:8083/connectors/sftp-source-csv/config | jq .

sleep 5

log "Process a file csv-sftp-source1.csv"
echo $'id,first_name,last_name,email,gender,ip_address,last_login,account_balance,country,favorite_color\n1,Salmon,Baitman,sbaitman0@feedburner.com,Male,120.181.75.98,2015-03-01T06:01:15Z,17462.66,IT,#f09bc0\n2,Debby,Brea,dbrea1@icio.us,Female,153.239.187.49,2018-10-21T12:27:12Z,14693.49,CZ,#73893a' > csv-sftp-source1.csv
docker cp csv-sftp-source1.csv sftp-server:/chroot/home/foo/upload/input/
rm -f csv-sftp-source1.csv

sleep 5

log "netstat -an | grep 22"
set +e
docker exec connect netstat -an | grep 22
set -e

log "Restart SFTP server"
docker container restart sftp-server

sleep 20

log "netstat -an | grep 22"
set +e
docker exec connect netstat -an | grep 22
set -e

log "Process a file csv-sftp-source2.csv"
echo $'id,first_name,last_name,email,gender,ip_address,last_login,account_balance,country,favorite_color\n1,Salmon,Baitman,sbaitman0@feedburner.com,Male,120.181.75.98,2015-03-01T06:01:15Z,17462.66,IT,#f09bc0\n2,Debby,Brea,dbrea1@icio.us,Female,153.239.187.49,2018-10-21T12:27:12Z,14693.49,CZ,#73893a' > csv-sftp-source2.csv
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

# [2020-03-05 15:03:09,937] INFO WorkerSourceTask{id=sftp-source-csv-0} Finished commitOffsets successfully in 18 ms (org.apache.kafka.connect.runtime.WorkerSourceTask)
# [2020-03-05 15:03:09,937] ERROR WorkerSourceTask{id=sftp-source-csv-0} Task threw an uncaught and unrecoverable exception (org.apache.kafka.connect.runtime.WorkerTask)
# org.apache.kafka.connect.errors.ConnectException: Can not get connection to SFTP:
#         at io.confluent.connect.sftp.connection.SftpConnection.init(SftpConnection.java:101)
#         at io.confluent.connect.sftp.connection.SftpConnection.<init>(SftpConnection.java:55)
#         at io.confluent.connect.sftp.source.SftpCsvSourceConnectorConfig.getSftpConnection(SftpCsvSourceConnectorConfig.java:638)
#         at io.confluent.connect.sftp.source.AbstractSftpSourceTask.read(AbstractSftpSourceTask.java:213)
#         at io.confluent.connect.sftp.source.AbstractSftpSourceTask.poll(AbstractSftpSourceTask.java:131)
#         at org.apache.kafka.connect.runtime.WorkerSourceTask.poll(WorkerSourceTask.java:265)
#         at org.apache.kafka.connect.runtime.WorkerSourceTask.execute(WorkerSourceTask.java:232)
#         at org.apache.kafka.connect.runtime.WorkerTask.doRun(WorkerTask.java:177)
#         at org.apache.kafka.connect.runtime.WorkerTask.run(WorkerTask.java:227)
#         at java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:511)
#         at java.util.concurrent.FutureTask.run(FutureTask.java:266)
#         at java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1149)
#         at java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:624)
#         at java.lang.Thread.run(Thread.java:748)
# Caused by: com.jcraft.jsch.JSchException: java.net.ConnectException: Connection refused (Connection refused)
#         at com.jcraft.jsch.Util.createSocket(Util.java:394)
#         at com.jcraft.jsch.Session.connect(Session.java:215)
#         at com.jcraft.jsch.Session.connect(Session.java:183)
#         at io.confluent.connect.sftp.connection.SftpConnection.init(SftpConnection.java:95)
#         ... 13 more
# Caused by: java.net.ConnectException: Connection refused (Connection refused)
#         at java.net.PlainSocketImpl.socketConnect(Native Method)
#         at java.net.AbstractPlainSocketImpl.doConnect(AbstractPlainSocketImpl.java:350)
#         at java.net.AbstractPlainSocketImpl.connectToAddress(AbstractPlainSocketImpl.java:206)
#         at java.net.AbstractPlainSocketImpl.connect(AbstractPlainSocketImpl.java:188)
#         at java.net.SocksSocketImpl.connect(SocksSocketImpl.java:392)
#         at java.net.Socket.connect(Socket.java:589)
#         at java.net.Socket.connect(Socket.java:538)
#         at java.net.Socket.<init>(Socket.java:434)
#         at java.net.Socket.<init>(Socket.java:211)
#         at com.jcraft.jsch.Util$1.run(Util.java:362)
#         ... 1 more
# [2020-03-05 15:03:09,939] ERROR WorkerSourceTask{id=sftp-source-csv-0} Task is being killed and will not recover until manually restarted (org.apache.kafka.connect.runtime.WorkerTask)
# [2020-03-05 15:03:09,939] INFO Stopping task. (io.confluent.connect.sftp.source.AbstractSftpSourceTask)
# [2020-03-05 15:03:09,940] INFO Closed SFTP connection. (io.confluent.connect.sftp.connection.SftpConnection)


# 16:02:57 Creating connector sftp-source-csv
#   % Total    % Received % Xferd  Average Speed   Time    Time     Time  Current
#                                  Dload  Upload   Total   Spent    Left  Speed
# 100  1341  100   581  100   760    435    569  0:00:01  0:00:01 --:--:--   569
# {
#   "name": "sftp-source-csv",
#   "config": {
#     "topics": "test_sftp_sink",
#     "tasks.max": "1",
#     "connector.class": "io.confluent.connect.sftp.SftpCsvSourceConnector",
#     "cleanup.policy": "MOVE",
#     "behavior.on.error": "LOG",
#     "input.path": "/upload/input",
#     "error.path": "/upload/error",
#     "finished.path": "/upload/finished",
#     "input.file.pattern": "csv-sftp-source(.*).csv",
#     "sftp.username": "foo",
#     "sftp.password": "pass",
#     "sftp.host": "sftp-server",
#     "sftp.port": "22",
#     "kafka.topic": "sftp-testing-topic",
#     "csv.first.row.as.header": "true",
#     "schema.generation.enabled": "true",
#     "name": "sftp-source-csv"
#   },
#   "tasks": [],
#   "type": "source"
# }
# 16:03:04 Process a file csv-sftp-source1.csv
# 16:03:09 netstat -an | grep 22
# tcp        0      0 192.168.144.5:34544     192.168.144.3:22        ESTABLISHED
# tcp        0      0 192.168.144.5:51226     192.168.144.2:9092      TIME_WAIT
# tcp        0      0 192.168.144.5:42896     13.225.29.42:80         TIME_WAIT
# tcp        0      0 192.168.144.5:51228     192.168.144.2:9092      TIME_WAIT
# tcp        0      0 192.168.144.5:51224     192.168.144.2:9092      TIME_WAIT
# tcp        0      0 192.168.144.5:34552     192.168.144.3:22        ESTABLISHED
# unix  2      [ ]         STREAM     CONNECTED     7822540
# 16:03:09 Restart SFTP server
# sftp-server
# 16:03:30 netstat -an | grep 22
# tcp        0      0 192.168.144.5:42896     13.225.29.42:80         TIME_WAIT
# unix  2      [ ]         STREAM     CONNECTED     7822540
# 16:03:30 Process a file csv-sftp-source2.csv
# 16:03:35 Deleting connector sftp-source-csv
# 16:03:40 netstat -an | grep 22
# tcp        0      0 192.168.144.5:34584     192.168.144.3:22        TIME_WAIT
# unix  2      [ ]         STREAM     CONNECTED     7822540
