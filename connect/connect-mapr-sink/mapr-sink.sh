#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"

# https://raw.githubusercontent.com/mapr-demos/mapr-db-60-getting-started/master/mapr_devsandbox_container_setup.sh

log "Installing Mapr Client"
if [[ "$TAG" == *ubi8 ]]
then
     # RHEL
     # required deps for mapr-client
     docker exec -i --privileged --user root -t connect  bash -c "rpm -i http://mirror.centos.org/centos/7/os/x86_64/Packages/mtools-4.0.18-5.el7.x86_64.rpm"
     docker exec -i --privileged --user root -t connect  bash -c "rpm -i http://mirror.centos.org/centos/7/os/x86_64/Packages/syslinux-4.05-15.el7.x86_64.rpm"

     docker exec -i --privileged --user root -t connect  bash -c "yum -y install hostname findutils net-tools"

     docker exec -i --privileged --user root -t connect  bash -c "rpm --import https://package.mapr.com/releases/pub/maprgpg.key && yum -y update && yum -y install mapr-client.x86_64"
else
     logerror "This can only be run with UBI image"
     exit 1
fi

CONNECT_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' connect)
MAPR_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' mapr)

log "Login with maprlogin"
docker exec -i mapr bash -c "maprlogin password -user mapr" << EOF
mapr
EOF

log "Create table /mapr/maprdemo.mapr.io/maprtopic"
docker exec -i mapr bash -c "mapr dbshell" << EOF
create /mapr/maprdemo.mapr.io/maprtopic
EOF


# log "Set MAPR_EXTERNAL on mapr"
# docker exec -i --privileged --user root mapr bash -c "sed -i \"s/MAPR_EXTERNAL=.*/MAPR_EXTERNAL=${CONNECT_IP}/\" /opt/mapr/conf/env.sh"
# docker exec -i --privileged --user root mapr bash -c "service mapr-warden restart"

sleep 30

log "Configure Mapr Client"
docker exec -i --privileged --user root -t connect bash -c "/opt/mapr/server/configure.sh -secure  -N maprdemo.mapr.io -c -C $MAPR_IP:7222 -H mapr -u appuser -g appuser"
#docker exec -i --privileged --user root -t connect bash -c "/opt/mapr/server/configure.sh -N maprdemo.mapr.io -c -C $CONNECT_IP -H mapr -u appuser -g appuser"


log "Sending messages to topic maprtopic"
docker exec -i broker kafka-console-producer --broker-list broker:9092 --topic maprtopic --property parse.key=true --property key.separator=, << EOF
1,{"schema":{"type":"struct","fields":[{"type":"string","optional":false,"field":"record"}]},"payload":{"record":"record1"}}
2,{"schema":{"type":"struct","fields":[{"type":"string","optional":false,"field":"record"}]},"payload":{"record":"record2"}}
3,{"schema":{"type":"struct","fields":[{"type":"string","optional":false,"field":"record"}]},"payload":{"record":"record3"}}
EOF

log "Creating Mapr sink connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.confluent.connect.mapr.db.MapRDbSinkConnector",
               "tasks.max": "1",
               "mapr.table.map.maprtopic" : "/mapr/maprdemo.mapr.io/maprtopic",
               "key.converter": "org.apache.kafka.connect.storage.StringConverter",
               "value.converter": "org.apache.kafka.connect.json.JsonConverter",
               "topics": "maprtopic"
          }' \
     http://localhost:8083/connectors/mapr-sink/config | jq .

sleep 10

