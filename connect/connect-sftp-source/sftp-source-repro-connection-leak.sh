#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh


function display_connections () {
     log "number of connections on port 22 in connect"
     docker exec -it connect netstat -an | grep "22" | wc -l
     log "number of processes in sftp-server"
     docker exec -it sftp-server ps -ef | wc -l
}


${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.repro.yml"

docker exec -i --privileged --user root connect  bash -c "yum -y install net-tools"

docker exec sftp-server bash -c "
mkdir -p /chroot/home/foo/upload/input
mkdir -p /chroot/home/foo/upload/error
mkdir -p /chroot/home/foo/upload/finished

chown -R foo /chroot/home/foo/upload
"

display_connections

i=0
log "Process a file csv-sftp-source$i.csv"
echo $'id,first_name,last_name,email,gender,ip_address,last_login,account_balance,country,favorite_color\n1,Salmon,Baitman,sbaitman0@feedburner.com,Male,120.181.75.98,2015-03-01T06:01:15Z,17462.66,IT,#f09bc0\n2,Debby,Brea,dbrea1@icio.us,Female,153.239.187.49,2018-10-21T12:27:12Z,14693.49,CZ,#73893a' > csv-sftp-source$i.csv
docker cp csv-sftp-source$i.csv sftp-server:/chroot/home/foo/upload/input/
rm -f csv-sftp-source$i.csv

display_connections

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

for i in $(seq 1 5)
do
     display_connections

     log "Process a file csv-sftp-source$i.csv"
     echo $'id,first_name,last_name,email,gender,ip_address,last_login,account_balance,country,favorite_color\n1,Salmon,Baitman,sbaitman0@feedburner.com,Male,120.181.75.98,2015-03-01T06:01:15Z,17462.66,IT,#f09bc0\n2,Debby,Brea,dbrea1@icio.us,Female,153.239.187.49,2018-10-21T12:27:12Z,14693.49,CZ,#73893a' > csv-sftp-source$i.csv
     docker cp csv-sftp-source$i.csv sftp-server:/chroot/home/foo/upload/input/
     rm -f csv-sftp-source$i.csv

     sleep 2

     # log "Verifying topic sftp-testing-topic"
     # timeout 60 docker exec connect kafka-avro-console-consumer -bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic sftp-testing-topic --from-beginning --max-messages 2

     # Check
     display_connections
done

# results
# 14:46:34 number of connections on port 22 in connect
#        3
# 14:46:34 number of processes in sftp-server
#        3
# 14:46:34 Process a file csv-sftp-source0.csv
# 14:46:35 number of connections on port 22 in connect
#        3
# 14:46:35 number of processes in sftp-server
#        3
#   % Total    % Received % Xferd  Average Speed   Time    Time     Time  Current
#                                  Dload  Upload   Total   Spent    Left  Speed
#   0     0    0     0    0     0      0      0 --:100  1395  100   608  100   787    818   1059 --:100  1395  100   608  100   787    818   1059 --:--:-- --:--:-- --:--:--  1875
# {
#   "name": "sftp-source-csv",
#   "config": {
#     "topics": "test_sftp_sink",
#     "tasks.max": "1",
#     "connector.class": "io.confluent.connect.sftp.SftpCsvSourceConnector",
#     "cleanup.policy": "MOVE",
#     "behavior.on.error": "LOG",
#     "input.path": "/home/foo/upload/input",
#     "error.path": "/home/foo/upload/error",
#     "finished.path": "/home/foo/upload/finished",
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
# 14:46:36 number of connections on port 22 in connect
#        4
# 14:46:37 number of processes in sftp-server
#        6
# 14:46:37 Process a file csv-sftp-source1.csv
# 14:46:40 number of connections on port 22 in connect
#        8
# 14:46:40 number of processes in sftp-server
#       15
# 14:46:40 number of connections on port 22 in connect
#        9
# 14:46:41 number of processes in sftp-server
#       18
# 14:46:41 Process a file csv-sftp-source2.csv
# 14:46:44 number of connections on port 22 in connect
#       11
# 14:46:44 number of processes in sftp-server
#       24
# 14:46:44 number of connections on port 22 in connect
#       11
# 14:46:45 number of processes in sftp-server
#       24
# 14:46:45 Process a file csv-sftp-source3.csv
# 14:46:47 number of connections on port 22 in connect
#       12
# 14:46:48 number of processes in sftp-server
#       27
# 14:46:48 number of connections on port 22 in connect
#       12
# 14:46:48 number of processes in sftp-server
#       27
# 14:46:48 Process a file csv-sftp-source4.csv
# 14:46:51 number of connections on port 22 in connect
#       13
# 14:46:51 number of processes in sftp-server
#       30
# 14:46:51 number of connections on port 22 in connect
#       13
# 14:46:52 number of processes in sftp-server
#       30
# 14:46:52 Process a file csv-sftp-source5.csv
# 14:46:54 number of connections on port 22 in connect
#       14
# 14:46:55 number of processes in sftp-server
#       33

