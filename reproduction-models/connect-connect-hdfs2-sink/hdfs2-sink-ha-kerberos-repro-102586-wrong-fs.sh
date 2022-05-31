#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if [ ! -f ${DIR}/hadoop-2.7.4.tar.gz ]
then
     log "Getting hadoop-2.7.4.tar.gz"
     wget https://archive.apache.org/dist/hadoop/common/hadoop-2.7.4/hadoop-2.7.4.tar.gz
fi

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.ha-kerberos.repro-102586-wrong-fs.yml"

log "Wait 120 seconds while hadoop is installing"
sleep 120

# Note in this simple example, if you get into an issue with permissions at the local HDFS level, it may be easiest to unlock the permissions unless you want to debug that more.
docker exec namenode1 bash -c "kinit -kt /opt/hadoop/etc/hadoop/nn.keytab nn/namenode1.kerberos-demo.local && /opt/hadoop/bin/hdfs dfs -chmod 777  /"

log "Add connect kerberos principal"
docker exec -i krb5 kadmin.local << EOF
addprinc -randkey connect/connect.kerberos-demo.local@EXAMPLE.COM
modprinc -maxrenewlife 11days +allow_renewable connect/connect.kerberos-demo.local@EXAMPLE.COM
modprinc -maxrenewlife 11days krbtgt/EXAMPLE.COM
modprinc -maxlife 11days connect/connect.kerberos-demo.local@EXAMPLE.COM
ktadd -k /connect.keytab connect/connect.kerberos-demo.local@EXAMPLE.COM
listprincs
EOF

log "Copy connect.keytab to connect container /tmp/sshuser.keytab"
docker cp krb5:/connect.keytab .
docker cp connect.keytab connect:/tmp/connect.keytab
if [[ "$TAG" == *ubi8 ]] || version_gt $TAG_BASE "5.9.0"
then
     docker exec -u 0 connect chown appuser:appuser /tmp/connect.keytab
fi

log "Creating HDFS Sink connector with wrong FS"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class":"io.confluent.connect.hdfs.HdfsSinkConnector",
               "tasks.max":"1",
               "topics":"test_hdfs",
               "store.url":"hdfs://namenode1:9820",
               "flush.size":"3",
               "hadoop.conf.dir":"/opt/hadoop/etc/hadoop/",
               "partitioner.class":"io.confluent.connect.hdfs.partitioner.FieldPartitioner",
               "partition.field.name":"f1",
               "rotate.interval.ms":"120000",
               "logs.dir":"/logs",
               "hdfs.authentication.kerberos": "true",
               "connect.hdfs.principal": "connect/connect.kerberos-demo.local@EXAMPLE.COM",
               "connect.hdfs.keytab": "/tmp/connect.keytab",
               "hdfs.namenode.principal": "nn/namenode1.kerberos-demo.local@EXAMPLE.COM",
               "key.converter":"org.apache.kafka.connect.storage.StringConverter",
               "value.converter":"io.confluent.connect.avro.AvroConverter",
               "value.converter.schema.registry.url":"http://schema-registry:8081",
               "schema.compatibility":"BACKWARD"
          }' \
     http://localhost:8083/connectors/hdfs2-sink-ha-kerberos/config | jq .


log "Sending messages to topic test_hdfs"
seq -f "{\"f1\": \"value%g\"}" 10 | docker exec -i connect kafka-avro-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic test_hdfs --property value.schema='{"type":"record","name":"myrecord","fields":[{"name":"f1","type":"string"}]}'

sleep 10

log "Listing content of /topics/test_hdfs in HDFS"
docker exec namenode1 bash -c "kinit -kt /opt/hadoop/etc/hadoop/nn.keytab nn/namenode1.kerberos-demo.local && /opt/hadoop/bin/hdfs dfs -ls /topics/test_hdfs"

log "Getting one of the avro files locally and displaying content with avro-tools"
docker exec namenode1 bash -c "kinit -kt /opt/hadoop/etc/hadoop/nn.keytab nn/namenode1.kerberos-demo.local && /opt/hadoop/bin/hadoop fs -copyToLocal /topics/test_hdfs/f1=value1/test_hdfs+0+0000000000+0000000000.avro /tmp"
docker cp namenode1:/tmp/test_hdfs+0+0000000000+0000000000.avro /tmp/

docker run --rm -v /tmp:/tmp actions/avro-tools tojson /tmp/test_hdfs+0+0000000000+0000000000.avro

log "Creating HDFS Sink connector with correct FS"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class":"io.confluent.connect.hdfs.HdfsSinkConnector",
               "tasks.max":"1",
               "topics":"test_hdfs",
               "store.url":"hdfs://sh",
               "flush.size":"3",
               "hadoop.conf.dir":"/opt/hadoop/etc/hadoop/",
               "partitioner.class":"io.confluent.connect.hdfs.partitioner.FieldPartitioner",
               "partition.field.name":"f1",
               "rotate.interval.ms":"120000",
               "logs.dir":"/logs",
               "hdfs.authentication.kerberos": "true",
               "connect.hdfs.principal": "connect/connect.kerberos-demo.local@EXAMPLE.COM",
               "connect.hdfs.keytab": "/tmp/connect.keytab",
               "hdfs.namenode.principal": "nn/namenode1.kerberos-demo.local@EXAMPLE.COM",
               "key.converter":"org.apache.kafka.connect.storage.StringConverter",
               "value.converter":"io.confluent.connect.avro.AvroConverter",
               "value.converter.schema.registry.url":"http://schema-registry:8081",
               "schema.compatibility":"BACKWARD"
          }' \
     http://localhost:8083/connectors/hdfs2-sink-ha-kerberos/config | jq .

