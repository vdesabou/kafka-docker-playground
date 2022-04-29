#!/bin/bash
set -e

# https://steveloughran.gitbooks.io/kerberos_and_hadoop/content/sections/errors.html
# https://stackoverflow.com/questions/34616676/should-i-call-ugi-checktgtandreloginfromkeytab-before-every-action-on-hadoop
# https://stackoverflow.com/questions/44362086/is-kinit-required-while-accessing-a-kerberized-service-through-java-code
# https://stackoverflow.com/questions/38555244/how-do-you-set-the-kerberos-ticket-lifetime-from-java
# https://serverfault.com/a/133631
# https://community.cloudera.com/t5/Support-Questions/Error-on-kerberos-ticket-renewer-role-startup/td-p/31187

export ENABLE_CONNECT_NODES=1
NB_CONNECTORS=110
NB_TASK_PER_CONNECTOR=8
CONNECT_KERBEROS_TICKET_LIFETIME=5

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

function wait_for_gss_exception () {
     MAX_WAIT=43200
     CUR_WAIT=0
     log "⌛ Waiting up to $MAX_WAIT seconds for GSS exception to happen (it can take several hours)"
     docker container logs connect > /tmp/out.txt 2>&1
     docker container logs connect2 >> /tmp/out.txt 2>&1
     docker container logs connect3 >> /tmp/out.txt 2>&1
     while ! grep "Failed to find any Kerberos tgt" /tmp/out.txt > /dev/null;
     do
          sleep 10
          docker container logs connect > /tmp/out.txt 2>&1
          docker container logs connect2 >> /tmp/out.txt 2>&1
          docker container logs connect3 >> /tmp/out.txt 2>&1
          CUR_WAIT=$(( CUR_WAIT+10 ))
          if [[ "$CUR_WAIT" -gt "$MAX_WAIT" ]]; then
               echo -e "\nERROR: The logs in all connect containers do not show 'Failed to find any Kerberos tgt' after $MAX_WAIT seconds. Please troubleshoot with 'docker container ps' and 'docker container logs'.\n"
               exit 1
          fi

          for((i=0;i<$NB_CONNECTORS;i++)); do
               # send requests
               seq -f "{\"f1\": \"value%g\"}" 100 | docker exec -i connect kafka-avro-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic test_hdfs$i --property value.schema='{"type":"record","name":"myrecord","fields":[{"name":"f1","type":"string"}]}'
          done
     done
     log "The problem has been reproduced !"
}


