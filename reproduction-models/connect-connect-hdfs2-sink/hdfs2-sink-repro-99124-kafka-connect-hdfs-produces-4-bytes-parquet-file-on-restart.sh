#!/bin/bash
set -e

export ENABLE_CONNECT_NODES=true

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

NB_CONNECTORS=10
NB_TASK_PER_CONNECTOR=5

function wait_for_repro () {
     MAX_WAIT=43200
     CUR_WAIT=0
     log "⌛ Waiting up to $MAX_WAIT seconds for repro (it can take several hours)"
     docker container logs connect > /tmp/out.txt 2>&1
     docker container logs connect2 >> /tmp/out.txt 2>&1
     docker container logs connect3 >> /tmp/out.txt 2>&1
     while ! grep "is not a Parquet file" /tmp/out.txt > /dev/null;
     do
          log "Do a rolling update"
          log "restart connect"
          docker kill connect
          docker restart connect
          sleep 60
          log "restart connect2"
          docker kill connect2
          docker restart connect2
          sleep 60
          log "restart connect3"
          docker kill connect3
          docker restart connect3
          sleep 60
          docker container logs connect > /tmp/out.txt 2>&1
          docker container logs connect2 >> /tmp/out.txt 2>&1
          docker container logs connect3 >> /tmp/out.txt 2>&1
          CUR_WAIT=$(( CUR_WAIT+10 ))
          if [[ "$CUR_WAIT" -gt "$MAX_WAIT" ]]; then
               echo -e "\nERROR: The logs in all connect containers do not show 'is not a Parquet file' after $MAX_WAIT seconds. Please troubleshoot with 'docker container ps' and 'docker container logs'.\n"
               exit 1
          fi

          curl http://localhost:8083/connectors?expand=status&expand=info | jq .
     done
     log "The problem has been reproduced !"
}

for component in producer-repro-99124
do
    set +e
    log "🏗 Building jar for ${component}"
    docker run -i --rm -e KAFKA_CLIENT_TAG=$KAFKA_CLIENT_TAG -e TAG=$TAG_BASE -v "${DIR}/${component}":/usr/src/mymaven -v "$HOME/.m2":/root/.m2 -v "${DIR}/${component}/target:/usr/src/mymaven/target" -w /usr/src/mymaven maven:3.6.1-jdk-11 mvn -Dkafka.tag=$TAG -Dkafka.client.tag=$KAFKA_CLIENT_TAG package > /tmp/result.log 2>&1
    if [ $? != 0 ]
    then
        logerror "ERROR: failed to build java component "
        tail -500 /tmp/result.log
        exit 1
    fi
    set -e
done

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.repro-99124-kafka-connect-hdfs-produces-4-bytes-parquet-file-on-restart.yml"

sleep 10

# Note in this simple example, if you get into an issue with permissions at the local HDFS level, it may be easiest to unlock the permissions unless you want to debug that more.
docker exec namenode bash -c "/opt/hadoop-2.7.4/bin/hdfs dfs -chmod 777  /"

for((i=0;i<$NB_CONNECTORS;i++)); do
     LOG_DIR="/logs$i"
     TOPIC="customer_avro$i"
     TOPICS_DIR="/topics$i"
     log "Creating HDFS Sink connector"
     curl -X PUT \
          -H "Content-Type: application/json" \
          --data '{
                    "connector.class":"io.confluent.connect.hdfs.HdfsSinkConnector",
                    "tasks.max":"'"$NB_TASK_PER_CONNECTOR"'",
                    "topics": "customer_avro0,customer_avro1,customer_avro2",
                    "store.url":"hdfs://namenode:8020",
                    "flush.size":"20000",
                    "hadoop.conf.dir":"/etc/hadoop/",
                    "rotate.interval.ms": "300000",
                    "partition.duration.ms": "3600000",
                    "logs.dir": "'"$LOG_DIR"'",
                    "confluent.license": "",
                    "confluent.topic.bootstrap.servers": "broker:9092",
                    "confluent.topic.replication.factor": "1",
                    "key.converter":"io.confluent.connect.avro.AvroConverter",
                    "key.converter.schema.registry.url":"http://schema-registry:8081",
                    "value.converter":"io.confluent.connect.avro.AvroConverter",
                    "value.converter.schema.registry.url":"http://schema-registry:8081",
                    "schema.compatibility":"BACKWARD",

                    "format.class": "io.confluent.connect.hdfs.parquet.ParquetFormat",
                    "path.format": "YYYY/MM/dd/HH",
                    "filename.offset.zero.pad.width": "1",
                    "locale": "en-US",
                    "max.retries": "5",
                    "partitioner.class": "io.confluent.connect.storage.partitioner.TimeBasedPartitioner",
                    "timezone": "UTC",
                    "transforms.InsertField.offset.field": "KafkaOffset",
                    "transforms.InsertField.partition.field": "KafkaPartition",
                    "transforms.InsertField.topic.field": "KafkaTopic",
                    "transforms.InsertField.type": "org.apache.kafka.connect.transforms.InsertField$Value",
                    "transforms": "InsertField"

               }' \
          http://localhost:8083/connectors/hdfs-sink$i/config | jq .

          log "✨ Run the avro java producer which produces to topic $TOPIC"
          docker exec -d producer-repro-99124 bash -c "export TOPIC=$TOPIC;java ${JAVA_OPTS} -jar producer-1.0.0-jar-with-dependencies.jar"