sleep 10

log "Sending messages to topic test_hdfs"
seq -f "{\"f1\": \"value%g\"}" 10 | docker exec -i connect kafka-avro-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic test_hdfs --property value.schema='{"type":"record","name":"myrecord","fields":[{"name":"f1","type":"string"}]}'


# [2022-05-31 11:15:04,428] ERROR [hdfs2-sink-ha-kerberos|task-0] WorkerSinkTask{id=hdfs2-sink-ha-kerberos-0} Task threw an uncaught and unrecoverable exception. Task is being killed and will not recover until manually restarted (org.apache.kafka.connect.runtime.WorkerTask:207)
# java.lang.IllegalArgumentException: Wrong FS: hdfs://namenode1:9820/topics/test_hdfs/f1=value2/test_hdfs+0+0000000001+0000000001.avro, expected: hdfs://sh
#         at org.apache.hadoop.fs.FileSystem.checkPath(FileSystem.java:778)
#         at org.apache.hadoop.hdfs.DistributedFileSystem.getPathName(DistributedFileSystem.java:213)
#         at org.apache.hadoop.hdfs.DistributedFileSystem$29.doCall(DistributedFileSystem.java:1524)
#         at org.apache.hadoop.hdfs.DistributedFileSystem$29.doCall(DistributedFileSystem.java:1521)
#         at org.apache.hadoop.fs.FileSystemLinkResolver.resolve(FileSystemLinkResolver.java:81)
#         at org.apache.hadoop.hdfs.DistributedFileSystem.getFileStatus(DistributedFileSystem.java:1521)
#         at org.apache.hadoop.fs.FileSystem.exists(FileSystem.java:1632)
#         at io.confluent.connect.hdfs.storage.HdfsStorage.exists(HdfsStorage.java:150)
#         at io.confluent.connect.hdfs.wal.FSWAL.commitEntriesToStorage(FSWAL.java:192)
#         at io.confluent.connect.hdfs.wal.FSWAL.commitWalEntriesToStorage(FSWAL.java:173)
#         at io.confluent.connect.hdfs.wal.FSWAL.apply(FSWAL.java:141)
#         at io.confluent.connect.hdfs.TopicPartitionWriter.applyWAL(TopicPartitionWriter.java:703)
#         at io.confluent.connect.hdfs.TopicPartitionWriter.recover(TopicPartitionWriter.java:262)
#         at io.confluent.connect.hdfs.DataWriter.recover(DataWriter.java:392)
#         at io.confluent.connect.hdfs.DataWriter.open(DataWriter.java:463)
#         at io.confluent.connect.hdfs.HdfsSinkTask.open(HdfsSinkTask.java:162)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.openPartitions(WorkerSinkTask.java:644)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.access$1200(WorkerSinkTask.java:73)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask$HandleRebalance.onPartitionsAssigned(WorkerSinkTask.java:740)
#         at org.apache.kafka.clients.consumer.internals.ConsumerCoordinator.invokePartitionsAssigned(ConsumerCoordinator.java:296)
#         at org.apache.kafka.clients.consumer.internals.ConsumerCoordinator.onJoinComplete(ConsumerCoordinator.java:433)
#         at org.apache.kafka.clients.consumer.internals.AbstractCoordinator.joinGroupIfNeeded(AbstractCoordinator.java:450)
#         at org.apache.kafka.clients.consumer.internals.AbstractCoordinator.ensureActiveGroup(AbstractCoordinator.java:366)
#         at org.apache.kafka.clients.consumer.internals.ConsumerCoordinator.poll(ConsumerCoordinator.java:511)
#         at org.apache.kafka.clients.consumer.KafkaConsumer.updateAssignmentMetadataIfNeeded(KafkaConsumer.java:1262)
#         at org.apache.kafka.clients.consumer.KafkaConsumer.poll(KafkaConsumer.java:1231)
#         at org.apache.kafka.clients.consumer.KafkaConsumer.poll(KafkaConsumer.java:1211)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.pollConsumer(WorkerSinkTask.java:473)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.poll(WorkerSinkTask.java:329)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.iteration(WorkerSinkTask.java:235)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.execute(WorkerSinkTask.java:204)
#         at org.apache.kafka.connect.runtime.WorkerTask.doRun(WorkerTask.java:200)
#         at org.apache.kafka.connect.runtime.WorkerTask.run(WorkerTask.java:255)
#         at java.base/java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:515)
#         at java.base/java.util.concurrent.FutureTask.run(FutureTask.java:264)
#         at java.base/java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1128)
#         at java.base/java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:628)
#         at java.base/java.lang.Thread.run(Thread.java:829)