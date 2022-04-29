#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

# FIXED WITH 10.1.7

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"

sleep 10

# Note in this simple example, if you get into an issue with permissions at the local HDFS level, it may be easiest to unlock the permissions unless you want to debug that more.
docker exec namenode bash -c "/opt/hadoop-2.7.4/bin/hdfs dfs -chmod 777  /"

log "Creating HDFS Sink connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class":"io.confluent.connect.hdfs.HdfsSinkConnector",
               "tasks.max":"1",
               "topics":"test_hdfs",
               "store.url":"hdfs://namenode:8020",
               "flush.size":"3",
               "hadoop.conf.dir":"/etc/hadoop/",
               "path.format": "YYYY",
               "partition.duration.ms": "3600000",
               "filename.offset.zero.pad.width": "1",
               "locale": "en-US",
               "max.retries": "5",
               "partitioner.class": "io.confluent.connect.storage.partitioner.TimeBasedPartitioner",
               "timezone": "UTC",
               "rotate.interval.ms": "30000",
               "logs.dir":"/tmp",
               "confluent.license": "",
               "confluent.topic.bootstrap.servers": "broker:9092",
               "confluent.topic.replication.factor": "1",
               "key.converter":"org.apache.kafka.connect.storage.StringConverter",
               "value.converter":"io.confluent.connect.avro.AvroConverter",
               "value.converter.schema.registry.url":"http://schema-registry:8081",
               "schema.compatibility":"BACKWARD",

               "format.class": "io.confluent.connect.hdfs.parquet.ParquetFormat"
          }' \
     http://localhost:8083/connectors/hdfs-sink/config | jq .


log "Sending messages to topic test_hdfs"
seq -f "{\"f1\": \"value%g\"}" 10 | docker exec -i connect kafka-avro-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic test_hdfs --property value.schema='{"type":"record","name":"myrecord","fields":[{"name":"f1","type":"string"}]}'

sleep 10

log "Listing content of /topics/test_hdfs and /topics/+tmp in HDFS"
docker exec namenode bash -c "/opt/hadoop-2.7.4/bin/hdfs dfs -ls /topics/test_hdfs/2022"
docker exec namenode bash -c "/opt/hadoop-2.7.4/bin/hdfs dfs -ls /topics/+tmp/test_hdfs/2022"

# Found 3 items
# -rw-r--r--   3 appuser supergroup        461 2022-04-07 12:41 /topics/test_hdfs/2022/test_hdfs+0+0+2.parquet
# -rw-r--r--   3 appuser supergroup        461 2022-04-07 12:41 /topics/test_hdfs/2022/test_hdfs+0+3+5.parquet
# -rw-r--r--   3 appuser supergroup        461 2022-04-07 12:41 /topics/test_hdfs/2022/test_hdfs+0+6+8.parquet
# Found 1 items
# -rw-r--r--   3 appuser supergroup          0 2022-04-07 12:41 /topics/+tmp/test_hdfs/2022/6ae82507-fc0e-435d-b525-937a0d45a5ae_tmp.parquet

# log "delete connector"
# curl -X DELETE localhost:8083/connectors/hdfs-sink

log "restart connect"
docker restart connect
sleep 60