done


sleep 30

wait_for_repro

exit 0

log "setting quota: https://github.com/confluentinc/kafka-connect-hdfs/issues/453#issuecomment-538091951"
docker exec namenode bash -c "/opt/hadoop-2.7.4/bin/hdfs dfsadmin -setSpaceQuota 805312 /topics//+tmp"

sleep 30

docker exec namenode bash -c "/opt/hadoop-2.7.4/bin/hdfs dfs -ls /topics/+tmp/customer_avro/partition=0"
# -rw-r--r--   3 appuser supergroup          0 2022-04-01 13:56 /topics/+tmp/customer_avro/partition=0/3880709b-84a3-44b2-9324-651fa8fd92f8_tmp.parquet


log "remove quota"
docker exec namenode bash -c "/opt/hadoop-2.7.4/bin/hdfs dfsadmin -clrSpaceQuota /topics//+tmp"




# [2022-04-01 13:56:21,194] ERROR [hdfs-sink|task-0] Failed to close temporary file for partition partition=0. The connector will attempt to rewrite the temporary file. (io.confluent.connect.hdfs.TopicPartitionWriter:776)
# [2022-04-01 13:56:21,214] ERROR [hdfs-sink|task-0] Exception on topic partition customer_avro-0:  (io.confluent.connect.hdfs.TopicPartitionWriter:412)
# org.apache.kafka.connect.errors.ConnectException: java.io.IOException: can not write OffsetIndex(page_locations:[PageLocation(offset:4, compressed_page_size:59234, first_row_index:0), PageLocation(offset:59238, compressed_page_size:59234, first_row_index:7400), PageLocation(offset:118472, compressed_page_size:59234, first_row_index:14800), PageLocation(offset:177706, compressed_page_size:59233, first_row_index:22200), PageLocation(offset:236939, compressed_page_size:59234, first_row_index:29600), PageLocation(offset:296173, compressed_page_size:20450, first_row_index:37000)])
#         at io.confluent.connect.hdfs.parquet.ParquetRecordWriterProvider$1.close(ParquetRecordWriterProvider.java:112)
#         at io.confluent.connect.hdfs.TopicPartitionWriter.closeTempFile(TopicPartitionWriter.java:763)
#         at io.confluent.connect.hdfs.TopicPartitionWriter.closeTempFile(TopicPartitionWriter.java:772)
#         at io.confluent.connect.hdfs.TopicPartitionWriter.write(TopicPartitionWriter.java:395)
#         at io.confluent.connect.hdfs.DataWriter.write(DataWriter.java:376)
#         at io.confluent.connect.hdfs.HdfsSinkTask.put(HdfsSinkTask.java:133)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.deliverMessages(WorkerSinkTask.java:604)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.poll(WorkerSinkTask.java:334)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.iteration(WorkerSinkTask.java:235)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.execute(WorkerSinkTask.java:204)
#         at org.apache.kafka.connect.runtime.WorkerTask.doRun(WorkerTask.java:199)
#         at org.apache.kafka.connect.runtime.WorkerTask.run(WorkerTask.java:254)
#         at java.base/java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:515)
#         at java.base/java.util.concurrent.FutureTask.run(FutureTask.java:264)
#         at java.base/java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1128)
#         at java.base/java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:628)
#         at java.base/java.lang.Thread.run(Thread.java:829)
# Caused by: java.io.IOException: can not write OffsetIndex(page_locations:[PageLocation(offset:4, compressed_page_size:59234, first_row_index:0), PageLocation(offset:59238, compressed_page_size:59234, first_row_index:7400), PageLocation(offset:118472, compressed_page_size:59234, first_row_index:14800), PageLocation(offset:177706, compressed_page_size:59233, first_row_index:22200), PageLocation(offset:236939, compressed_page_size:59234, first_row_index:29600), PageLocation(offset:296173, compressed_page_size:20450, first_row_index:37000)])
#         at org.apache.parquet.format.Util.write(Util.java:233)
#         at org.apache.parquet.format.Util.writeOffsetIndex(Util.java:66)
#         at org.apache.parquet.hadoop.ParquetFileWriter.serializeOffsetIndexes(ParquetFileWriter.java:905)
#         at org.apache.parquet.hadoop.ParquetFileWriter.end(ParquetFileWriter.java:861)
#         at org.apache.parquet.hadoop.InternalParquetRecordWriter.close(InternalParquetRecordWriter.java:122)
#         at org.apache.parquet.hadoop.ParquetWriter.close(ParquetWriter.java:310)
#         at io.confluent.connect.hdfs.parquet.ParquetRecordWriterProvider$1.close(ParquetRecordWriterProvider.java:110)
#         ... 16 more
# Caused by: shaded.parquet.org.apache.thrift.transport.TTransportException: org.apache.hadoop.hdfs.protocol.DSQuotaExceededException: The DiskSpace quota of /topics/+tmp is exceeded: quota = 805312 B = 786.44 KB but diskspace consumed = 805306368 B = 768 MB
#         at org.apache.hadoop.hdfs.server.namenode.DirectoryWithQuotaFeature.verifyStoragespaceQuota(DirectoryWithQuotaFeature.java:212)
#         at org.apache.hadoop.hdfs.server.namenode.DirectoryWithQuotaFeature.verifyQuota(DirectoryWithQuotaFeature.java:239)
#         at org.apache.hadoop.hdfs.server.namenode.FSDirectory.verifyQuota(FSDirectory.java:911)
#         at org.apache.hadoop.hdfs.server.namenode.FSDirectory.updateCount(FSDirectory.java:766)
#         at org.apache.hadoop.hdfs.server.namenode.FSDirectory.updateCount(FSDirectory.java:725)
#         at org.apache.hadoop.hdfs.server.namenode.FSDirectory.addBlock(FSDirectory.java:497)
#         at org.apache.hadoop.hdfs.server.namenode.FSNamesystem.saveAllocatedBlock(FSNamesystem.java:3532)
#         at org.apache.hadoop.hdfs.server.namenode.FSNamesystem.storeAllocatedBlock(FSNamesystem.java:3172)
#         at org.apache.hadoop.hdfs.server.namenode.FSNamesystem.getAdditionalBlock(FSNamesystem.java:3052)
#         at org.apache.hadoop.hdfs.server.namenode.NameNodeRpcServer.addBlock(NameNodeRpcServer.java:725)
#         at org.apache.hadoop.hdfs.protocolPB.ClientNamenodeProtocolServerSideTranslatorPB.addBlock(ClientNamenodeProtocolServerSideTranslatorPB.java:493)
#         at org.apache.hadoop.hdfs.protocol.proto.ClientNamenodeProtocolProtos$ClientNamenodeProtocol$2.callBlockingMethod(ClientNamenodeProtocolProtos.java)
#         at org.apache.hadoop.ipc.ProtobufRpcEngine$Server$ProtoBufRpcInvoker.call(ProtobufRpcEngine.java:616)
#         at org.apache.hadoop.ipc.RPC$Server.call(RPC.java:982)
#         at org.apache.hadoop.ipc.Server$Handler$1.run(Server.java:2217)
#         at org.apache.hadoop.ipc.Server$Handler$1.run(Server.java:2213)
#         at java.security.AccessController.doPrivileged(Native Method)
#         at javax.security.auth.Subject.doAs(Subject.java:422)
#         at org.apache.hadoop.security.UserGroupInformation.doAs(UserGroupInformation.java:1746)
#         at org.apache.hadoop.ipc.Server$Handler.run(Server.java:2213)