# [2020-09-25 09:53:23,765] ERROR WorkerSinkTask{id=mapr-sink-0} Task threw an uncaught and unrecoverable exception. Task is being killed and will not recover until manually restarted. Error: com.mapr.db.exceptions.DBException: tableExists() failed., (org.apache.kafka.connect.runtime.WorkerSinkTask)
# com.google.common.util.concurrent.UncheckedExecutionException: com.mapr.db.exceptions.DBException: tableExists() failed.,
#         at com.google.common.cache.LocalCache$Segment.get(LocalCache.java:2052)
#         at com.google.common.cache.LocalCache.get(LocalCache.java:3963)
#         at com.google.common.cache.LocalCache$LocalManualCache.get(LocalCache.java:4865)
#         at io.confluent.connect.mapr.db.MapRDbSinkTask.put(MapRDbSinkTask.java:72)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.deliverMessages(WorkerSinkTask.java:545)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.poll(WorkerSinkTask.java:325)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.iteration(WorkerSinkTask.java:228)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.execute(WorkerSinkTask.java:200)
#         at org.apache.kafka.connect.runtime.WorkerTask.doRun(WorkerTask.java:184)
#         at org.apache.kafka.connect.runtime.WorkerTask.run(WorkerTask.java:234)
#         at java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:511)
#         at java.util.concurrent.FutureTask.run(FutureTask.java:266)
#         at java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1149)
#         at java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:624)
#         at java.lang.Thread.run(Thread.java:748)
# Caused by: com.mapr.db.exceptions.DBException: tableExists() failed.,
#         at com.mapr.db.exceptions.ExceptionHandler.handle(ExceptionHandler.java:65)
#         at com.mapr.db.impl.AdminImpl.tableExists(AdminImpl.java:318)
#         at com.mapr.db.impl.AdminImpl.tableExists(AdminImpl.java:307)
#         at com.mapr.db.impl.MapRDBImpl.tableExists(MapRDBImpl.java:55)
#         at com.mapr.db.MapRDB.tableExists(MapRDB.java:45)
#         at io.confluent.connect.mapr.db.MapRDbSinkTask.lambda$put$1(MapRDbSinkTask.java:83)
#         at com.google.common.cache.LocalCache$LocalManualCache$1.load(LocalCache.java:4870)
#         at com.google.common.cache.LocalCache$LoadingValueReference.loadFuture(LocalCache.java:3524)
#         at com.google.common.cache.LocalCache$Segment.loadSync(LocalCache.java:2250)
#         at com.google.common.cache.LocalCache$Segment.lockedGetOrLoad(LocalCache.java:2133)
#         at com.google.common.cache.LocalCache$Segment.get(LocalCache.java:2046)
#         ... 14 more
# Caused by: java.io.IOException: Could not create FileClient
#         at com.mapr.fs.MapRFileSystem.lookupClient(MapRFileSystem.java:656)
#         at com.mapr.fs.MapRFileSystem.lookupClient(MapRFileSystem.java:709)
#         at com.mapr.fs.MapRFileSystem.getTableProperties(MapRFileSystem.java:4088)
#         at com.mapr.db.impl.AdminImpl.tableExists(AdminImpl.java:313)
#         ... 23 more
# Caused by: java.io.IOException: Could not create FileClient
#         at com.mapr.fs.MapRClientImpl.<init>(MapRClientImpl.java:137)
#         at com.mapr.fs.MapRFileSystem.lookupClient(MapRFileSystem.java:650)
#         ... 26 more
# [2020-09-25 09:53:23,765] ERROR WorkerSinkTask{id=mapr-sink-0} Task threw an uncaught and unrecoverable exception (org.apache.kafka.connect.runtime.WorkerTask)
# org.apache.kafka.connect.errors.ConnectException: Exiting WorkerSinkTask due to unrecoverable exception.
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.deliverMessages(WorkerSinkTask.java:567)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.poll(WorkerSinkTask.java:325)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.iteration(WorkerSinkTask.java:228)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.execute(WorkerSinkTask.java:200)
#         at org.apache.kafka.connect.runtime.WorkerTask.doRun(WorkerTask.java:184)
#         at org.apache.kafka.connect.runtime.WorkerTask.run(WorkerTask.java:234)
#         at java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:511)
#         at java.util.concurrent.FutureTask.run(FutureTask.java:266)
#         at java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1149)
#         at java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:624)
#         at java.lang.Thread.run(Thread.java:748)
# Caused by: com.google.common.util.concurrent.UncheckedExecutionException: com.mapr.db.exceptions.DBException: tableExists() failed.,
#         at com.google.common.cache.LocalCache$Segment.get(LocalCache.java:2052)
#         at com.google.common.cache.LocalCache.get(LocalCache.java:3963)
#         at com.google.common.cache.LocalCache$LocalManualCache.get(LocalCache.java:4865)
#         at io.confluent.connect.mapr.db.MapRDbSinkTask.put(MapRDbSinkTask.java:72)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.deliverMessages(WorkerSinkTask.java:545)
#         ... 10 more
# Caused by: com.mapr.db.exceptions.DBException: tableExists() failed.,
#         at com.mapr.db.exceptions.ExceptionHandler.handle(ExceptionHandler.java:65)
#         at com.mapr.db.impl.AdminImpl.tableExists(AdminImpl.java:318)
#         at com.mapr.db.impl.AdminImpl.tableExists(AdminImpl.java:307)
#         at com.mapr.db.impl.MapRDBImpl.tableExists(MapRDBImpl.java:55)
#         at com.mapr.db.MapRDB.tableExists(MapRDB.java:45)
#         at io.confluent.connect.mapr.db.MapRDbSinkTask.lambda$put$1(MapRDbSinkTask.java:83)
#         at com.google.common.cache.LocalCache$LocalManualCache$1.load(LocalCache.java:4870)
#         at com.google.common.cache.LocalCache$LoadingValueReference.loadFuture(LocalCache.java:3524)
#         at com.google.common.cache.LocalCache$Segment.loadSync(LocalCache.java:2250)
#         at com.google.common.cache.LocalCache$Segment.lockedGetOrLoad(LocalCache.java:2133)
#         at com.google.common.cache.LocalCache$Segment.get(LocalCache.java:2046)
#         ... 14 more
# Caused by: java.io.IOException: Could not create FileClient
#         at com.mapr.fs.MapRFileSystem.lookupClient(MapRFileSystem.java:656)
#         at com.mapr.fs.MapRFileSystem.lookupClient(MapRFileSystem.java:709)
#         at com.mapr.fs.MapRFileSystem.getTableProperties(MapRFileSystem.java:4088)
#         at com.mapr.db.impl.AdminImpl.tableExists(AdminImpl.java:313)
#         ... 23 more
# Caused by: java.io.IOException: Could not create FileClient
#         at com.mapr.fs.MapRClientImpl.<init>(MapRClientImpl.java:137)
#         at com.mapr.fs.MapRFileSystem.lookupClient(MapRFileSystem.java:650)
#         ... 26 more
# [2020-09-25 09:53:23,766] ERROR WorkerSinkTask{id=mapr-sink-0} Task is being killed and will not recover until manually restarted (org.apache.kafka.connect.runtime.WorkerTask)
log "Verify data is in Mapr"