# [2022-04-07 12:41:13,828] INFO [hdfs-sink|task-0] Starting commit and rotation for topic partition test_hdfs-0 with start offsets {2022=0} and end offsets {2022=2} (io.confluent.connect.hdfs.TopicPartitionWriter:377)
# [2022-04-07 12:41:14,906] INFO [hdfs-sink|task-0] Committed hdfs://namenode:8020/topics/test_hdfs/2022/test_hdfs+0+0+2.parquet for test_hdfs-0 (io.confluent.connect.hdfs.TopicPartitionWriter:894)
# [2022-04-07 12:41:14,907] INFO [hdfs-sink|task-0] Opening record writer for: hdfs://namenode:8020/topics//+tmp/test_hdfs/2022/6ae82507-fc0e-435d-b525-937a0d45a5ae_tmp.parquet (io.confluent.connect.hdfs.parquet.ParquetRecordWriterProvider:70)
# [2022-04-07 12:41:14,912] INFO [hdfs-sink|task-0] Starting commit and rotation for topic partition test_hdfs-0 with start offsets {2022=3} and end offsets {2022=5} (io.confluent.connect.hdfs.TopicPartitionWriter:377)
# [2022-04-07 12:41:14,947] INFO [hdfs-sink|task-0] Committed hdfs://namenode:8020/topics/test_hdfs/2022/test_hdfs+0+3+5.parquet for test_hdfs-0 (io.confluent.connect.hdfs.TopicPartitionWriter:894)
# [2022-04-07 12:41:14,947] INFO [hdfs-sink|task-0] Opening record writer for: hdfs://namenode:8020/topics//+tmp/test_hdfs/2022/6ae82507-fc0e-435d-b525-937a0d45a5ae_tmp.parquet (io.confluent.connect.hdfs.parquet.ParquetRecordWriterProvider:70)
# [2022-04-07 12:41:14,951] INFO [hdfs-sink|task-0] Starting commit and rotation for topic partition test_hdfs-0 with start offsets {2022=6} and end offsets {2022=8} (io.confluent.connect.hdfs.TopicPartitionWriter:377)
# [2022-04-07 12:41:14,982] INFO [hdfs-sink|task-0] Committed hdfs://namenode:8020/topics/test_hdfs/2022/test_hdfs+0+6+8.parquet for test_hdfs-0 (io.confluent.connect.hdfs.TopicPartitionWriter:894)
# [2022-04-07 12:41:14,983] INFO [hdfs-sink|task-0] Opening record writer for: hdfs://namenode:8020/topics//+tmp/test_hdfs/2022/6ae82507-fc0e-435d-b525-937a0d45a5ae_tmp.parquet (io.confluent.connect.hdfs.parquet.ParquetRecordWriterProvider:70)
# [2022-04-07 12:42:00,968] INFO Kafka Connect stopping (org.apache.kafka.connect.runtime.Connect:67)
# [2022-04-07 12:42:00,969] INFO Stopping REST server (org.apache.kafka.connect.runtime.rest.RestServer:316)
# [2022-04-07 12:42:00,977] INFO Stopped http_8083@72fa021{HTTP/1.1, (http/1.1)}{0.0.0.0:8083} (org.eclipse.jetty.server.AbstractConnector:381)
# [2022-04-07 12:42:00,978] INFO node0 Stopped scavenging (org.eclipse.jetty.server.session:149)
# [2022-04-07 12:42:00,982] INFO REST server stopped (org.apache.kafka.connect.runtime.rest.RestServer:333)
# [2022-04-07 12:42:00,983] INFO [Worker clientId=connect-1, groupId=connect-cluster] Herder stopping (org.apache.kafka.connect.runtime.distributed.DistributedHerder:731)
# [2022-04-07 12:42:00,983] INFO [Worker clientId=connect-1, groupId=connect-cluster] Stopping connectors and tasks that are still assigned to this worker. (org.apache.kafka.connect.runtime.distributed.DistributedHerder:696)
# [2022-04-07 12:42:00,984] INFO [hdfs-sink|worker] Stopping connector hdfs-sink (org.apache.kafka.connect.runtime.Worker:411)
# [2022-04-07 12:42:00,984] INFO [hdfs-sink|worker] Scheduled shutdown for WorkerConnector{id=hdfs-sink} (org.apache.kafka.connect.runtime.WorkerConnector:249)
# [2022-04-07 12:42:00,984] INFO [hdfs-sink|task-0] Stopping task hdfs-sink-0 (org.apache.kafka.connect.runtime.Worker:919)
# [2022-04-07 12:42:00,985] INFO [hdfs-sink|worker] Completed shutdown for WorkerConnector{id=hdfs-sink} (org.apache.kafka.connect.runtime.WorkerConnector:269)
# [2022-04-07 12:42:00,999] ERROR [hdfs-sink|task-0] Error closing temp file hdfs://namenode:8020/topics//+tmp/test_hdfs/2022/6ae82507-fc0e-435d-b525-937a0d45a5ae_tmp.parquet for test_hdfs-0 2022 when closing TopicPartitionWriter: (io.confluent.connect.hdfs.TopicPartitionWriter:477)
# org.apache.kafka.connect.errors.ConnectException: java.nio.channels.ClosedChannelException
# 	at io.confluent.connect.hdfs.parquet.ParquetRecordWriterProvider$1.close(ParquetRecordWriterProvider.java:112)
# 	at io.confluent.connect.hdfs.TopicPartitionWriter.closeTempFile(TopicPartitionWriter.java:763)
# 	at io.confluent.connect.hdfs.TopicPartitionWriter.close(TopicPartitionWriter.java:475)
# 	at io.confluent.connect.hdfs.DataWriter.close(DataWriter.java:469)
# 	at io.confluent.connect.hdfs.HdfsSinkTask.close(HdfsSinkTask.java:169)
# 	at org.apache.kafka.connect.runtime.WorkerSinkTask.commitOffsets(WorkerSinkTask.java:422)
# 	at org.apache.kafka.connect.runtime.WorkerSinkTask.closePartitions(WorkerSinkTask.java:673)
# 	at org.apache.kafka.connect.runtime.WorkerSinkTask.closeAllPartitions(WorkerSinkTask.java:668)
# 	at org.apache.kafka.connect.runtime.WorkerSinkTask.execute(WorkerSinkTask.java:205)
# 	at org.apache.kafka.connect.runtime.WorkerTask.doRun(WorkerTask.java:199)
# 	at org.apache.kafka.connect.runtime.WorkerTask.run(WorkerTask.java:254)
# 	at java.base/java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:515)
# 	at java.base/java.util.concurrent.FutureTask.run(FutureTask.java:264)
# 	at java.base/java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1128)
# 	at java.base/java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:628)
# 	at java.base/java.lang.Thread.run(Thread.java:829)
# Caused by: java.nio.channels.ClosedChannelException
# 	at org.apache.hadoop.hdfs.DataStreamer$LastExceptionInStreamer.throwException4Close(DataStreamer.java:324)
# 	at org.apache.hadoop.hdfs.DFSOutputStream.checkClosed(DFSOutputStream.java:151)
# 	at org.apache.hadoop.fs.FSOutputSummer.write(FSOutputSummer.java:105)
# 	at org.apache.hadoop.fs.FSDataOutputStream$PositionCache.write(FSDataOutputStream.java:58)
# 	at java.base/java.io.DataOutputStream.write(DataOutputStream.java:107)
# 	at java.base/java.io.FilterOutputStream.write(FilterOutputStream.java:108)
# 	at org.apache.parquet.hadoop.util.HadoopPositionOutputStream.write(HadoopPositionOutputStream.java:45)
# 	at org.apache.parquet.bytes.ConcatenatingByteArrayCollector.writeAllTo(ConcatenatingByteArrayCollector.java:46)
# 	at org.apache.parquet.hadoop.ParquetFileWriter.writeColumnChunk(ParquetFileWriter.java:620)
# 	at org.apache.parquet.hadoop.ColumnChunkPageWriteStore$ColumnChunkPageWriter.writeToFileWriter(ColumnChunkPageWriteStore.java:241)
# 	at org.apache.parquet.hadoop.ColumnChunkPageWriteStore.flushToFileWriter(ColumnChunkPageWriteStore.java:319)
# 	at org.apache.parquet.hadoop.InternalParquetRecordWriter.flushRowGroupToStore(InternalParquetRecordWriter.java:173)
# 	at org.apache.parquet.hadoop.InternalParquetRecordWriter.close(InternalParquetRecordWriter.java:114)
# 	at org.apache.parquet.hadoop.ParquetWriter.close(ParquetWriter.java:310)
# 	at io.confluent.connect.hdfs.parquet.ParquetRecordWriterProvider$1.close(ParquetRecordWriterProvider.java:110)
# 	... 15 more
# [2022-04-07 12:42:01,009] ERROR [hdfs-sink|task-0] Error deleting temp file hdfs://namenode:8020/topics//+tmp/test_hdfs/2022/6ae82507-fc0e-435d-b525-937a0d45a5ae_tmp.parquet for test_hdfs-0 2022 when closing TopicPartitionWriter: (io.confluent.connect.hdfs.TopicPartitionWriter:489)
# org.apache.kafka.connect.errors.ConnectException: java.io.IOException: The client is stopped
# 	at io.confluent.connect.hdfs.storage.HdfsStorage.delete(HdfsStorage.java:165)
# 	at io.confluent.connect.hdfs.TopicPartitionWriter.deleteTempFile(TopicPartitionWriter.java:900)
# 	at io.confluent.connect.hdfs.TopicPartitionWriter.close(TopicPartitionWriter.java:487)
# 	at io.confluent.connect.hdfs.DataWriter.close(DataWriter.java:469)
# 	at io.confluent.connect.hdfs.HdfsSinkTask.close(HdfsSinkTask.java:169)
# 	at org.apache.kafka.connect.runtime.WorkerSinkTask.commitOffsets(WorkerSinkTask.java:422)
# 	at org.apache.kafka.connect.runtime.WorkerSinkTask.closePartitions(WorkerSinkTask.java:673)
# 	at org.apache.kafka.connect.runtime.WorkerSinkTask.closeAllPartitions(WorkerSinkTask.java:668)
# 	at org.apache.kafka.connect.runtime.WorkerSinkTask.execute(WorkerSinkTask.java:205)
# 	at org.apache.kafka.connect.runtime.WorkerTask.doRun(WorkerTask.java:199)
# 	at org.apache.kafka.connect.runtime.WorkerTask.run(WorkerTask.java:254)
# 	at java.base/java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:515)
# 	at java.base/java.util.concurrent.FutureTask.run(FutureTask.java:264)
# 	at java.base/java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1128)
# 	at java.base/java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:628)
# 	at java.base/java.lang.Thread.run(Thread.java:829)
# Caused by: java.io.IOException: The client is stopped
# 	at org.apache.hadoop.ipc.Client.getConnection(Client.java:1579)
# 	at org.apache.hadoop.ipc.Client.call(Client.java:1441)
# 	at org.apache.hadoop.ipc.Client.call(Client.java:1394)
# 	at org.apache.hadoop.ipc.ProtobufRpcEngine$Invoker.invoke(ProtobufRpcEngine.java:232)
# 	at org.apache.hadoop.ipc.ProtobufRpcEngine$Invoker.invoke(ProtobufRpcEngine.java:118)
# 	at com.sun.proxy.$Proxy55.delete(Unknown Source)
# 	at org.apache.hadoop.hdfs.protocolPB.ClientNamenodeProtocolTranslatorPB.delete(ClientNamenodeProtocolTranslatorPB.java:572)
# 	at java.base/jdk.internal.reflect.NativeMethodAccessorImpl.invoke0(Native Method)
# 	at java.base/jdk.internal.reflect.NativeMethodAccessorImpl.invoke(NativeMethodAccessorImpl.java:62)
# 	at java.base/jdk.internal.reflect.DelegatingMethodAccessorImpl.invoke(DelegatingMethodAccessorImpl.java:43)
# 	at java.base/java.lang.reflect.Method.invoke(Method.java:566)
# 	at org.apache.hadoop.io.retry.RetryInvocationHandler.invokeMethod(RetryInvocationHandler.java:422)
# 	at org.apache.hadoop.io.retry.RetryInvocationHandler$Call.invokeMethod(RetryInvocationHandler.java:165)
# 	at org.apache.hadoop.io.retry.RetryInvocationHandler$Call.invoke(RetryInvocationHandler.java:157)
# 	at org.apache.hadoop.io.retry.RetryInvocationHandler$Call.invokeOnce(RetryInvocationHandler.java:95)
# 	at org.apache.hadoop.io.retry.RetryInvocationHandler.invoke(RetryInvocationHandler.java:359)
# 	at com.sun.proxy.$Proxy56.delete(Unknown Source)
# 	at org.apache.hadoop.hdfs.DFSClient.delete(DFSClient.java:1614)
# 	at org.apache.hadoop.hdfs.DistributedFileSystem$19.doCall(DistributedFileSystem.java:882)
# 	at org.apache.hadoop.hdfs.DistributedFileSystem$19.doCall(DistributedFileSystem.java:879)
# 	at org.apache.hadoop.fs.FileSystemLinkResolver.resolve(FileSystemLinkResolver.java:81)
# 	at org.apache.hadoop.hdfs.DistributedFileSystem.delete(DistributedFileSystem.java:879)
# 	at io.confluent.connect.hdfs.storage.HdfsStorage.delete(HdfsStorage.java:163)
# 	... 15 more
# [2022-04-07 12:42:01,020] INFO [hdfs-sink|task-0] Stopping HDFS Sink Task hdfs-sink-0 (io.confluent.connect.hdfs.HdfsSinkTask:175)