${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.repro-ha-gss-exception-99030.yml"

log "Java version used on connect:"
docker exec -i connect java -version

log "Wait 120 seconds while hadoop is installing"
sleep 120

# curl --request PUT \
#   --url http://localhost:8083/admin/loggers/io.confluent.connect.hdfs \
#   --header 'Accept: application/json' \
#   --header 'Content-Type: application/json' \
#   --data '{
# 	"level": "DEBUG"
# }'

# curl --request PUT \
#   --url http://localhost:8083/admin/loggers/org.apache.hadoop.security \
#   --header 'Accept: application/json' \
#   --header 'Content-Type: application/json' \
#   --data '{
# 	"level": "DEBUG"
# }'

# curl --request PUT \
#   --url http://localhost:18083/admin/loggers/io.confluent.connect.hdfs \
#   --header 'Accept: application/json' \
#   --header 'Content-Type: application/json' \
#   --data '{
# 	"level": "DEBUG"
# }'

# curl --request PUT \
#   --url http://localhost:18083/admin/loggers/org.apache.hadoop.security \
#   --header 'Accept: application/json' \
#   --header 'Content-Type: application/json' \
#   --data '{
# 	"level": "DEBUG"
# }'

# curl --request PUT \
#   --url http://localhost:28083/admin/loggers/io.confluent.connect.hdfs \
#   --header 'Accept: application/json' \
#   --header 'Content-Type: application/json' \
#   --data '{
# 	"level": "DEBUG"
# }'

# curl --request PUT \
#   --url http://localhost:28083/admin/loggers/org.apache.hadoop.security \
#   --header 'Accept: application/json' \
#   --header 'Content-Type: application/json' \
#   --data '{
# 	"level": "DEBUG"
# }'


# Note in this simple example, if you get into an issue with permissions at the local HDFS level, it may be easiest to unlock the permissions unless you want to debug that more.
docker exec namenode1 bash -c "kinit -kt /opt/hadoop/etc/hadoop/nn.keytab nn/namenode1.kerberos-demo.local && /opt/hadoop/bin/hdfs dfs -chmod 777  /"

log "Add connect kerberos principal"
docker exec -i krb5 kadmin.local << EOF
addprinc -randkey connect@EXAMPLE.COM
modprinc -maxrenewlife 604800 +allow_renewable connect@EXAMPLE.COM
modprinc -maxrenewlife 604800 +allow_renewable krbtgt/EXAMPLE.COM
modprinc -maxrenewlife 604800 +allow_renewable krbtgt/EXAMPLE.COM@EXAMPLE.COM
modprinc -maxlife $CONNECT_KERBEROS_TICKET_LIFETIME connect@EXAMPLE.COM
ktadd -k /connect.keytab connect@EXAMPLE.COM
getprinc connect@EXAMPLE.COM
EOF

log "Copy connect.keytab to connect container"
docker cp krb5:/connect.keytab .
docker cp connect.keytab connect:/tmp/connect.keytab
if [[ "$TAG" == *ubi8 ]] || version_gt $TAG_BASE "5.9.0"
then
     docker exec -u 0 connect chown appuser:appuser /tmp/connect.keytab
fi

log "Copy connect.keytab to connect2 container"
docker cp connect.keytab connect2:/tmp/connect.keytab
if [[ "$TAG" == *ubi8 ]] || version_gt $TAG_BASE "5.9.0"
then
     docker exec -u 0 connect2 chown appuser:appuser /tmp/connect.keytab
fi

log "Copy connect.keytab to connect3 container"
docker cp connect.keytab connect3:/tmp/connect.keytab
if [[ "$TAG" == *ubi8 ]] || version_gt $TAG_BASE "5.9.0"
then
     docker exec -u 0 connect3 chown appuser:appuser /tmp/connect.keytab
fi

for((i=0;i<$NB_CONNECTORS;i++)); do
     LOG_DIR="/logs$i"
     TOPIC="test_hdfs$i"
     log "Creating HDFS Sink connector $i"
     curl -X PUT \
          -H "Content-Type: application/json" \
          --data '{
                    "connector.class":"io.confluent.connect.hdfs3.Hdfs3SinkConnector",
                    "tasks.max":"'"$NB_TASK_PER_CONNECTOR"'",
                    "topics": "'"$TOPIC"'",
                    "store.url":"hdfs://sh",
                    "flush.size":"3",
                    "hadoop.conf.dir":"/opt/hadoop/etc/hadoop/",
                    "partitioner.class":"io.confluent.connect.storage.partitioner.FieldPartitioner",
                    "partition.field.name":"f1",
                    "rotate.interval.ms":"120000",
                    "logs.dir": "'"$LOG_DIR"'",
                    "hdfs.authentication.kerberos": "true",
                    "kerberos.ticket.renew.period.ms": "1000",
                    "connect.hdfs.principal": "connect@EXAMPLE.COM",
                    "connect.hdfs.keytab": "/tmp/connect.keytab",
                    "hdfs.namenode.principal": "nn/_HOST@EXAMPLE.COM",
                    "confluent.license": "",
                    "confluent.topic.bootstrap.servers": "broker:9092",
                    "confluent.topic.replication.factor": "1",
                    "key.converter":"org.apache.kafka.connect.storage.StringConverter",
                    "value.converter":"io.confluent.connect.avro.AvroConverter",
                    "value.converter.schema.registry.url":"http://schema-registry:8081",
                    "schema.compatibility":"BACKWARD"
               }' \
          http://localhost:8083/connectors/hdfs-sink-kerberos$i/config | jq .
done

wait_for_gss_exception

exit 0

log "Trigger a manual failover from nn1 to nn2"
docker exec namenode1 bash -c "kinit -kt /opt/hadoop/etc/hadoop/nn.keytab nn/namenode1.kerberos-demo.local && /opt/hadoop/bin/hdfs haadmin -failover -forceactive nn1 nn2"