#         at shaded.parquet.org.apache.thrift.transport.TIOStreamTransport.write(TIOStreamTransport.java:147)
#         at shaded.parquet.org.apache.thrift.protocol.TCompactProtocol.writeByteDirect(TCompactProtocol.java:486)
#         at shaded.parquet.org.apache.thrift.protocol.TCompactProtocol.writeByteDirect(TCompactProtocol.java:493)
#         at shaded.parquet.org.apache.thrift.protocol.TCompactProtocol.writeFieldBeginInternal(TCompactProtocol.java:260)
#         at shaded.parquet.org.apache.thrift.protocol.TCompactProtocol.writeFieldBegin(TCompactProtocol.java:242)
#         at org.apache.parquet.format.InterningProtocol.writeFieldBegin(InterningProtocol.java:71)
#         at org.apache.parquet.format.OffsetIndex$OffsetIndexStandardScheme.write(OffsetIndex.java:382)
#         at org.apache.parquet.format.OffsetIndex$OffsetIndexStandardScheme.write(OffsetIndex.java:335)
#         at org.apache.parquet.format.OffsetIndex.write(OffsetIndex.java:286)
#         at org.apache.parquet.format.Util.write(Util.java:231)
#         ... 22 more
# Caused by: org.apache.hadoop.hdfs.protocol.DSQuotaExceededException: The DiskSpace quota of /topics/+tmp is exceeded: quota = 805312 B = 786.44 KB but diskspace consumed = 805306368 B = 768 MB
#         at org.apache.hadoop.hdfs.server.namenode.DirectoryWithQuotaFeature.verifyStoragespaceQuota(DirectoryWithQuotaFeature.java:212)
#         at org.apache.hadoop.hdfs.server.namenode.DirectoryWithQuotaFeature.verifyQuota(DirectoryWithQuotaFeature.java:239)
#         at org.apache.hadoop.hdfs.server.namenode.FSDirectory.verifyQuota(FSDirectory.java:911)
#         at org.apache.hadoop.hdfs.server.namenode.FSDirectory.updateCount(FSDirectory.java:766)
#         at org.apache.hadoop.hdfs.server.namenode.FSDirectory.updateCount(FSDirectory.java:725)
#         at org.apache.hadoop.hdfs.server.namenode.FSDirectory.addBlock(FSDirectory.java:497)
#         at org.apache.hadoop.hdfs.server.namenode.FSNamesystem.saveAllocatedBlock(FSNamesystem.java:3532)
#         at org.apache.hadoop.hdfs.server.namenode.FSNamesystem.storeAllocatedBlock(FSNamesystem.java:3172)
#         at org.apache.hadoop.hdfs.server.namenode.FSNamesystem.getAdditionalBlock(FSNamesystem.java:3052)
#         at org.apache.hadoop.hdfs.server.namenode.NameNodeRpcServer.addBlock(NameNodeRpcServer.java:725)
#         at org.apache.hadoop.hdfs.protocolPB.ClientNamenodeProtocolServerSideTranslatorPB.addBlock(ClientNamenodeProtocolServerSideTranslatorPB.java:493)
#         at org.apache.hadoop.hdfs.protocol.proto.ClientNamenodeProtocolProtos$ClientNamenodeProtocol$2.callBlockingMethod(ClientNamenodeProtocolProtos.java)
#         at org.apache.hadoop.ipc.ProtobufRpcEngine$Server$ProtoBufRpcInvoker.call(ProtobufRpcEngine.java:616)
#         at org.apache.hadoop.ipc.RPC$Server.call(RPC.java:982)
#         at org.apache.hadoop.ipc.Server$Handler$1.run(Server.java:2217)
#         at org.apache.hadoop.ipc.Server$Handler$1.run(Server.java:2213)
#         at java.security.AccessController.doPrivileged(Native Method)
#         at javax.security.auth.Subject.doAs(Subject.java:422)
#         at org.apache.hadoop.security.UserGroupInformation.doAs(UserGroupInformation.java:1746)
#         at org.apache.hadoop.ipc.Server$Handler.run(Server.java:2213)

