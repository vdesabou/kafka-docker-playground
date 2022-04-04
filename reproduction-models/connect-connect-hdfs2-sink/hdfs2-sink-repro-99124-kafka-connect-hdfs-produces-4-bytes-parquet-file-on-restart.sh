#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if [ ! -f ${DIR}/hive-jdbc-3.1.2-standalone.jar ]
then
     log "Getting hive-jdbc-3.1.2-standalone.jar"
     wget https://repo1.maven.org/maven2/org/apache/hive/hive-jdbc/3.1.2/hive-jdbc-3.1.2-standalone.jar
fi


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

log "Creating HDFS Sink connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class":"io.confluent.connect.hdfs.HdfsSinkConnector",
               "tasks.max":"1",
               "topics":"customer_avro",
               "store.url":"hdfs://namenode:8020",
               "flush.size":"20000",
               "hadoop.conf.dir":"/etc/hadoop/",
               "rotate.interval.ms": "300000",
               "partition.duration.ms": "3600000",
               "logs.dir": "/tmp/",
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
     http://localhost:8083/connectors/hdfs-sink/config | jq .

log "✨ Run the avro java producer which produces to topic customer_avro"
docker exec -d producer-repro-99124 bash -c "java ${JAVA_OPTS} -jar producer-1.0.0-jar-with-dependencies.jar"

sleep 10

log "Listing content of /topics/customer_avro in HDFS"
docker exec namenode bash -c "/opt/hadoop-2.7.4/bin/hdfs dfs -ls /topics/customer_avro"


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