# [2022-04-29 07:40:58,315] WARN [hdfs-sink-kerberos92|task-1] Exception encountered while connecting to the server  (org.apache.hadoop.ipc.Client:782)
# javax.security.sasl.SaslException: GSS initiate failed [Caused by GSSException: No valid credentials provided (Mechanism level: Failed to find any Kerberos tgt)]
#         at jdk.security.jgss/com.sun.security.sasl.gsskerb.GssKrb5Client.evaluateChallenge(GssKrb5Client.java:222)
#         at org.apache.hadoop.security.SaslRpcClient.saslConnect(SaslRpcClient.java:410)
#         at org.apache.hadoop.ipc.Client$Connection.setupSaslConnection(Client.java:623)
#         at org.apache.hadoop.ipc.Client$Connection.access$2300(Client.java:414)
#         at org.apache.hadoop.ipc.Client$Connection$2.run(Client.java:832)
#         at org.apache.hadoop.ipc.Client$Connection$2.run(Client.java:828)
#         at java.base/java.security.AccessController.doPrivileged(Native Method)
#         at java.base/javax.security.auth.Subject.doAs(Subject.java:423)
#         at org.apache.hadoop.security.UserGroupInformation.doAs(UserGroupInformation.java:1878)
#         at org.apache.hadoop.ipc.Client$Connection.setupIOstreams(Client.java:828)
#         at org.apache.hadoop.ipc.Client$Connection.access$3800(Client.java:414)
#         at org.apache.hadoop.ipc.Client.getConnection(Client.java:1647)
#         at org.apache.hadoop.ipc.Client.call(Client.java:1463)
#         at org.apache.hadoop.ipc.Client.call(Client.java:1416)
#         at org.apache.hadoop.ipc.ProtobufRpcEngine2$Invoker.invoke(ProtobufRpcEngine2.java:242)
#         at org.apache.hadoop.ipc.ProtobufRpcEngine2$Invoker.invoke(ProtobufRpcEngine2.java:129)
#         at com.sun.proxy.$Proxy51.getFileInfo(Unknown Source)
#         at org.apache.hadoop.hdfs.protocolPB.ClientNamenodeProtocolTranslatorPB.getFileInfo(ClientNamenodeProtocolTranslatorPB.java:965)
#         at jdk.internal.reflect.GeneratedMethodAccessor6.invoke(Unknown Source)
#         at java.base/jdk.internal.reflect.DelegatingMethodAccessorImpl.invoke(DelegatingMethodAccessorImpl.java:43)
#         at java.base/java.lang.reflect.Method.invoke(Method.java:566)
#         at org.apache.hadoop.io.retry.RetryInvocationHandler.invokeMethod(RetryInvocationHandler.java:422)
#         at org.apache.hadoop.io.retry.RetryInvocationHandler$Call.invokeMethod(RetryInvocationHandler.java:165)
#         at org.apache.hadoop.io.retry.RetryInvocationHandler$Call.invoke(RetryInvocationHandler.java:157)
#         at org.apache.hadoop.io.retry.RetryInvocationHandler$Call.invokeOnce(RetryInvocationHandler.java:95)
#         at org.apache.hadoop.io.retry.RetryInvocationHandler.invoke(RetryInvocationHandler.java:359)
#         at com.sun.proxy.$Proxy52.getFileInfo(Unknown Source)
#         at org.apache.hadoop.hdfs.DFSClient.getFileInfo(DFSClient.java:1731)
#         at org.apache.hadoop.hdfs.DistributedFileSystem$29.doCall(DistributedFileSystem.java:1752)
#         at org.apache.hadoop.hdfs.DistributedFileSystem$29.doCall(DistributedFileSystem.java:1749)
#         at org.apache.hadoop.fs.FileSystemLinkResolver.resolve(FileSystemLinkResolver.java:81)
#         at org.apache.hadoop.hdfs.DistributedFileSystem.getFileStatus(DistributedFileSystem.java:1764)
#         at org.apache.hadoop.fs.FileSystem.exists(FileSystem.java:1760)
#         at io.confluent.connect.hdfs3.storage.HdfsStorage.exists(HdfsStorage.java:139)
#         at io.confluent.connect.hdfs3.wal.FSWAL.apply(FSWAL.java:93)
#         at io.confluent.connect.hdfs3.TopicPartitionWriter.applyWAL(TopicPartitionWriter.java:634)
#         at io.confluent.connect.hdfs3.TopicPartitionWriter.recover(TopicPartitionWriter.java:252)
#         at io.confluent.connect.hdfs3.TopicPartitionWriter.write(TopicPartitionWriter.java:317)
#         at io.confluent.connect.hdfs3.DataWriter.write(DataWriter.java:357)
#         at io.confluent.connect.hdfs3.Hdfs3SinkTask.put(Hdfs3SinkTask.java:109)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.deliverMessages(WorkerSinkTask.java:584)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.poll(WorkerSinkTask.java:334)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.iteration(WorkerSinkTask.java:235)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.execute(WorkerSinkTask.java:204)
#         at org.apache.kafka.connect.runtime.WorkerTask.doRun(WorkerTask.java:200)
#         at org.apache.kafka.connect.runtime.WorkerTask.run(WorkerTask.java:255)
#         at java.base/java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:515)
#         at java.base/java.util.concurrent.FutureTask.run(FutureTask.java:264)
#         at java.base/java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1128)
#         at java.base/java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:628)
#         at java.base/java.lang.Thread.run(Thread.java:829)
# Caused by: GSSException: No valid credentials provided (Mechanism level: Failed to find any Kerberos tgt)
#         at java.security.jgss/sun.security.jgss.krb5.Krb5InitCredential.getInstance(Krb5InitCredential.java:162)
#         at java.security.jgss/sun.security.jgss.krb5.Krb5MechFactory.getCredentialElement(Krb5MechFactory.java:126)
#         at java.security.jgss/sun.security.jgss.krb5.Krb5MechFactory.getMechanismContext(Krb5MechFactory.java:193)
#         at java.security.jgss/sun.security.jgss.GSSManagerImpl.getMechanismContext(GSSManagerImpl.java:218)
#         at java.security.jgss/sun.security.jgss.GSSContextImpl.initSecContext(GSSContextImpl.java:230)
#         at java.security.jgss/sun.security.jgss.GSSContextImpl.initSecContext(GSSContextImpl.java:196)
#         at jdk.security.jgss/com.sun.security.sasl.gsskerb.GssKrb5Client.evaluateChallenge(GssKrb5Client.java:203)
#         ... 50 more
# [2022-04-29 07:40:58,326] ERROR [hdfs-sink-kerberos92|task-1] Recovery failed at state RECOVERY_PARTITION_PAUSED (io.confluent.connect.hdfs3.TopicPartitionWriter:273)
# org.apache.kafka.connect.errors.ConnectException: java.io.IOException: DestHost:destPort namenode1.kerberos-demo.local:9820 , LocalHost:localPort connect/172.20.0.15:0. Failed on local exception: java.io.IOException: javax.security.sasl.SaslException: GSS initiate failed [Caused by GSSException: No valid credentials provided (Mechanism level: Failed to find any Kerberos tgt)]
#         at io.confluent.connect.hdfs3.storage.HdfsStorage.exists(HdfsStorage.java:141)
#         at io.confluent.connect.hdfs3.wal.FSWAL.apply(FSWAL.java:93)
#         at io.confluent.connect.hdfs3.TopicPartitionWriter.applyWAL(TopicPartitionWriter.java:634)
#         at io.confluent.connect.hdfs3.TopicPartitionWriter.recover(TopicPartitionWriter.java:252)
#         at io.confluent.connect.hdfs3.TopicPartitionWriter.write(TopicPartitionWriter.java:317)
#         at io.confluent.connect.hdfs3.DataWriter.write(DataWriter.java:357)
#         at io.confluent.connect.hdfs3.Hdfs3SinkTask.put(Hdfs3SinkTask.java:109)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.deliverMessages(WorkerSinkTask.java:584)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.poll(WorkerSinkTask.java:334)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.iteration(WorkerSinkTask.java:235)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.execute(WorkerSinkTask.java:204)
#         at org.apache.kafka.connect.runtime.WorkerTask.doRun(WorkerTask.java:200)
#         at org.apache.kafka.connect.runtime.WorkerTask.run(WorkerTask.java:255)
#         at java.base/java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:515)
#         at java.base/java.util.concurrent.FutureTask.run(FutureTask.java:264)
#         at java.base/java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1128)
#         at java.base/java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:628)
#         at java.base/java.lang.Thread.run(Thread.java:829)