#         at java.base/jdk.internal.reflect.NativeConstructorAccessorImpl.newInstance0(Native Method)
#         at java.base/jdk.internal.reflect.NativeConstructorAccessorImpl.newInstance(NativeConstructorAccessorImpl.java:62)
#         at java.base/jdk.internal.reflect.DelegatingConstructorAccessorImpl.newInstance(DelegatingConstructorAccessorImpl.java:45)
#         at java.base/java.lang.reflect.Constructor.newInstance(Constructor.java:490)
#         at org.apache.hadoop.ipc.RemoteException.instantiateException(RemoteException.java:121)
#         at org.apache.hadoop.ipc.RemoteException.unwrapRemoteException(RemoteException.java:88)
#         at org.apache.hadoop.hdfs.DataStreamer.locateFollowingBlock(DataStreamer.java:1850)
#         at org.apache.hadoop.hdfs.DataStreamer.nextBlockOutputStream(DataStreamer.java:1645)
#         at org.apache.hadoop.hdfs.DataStreamer.run(DataStreamer.java:710)
# Caused by: org.apache.hadoop.ipc.RemoteException(org.apache.hadoop.hdfs.protocol.DSQuotaExceededException): The DiskSpace quota of /topics/+tmp is exceeded: quota = 805312 B = 786.44 KB but diskspace consumed = 805306368 B = 768 MB
#         at org.apache.hadoop.hdfs.server.namenode.DirectoryWithQuotaFeature.verifyStoragespaceQuota(DirectoryWithQuotaFeature.java:212)
#         at org.apache.hadoop.hdfs.server.namenode.DirectoryWithQuotaFeature.verifyQuota(DirectoryWithQuotaFeature.java:239)
#         at org.apache.hadoop.hdfs.server.namenode.FSDirectory.verifyQuota(FSDirectory.java:911)
#         at org.apache.hadoop.hdfs.server.namenode.FSDirectory.updateCount(FSDirectory.java:766)
#         at org.apache.hadoop.hdfs.server.namenode.FSDirectory.updateCount(FSDirectory.java:725)
#         at org.apache.hadoop.hdfs.server.namenode.FSDirectory.addBlock(FSDirectory.java:497)
#         at org.apache.hadoop.hdfs.server.namenode.FSNamesystem.saveAllocatedBlock(FSNamesystem.java:3532)
#         at org.apache.hadoop.hdfs.server.namenode.FSNamesystem.storeAllocatedBlock(FSNamesystem.java:3172)
#         at org.apache.hadoop.hdfs.server.namenode.FSNamesystem.getAdditionalBlock(FSNamesystem.java:3052)
#         at org.apache.hadoop.hdfs.server.namenode.NameNodeRpcServer.addBlock(NameNodeRpcServer.java:725)
#         at org.apache.hadoop.hdfs.protocolPB.ClientNamenodeProtocolServerSideTranslatorPB.addBlock(ClientNamenodeProtocolServerSideTranslatorPB.java:493)
#         at org.apache.hadoop.hdfs.protocol.proto.ClientNamenodeProtocolProtos$ClientNamenodeProtocol$2.callBlockingMethod(ClientNamenodeProtocolProtos.java)
#         at org.apache.hadoop.ipc.ProtobufRpcEngine$Server$ProtoBufRpcInvoker.call(ProtobufRpcEngine.java:616)
#         at org.apache.hadoop.ipc.RPC$Server.call(RPC.java:982)
#         at org.apache.hadoop.ipc.Server$Handler$1.run(Server.java:2217)
#         at org.apache.hadoop.ipc.Server$Handler$1.run(Server.java:2213)
#         at java.security.AccessController.doPrivileged(Native Method)
#         at javax.security.auth.Subject.doAs(Subject.java:422)
#         at org.apache.hadoop.security.UserGroupInformation.doAs(UserGroupInformation.java:1746)
#         at org.apache.hadoop.ipc.Server$Handler.run(Server.java:2213)