# [2022-04-07 12:43:29,267] INFO [hdfs-sink|task-0] Got brand-new compressor [.snappy] (org.apache.hadoop.io.compress.CodecPool:153)
# [2022-04-07 12:44:28,043] INFO [hdfs-sink|task-0] committing files after waiting for rotateIntervalMs time but less than flush.size records available. (io.confluent.connect.hdfs.TopicPartitionWriter:431)
# [2022-04-07 12:44:28,168] INFO [hdfs-sink|task-0] Committed hdfs://namenode:8020/topics/test_hdfs/2022/test_hdfs+0+9+9.parquet for test_hdfs-0 (io.confluent.connect.hdfs.TopicPartitionWriter:894)

log "Listing content of /topics/test_hdfs and /topics/+tmp in HDFS"
docker exec namenode bash -c "/opt/hadoop-2.7.4/bin/hdfs dfs -ls /topics/test_hdfs/2022"
docker exec namenode bash -c "/opt/hadoop-2.7.4/bin/hdfs dfs -ls /topics/+tmp/test_hdfs/2022"

# Found 4 items
# -rw-r--r--   3 appuser supergroup        461 2022-04-07 12:41 /topics/test_hdfs/2022/test_hdfs+0+0+2.parquet
# -rw-r--r--   3 appuser supergroup        461 2022-04-07 12:41 /topics/test_hdfs/2022/test_hdfs+0+3+5.parquet
# -rw-r--r--   3 appuser supergroup        461 2022-04-07 12:41 /topics/test_hdfs/2022/test_hdfs+0+6+8.parquet
# -rw-r--r--   3 appuser supergroup        470 2022-04-07 12:44 /topics/test_hdfs/2022/test_hdfs+0+9+9.parquet