#         at org.apache.hadoop.ipc.Client.getRpcResponse(Client.java:1549)
#         at org.apache.hadoop.ipc.Client.call(Client.java:1495)
#         at org.apache.hadoop.ipc.Client.call(Client.java:1394)
#         at org.apache.hadoop.ipc.ProtobufRpcEngine$Invoker.invoke(ProtobufRpcEngine.java:232)
#         at org.apache.hadoop.ipc.ProtobufRpcEngine$Invoker.invoke(ProtobufRpcEngine.java:118)
#         at com.sun.proxy.$Proxy56.addBlock(Unknown Source)
#         at org.apache.hadoop.hdfs.protocolPB.ClientNamenodeProtocolTranslatorPB.addBlock(ClientNamenodeProtocolTranslatorPB.java:448)
#         at java.base/jdk.internal.reflect.NativeMethodAccessorImpl.invoke0(Native Method)
#         at java.base/jdk.internal.reflect.NativeMethodAccessorImpl.invoke(NativeMethodAccessorImpl.java:62)
#         at java.base/jdk.internal.reflect.DelegatingMethodAccessorImpl.invoke(DelegatingMethodAccessorImpl.java:43)
#         at java.base/java.lang.reflect.Method.invoke(Method.java:566)
#         at org.apache.hadoop.io.retry.RetryInvocationHandler.invokeMethod(RetryInvocationHandler.java:422)
#         at org.apache.hadoop.io.retry.RetryInvocationHandler$Call.invokeMethod(RetryInvocationHandler.java:165)
#         at org.apache.hadoop.io.retry.RetryInvocationHandler$Call.invoke(RetryInvocationHandler.java:157)
#         at org.apache.hadoop.io.retry.RetryInvocationHandler$Call.invokeOnce(RetryInvocationHandler.java:95)
#         at org.apache.hadoop.io.retry.RetryInvocationHandler.invoke(RetryInvocationHandler.java:359)
#         at com.sun.proxy.$Proxy57.addBlock(Unknown Source)
#         at org.apache.hadoop.hdfs.DataStreamer.locateFollowingBlock(DataStreamer.java:1846)
#         ... 2 more