# Found 1 items
# -rw-r--r--   3 appuser supergroup          4 2022-04-07 12:42 /topics/+tmp/test_hdfs/2022/6ae82507-fc0e-435d-b525-937a0d45a5ae_tmp.parquet






# With AVRO: 

# 14:20:33 ℹ️ Listing content of /topics/test_hdfs and /topics/+tmp in HDFS
# Found 3 items
# -rw-r--r--   3 appuser supergroup        213 2022-04-07 14:20 /topics/test_hdfs/2022/test_hdfs+0+0+2.avro
# -rw-r--r--   3 appuser supergroup        213 2022-04-07 14:20 /topics/test_hdfs/2022/test_hdfs+0+3+5.avro
# -rw-r--r--   3 appuser supergroup        213 2022-04-07 14:20 /topics/test_hdfs/2022/test_hdfs+0+6+8.avro
# Found 1 items
# -rw-r--r--   3 appuser supergroup          0 2022-04-07 14:20 /topics/+tmp/test_hdfs/2022/32422d34-33e6-4ed5-a9e8-219dacad8598_tmp.avro


# 14:22:14 ℹ️ Listing content of /topics/test_hdfs and /topics/+tmp in HDFS
# Found 3 items
# -rw-r--r--   3 appuser supergroup        213 2022-04-07 14:20 /topics/test_hdfs/2022/test_hdfs+0+0+2.avro
# -rw-r--r--   3 appuser supergroup        213 2022-04-07 14:20 /topics/test_hdfs/2022/test_hdfs+0+3+5.avro
# -rw-r--r--   3 appuser supergroup        213 2022-04-07 14:20 /topics/test_hdfs/2022/test_hdfs+0+6+8.avro
# Found 1 items
# -rw-r--r--   3 appuser supergroup        200 2022-04-07 14:21 /topics/+tmp/test_hdfs/2022/32422d34-33e6-4ed5-a9e8-219dacad8598_tmp.avro