log "Restart failed task"
curl --request POST \
  --url http://localhost:8083/connectors/hdfs-sink/tasks/0/restart


docker restart connect


# I saw:

# [2022-04-04 12:06:46,253] INFO [hdfs-sink|task-0] Stopping task hdfs-sink-0 (org.apache.kafka.connect.runtime.Worker:925)
# [2022-04-04 12:06:46,253] INFO [hdfs-sink|worker] Stopping connector hdfs-sink (org.apache.kafka.connect.runtime.Worker:411)
# [2022-04-04 12:06:46,253] INFO [hdfs-sink|worker] Scheduled shutdown for WorkerConnector{id=hdfs-sink} (org.apache.kafka.connect.runtime.WorkerConnector:249)
# [2022-04-04 12:06:46,254] INFO [hdfs-sink|worker] Completed shutdown for WorkerConnector{id=hdfs-sink} (org.apache.kafka.connect.runtime.WorkerConnector:269)
# [2022-04-04 12:06:46,284] ERROR [hdfs-sink|task-0] Error closing temp file hdfs://namenode:8020/topics//+tmp/customer_avro/2022/04/04/12/3df7c80c-5cbd-42b3-9236-26f78d12ae5b_tmp.parquet for customer_avro-0 2022/04/04/12 when closing TopicPartitionWriter: (io.confluent.connect.hdfs.TopicPartitionWriter:477)
# org.apache.kafka.connect.errors.ConnectException: java.nio.channels.ClosedChannelException
#         at io.confluent.connect.hdfs.parquet.ParquetRecordWriterProvider$1.close(ParquetRecordWriterProvider.java:112)
#         at io.confluent.connect.hdfs.TopicPartitionWriter.closeTempFile(TopicPartitionWriter.java:763)
#         at io.confluent.connect.hdfs.TopicPartitionWriter.close(TopicPartitionWriter.java:475)
#         at io.confluent.connect.hdfs.DataWriter.close(DataWriter.java:469)
#         at io.confluent.connect.hdfs.HdfsSinkTask.close(HdfsSinkTask.java:169)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.commitOffsets(WorkerSinkTask.java:422)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.closePartitions(WorkerSinkTask.java:673)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.closeAllPartitions(WorkerSinkTask.java:668)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.execute(WorkerSinkTask.java:205)
#         at org.apache.kafka.connect.runtime.WorkerTask.doRun(WorkerTask.java:199)
#         at org.apache.kafka.connect.runtime.WorkerTask.run(WorkerTask.java:254)
#         at java.base/java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:515)
#         at java.base/java.util.concurrent.FutureTask.run(FutureTask.java:264)
#         at java.base/java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1128)
#         at java.base/java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:628)
#         at java.base/java.lang.Thread.run(Thread.java:829)
# Caused by: java.nio.channels.ClosedChannelException
#         at org.apache.hadoop.hdfs.DataStreamer$LastExceptionInStreamer.throwException4Close(DataStreamer.java:324)
#         at org.apache.hadoop.hdfs.DFSOutputStream.checkClosed(DFSOutputStream.java:151)
#         at org.apache.hadoop.fs.FSOutputSummer.write(FSOutputSummer.java:105)
#         at org.apache.hadoop.fs.FSDataOutputStream$PositionCache.write(FSDataOutputStream.java:58)
#         at java.base/java.io.DataOutputStream.write(DataOutputStream.java:107)
#         at java.base/java.io.FilterOutputStream.write(FilterOutputStream.java:108)
#         at org.apache.parquet.hadoop.util.HadoopPositionOutputStream.write(HadoopPositionOutputStream.java:45)
#         at org.apache.parquet.bytes.ConcatenatingByteArrayCollector.writeAllTo(ConcatenatingByteArrayCollector.java:46)
#         at org.apache.parquet.hadoop.ParquetFileWriter.writeColumnChunk(ParquetFileWriter.java:620)
#         at org.apache.parquet.hadoop.ColumnChunkPageWriteStore$ColumnChunkPageWriter.writeToFileWriter(ColumnChunkPageWriteStore.java:241)
#         at org.apache.parquet.hadoop.ColumnChunkPageWriteStore.flushToFileWriter(ColumnChunkPageWriteStore.java:319)
#         at org.apache.parquet.hadoop.InternalParquetRecordWriter.flushRowGroupToStore(InternalParquetRecordWriter.java:173)
#         at org.apache.parquet.hadoop.InternalParquetRecordWriter.close(InternalParquetRecordWriter.java:114)
#         at org.apache.parquet.hadoop.ParquetWriter.close(ParquetWriter.java:310)
#         at io.confluent.connect.hdfs.parquet.ParquetRecordWriterProvider$1.close(ParquetRecordWriterProvider.java:110)
#         ... 15 more
# [2022-04-04 12:06:46,286] ERROR [hdfs-sink|task-0] Error deleting temp file hdfs://namenode:8020/topics//+tmp/customer_avro/2022/04/04/12/3df7c80c-5cbd-42b3-9236-26f78d12ae5b_tmp.parquet for customer_avro-0 2022/04/04/12 when closing TopicPartitionWriter: (io.confluent.connect.hdfs.TopicPartitionWriter:489)
# org.apache.kafka.connect.errors.ConnectException: java.io.IOException: Filesystem closed
#         at io.confluent.connect.hdfs.storage.HdfsStorage.delete(HdfsStorage.java:165)
#         at io.confluent.connect.hdfs.TopicPartitionWriter.deleteTempFile(TopicPartitionWriter.java:900)
#         at io.confluent.connect.hdfs.TopicPartitionWriter.close(TopicPartitionWriter.java:487)
#         at io.confluent.connect.hdfs.DataWriter.close(DataWriter.java:469)
#         at io.confluent.connect.hdfs.HdfsSinkTask.close(HdfsSinkTask.java:169)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.commitOffsets(WorkerSinkTask.java:422)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.closePartitions(WorkerSinkTask.java:673)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.closeAllPartitions(WorkerSinkTask.java:668)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.execute(WorkerSinkTask.java:205)
#         at org.apache.kafka.connect.runtime.WorkerTask.doRun(WorkerTask.java:199)
#         at org.apache.kafka.connect.runtime.WorkerTask.run(WorkerTask.java:254)
#         at java.base/java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:515)
#         at java.base/java.util.concurrent.FutureTask.run(FutureTask.java:264)
#         at java.base/java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1128)
#         at java.base/java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:628)
#         at java.base/java.lang.Thread.run(Thread.java:829)
# Caused by: java.io.IOException: Filesystem closed
#         at org.apache.hadoop.hdfs.DFSClient.checkOpen(DFSClient.java:484)
#         at org.apache.hadoop.hdfs.DFSClient.delete(DFSClient.java:1612)
#         at org.apache.hadoop.hdfs.DistributedFileSystem$19.doCall(DistributedFileSystem.java:882)
#         at org.apache.hadoop.hdfs.DistributedFileSystem$19.doCall(DistributedFileSystem.java:879)
#         at org.apache.hadoop.fs.FileSystemLinkResolver.resolve(FileSystemLinkResolver.java:81)
#         at org.apache.hadoop.hdfs.DistributedFileSystem.delete(DistributedFileSystem.java:879)
#         at io.confluent.connect.hdfs.storage.HdfsStorage.delete(HdfsStorage.java:163)
#         ... 15 more
# [2022-04-04 12:06:46,295] INFO [hdfs-sink|task-0] Stopping HDFS Sink Task hdfs-sink-0 (io.confluent.connect.hdfs.HdfsSinkTask:175)