# [2022-04-07 14:21:12,550] ERROR [hdfs-sink|task-0] Error deleting temp file hdfs://namenode:8020/topics//+tmp/test_hdfs/2022/32422d34-33e6-4ed5-a9e8-219dacad8598_tmp.avro for test_hdfs-0 2022 when closing TopicPartitionWriter: (io.confluent.connect.hdfs.TopicPartitionWriter:489)
# org.apache.kafka.connect.errors.ConnectException: java.io.IOException: Filesystem closed
# 	at io.confluent.connect.hdfs.storage.HdfsStorage.delete(HdfsStorage.java:165)
# 	at io.confluent.connect.hdfs.TopicPartitionWriter.deleteTempFile(TopicPartitionWriter.java:900)
# 	at io.confluent.connect.hdfs.TopicPartitionWriter.close(TopicPartitionWriter.java:487)
# 	at io.confluent.connect.hdfs.DataWriter.close(DataWriter.java:469)
# 	at io.confluent.connect.hdfs.HdfsSinkTask.close(HdfsSinkTask.java:169)
# 	at org.apache.kafka.connect.runtime.WorkerSinkTask.commitOffsets(WorkerSinkTask.java:422)
# 	at org.apache.kafka.connect.runtime.WorkerSinkTask.closePartitions(WorkerSinkTask.java:673)
# 	at org.apache.kafka.connect.runtime.WorkerSinkTask.closeAllPartitions(WorkerSinkTask.java:668)
# 	at org.apache.kafka.connect.runtime.WorkerSinkTask.execute(WorkerSinkTask.java:205)
# 	at org.apache.kafka.connect.runtime.WorkerTask.doRun(WorkerTask.java:199)
# 	at org.apache.kafka.connect.runtime.WorkerTask.run(WorkerTask.java:254)
# 	at java.base/java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:515)
# 	at java.base/java.util.concurrent.FutureTask.run(FutureTask.java:264)
# 	at java.base/java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1128)
# 	at java.base/java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:628)
# 	at java.base/java.lang.Thread.run(Thread.java:829)
# Caused by: java.io.IOException: Filesystem closed
# 	at org.apache.hadoop.hdfs.DFSClient.checkOpen(DFSClient.java:484)
# 	at org.apache.hadoop.hdfs.DFSClient.delete(DFSClient.java:1612)
# 	at org.apache.hadoop.hdfs.DistributedFileSystem$19.doCall(DistributedFileSystem.java:882)
# 	at org.apache.hadoop.hdfs.DistributedFileSystem$19.doCall(DistributedFileSystem.java:879)
# 	at org.apache.hadoop.fs.FileSystemLinkResolver.resolve(FileSystemLinkResolver.java:81)
# 	at org.apache.hadoop.hdfs.DistributedFileSystem.delete(DistributedFileSystem.java:879)
# 	at io.confluent.connect.hdfs.storage.HdfsStorage.delete(HdfsStorage.java:163)
# 	... 15 more