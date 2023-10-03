#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if version_gt $TAG_BASE "5.9.0"; then
     log "Hbase does not support JDK 11, see https://hbase.apache.org/book.html#java"
     # known_issue https://github.com/vdesabou/kafka-docker-playground/issues/907
     exit 107
fi

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.2.2.4.yml"


log "Sending messages to topic hbase-test"
playground topic produce -t hbase-test --nb-messages 3 --key "key1" << 'EOF'
value%g
EOF

log "Creating HBase sink connector"
playground connector create-or-update --connector hbase-sink << EOF
{
     "connector.class": "io.confluent.connect.hbase.HBaseSinkConnector",
     "tasks.max": "1",
     "key.converter":"org.apache.kafka.connect.storage.StringConverter",
     "value.converter":"org.apache.kafka.connect.storage.StringConverter",
     "confluent.topic.bootstrap.servers": "broker:9092",
     "confluent.topic.replication.factor":1,
     "hbase.zookeeper.quorum": "hbase",
     "hbase.zookeeper.property.clientPort": "2181",
     "auto.create.tables": "true",
     "auto.create.column.families": "false",
     "table.name.format": "example_table",
     "topics": "hbase-test"
}
EOF

# Since 2.0.2:
# [2022-12-19 15:56:44,478] ERROR [hbase-sink|task-0] WorkerSinkTask{id=hbase-sink-0} Task threw an uncaught and unrecoverable exception (org.apache.kafka.connect.runtime.WorkerTask:191)
# org.apache.kafka.connect.errors.ConnectException: Error establishing connection from configs:
#         at io.confluent.connect.hbase.client.HBaseConnectionProvider.checkAndReturnConnection(HBaseConnectionProvider.java:87)
#         at io.confluent.connect.hbase.client.HBaseConnectionProvider.newConnection(HBaseConnectionProvider.java:73)
#         at io.confluent.connect.hbase.client.HBaseConnectionProvider.newConnection(HBaseConnectionProvider.java:24)
#         at io.confluent.connect.bigtable.BaseBigtableSinkTask.setupConnection(BaseBigtableSinkTask.java:148)
#         at io.confluent.connect.bigtable.BaseBigtableSinkTask.start(BaseBigtableSinkTask.java:53)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.initializeAndStart(WorkerSinkTask.java:305)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.execute(WorkerSinkTask.java:196)
#         at org.apache.kafka.connect.runtime.WorkerTask.doRun(WorkerTask.java:189)
#         at org.apache.kafka.connect.runtime.WorkerTask.run(WorkerTask.java:239)
#         at java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:511)
#         at java.util.concurrent.FutureTask.run(FutureTask.java:266)
#         at java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1149)
#         at java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:624)
#         at java.lang.Thread.run(Thread.java:748)
# Caused by: java.io.IOException: java.lang.reflect.UndeclaredThrowableException
#         at org.apache.hadoop.hbase.client.ConnectionFactory.createConnection(ConnectionFactory.java:233)
#         at org.apache.hadoop.hbase.client.ConnectionFactory.createConnection(ConnectionFactory.java:130)
#         at org.apache.hadoop.hbase.client.HBaseAdmin.available(HBaseAdmin.java:2305)
#         at io.confluent.connect.hbase.client.HBaseConnectionProvider.checkAndReturnConnection(HBaseConnectionProvider.java:84)
#         ... 13 more
# Caused by: java.lang.reflect.UndeclaredThrowableException
#         at org.apache.hadoop.security.UserGroupInformation.doAs(UserGroupInformation.java:1911)
#         at org.apache.hadoop.hbase.security.User$SecureHadoopUser.runAs(User.java:326)
#         at org.apache.hadoop.hbase.client.ConnectionFactory.createConnection(ConnectionFactory.java:230)
#         ... 16 more
# Caused by: java.lang.reflect.InvocationTargetException
#         at sun.reflect.NativeConstructorAccessorImpl.newInstance0(Native Method)
#         at sun.reflect.NativeConstructorAccessorImpl.newInstance(NativeConstructorAccessorImpl.java:62)
#         at sun.reflect.DelegatingConstructorAccessorImpl.newInstance(DelegatingConstructorAccessorImpl.java:45)
#         at java.lang.reflect.Constructor.newInstance(Constructor.java:423)
#         at org.apache.hadoop.hbase.client.ConnectionFactory.lambda$createConnection$0(ConnectionFactory.java:231)
#         at java.security.AccessController.doPrivileged(Native Method)
#         at javax.security.auth.Subject.doAs(Subject.java:422)
#         at org.apache.hadoop.security.UserGroupInformation.doAs(UserGroupInformation.java:1893)
#         ... 18 more
# Caused by: java.lang.UnsupportedOperationException: Constructor threw an exception for org.apache.hadoop.hbase.client.ZKConnectionRegistry
#         at org.apache.hadoop.hbase.util.ReflectionUtils.instantiate(ReflectionUtils.java:61)
#         at org.apache.hadoop.hbase.util.ReflectionUtils.newInstance(ReflectionUtils.java:66)
#         at org.apache.hadoop.hbase.client.ConnectionRegistryFactory.getRegistry(ConnectionRegistryFactory.java:42)
#         at org.apache.hadoop.hbase.client.ConnectionImplementation.<init>(ConnectionImplementation.java:309)
#         ... 26 more
# Caused by: java.lang.reflect.InvocationTargetException
#         at sun.reflect.NativeConstructorAccessorImpl.newInstance0(Native Method)
#         at sun.reflect.NativeConstructorAccessorImpl.newInstance(NativeConstructorAccessorImpl.java:62)
#         at sun.reflect.DelegatingConstructorAccessorImpl.newInstance(DelegatingConstructorAccessorImpl.java:45)
#         at java.lang.reflect.Constructor.newInstance(Constructor.java:423)
#         at org.apache.hadoop.hbase.util.ReflectionUtils.instantiate(ReflectionUtils.java:54)
#         ... 29 more
# Caused by: java.lang.NoClassDefFoundError: org/apache/hadoop/hbase/shaded/org/apache/zookeeper/KeeperException$Code
#         at org.apache.hadoop.hbase.client.ZKConnectionRegistry.<init>(ZKConnectionRegistry.java:67)
#         ... 34 more
# Caused by: java.lang.ClassNotFoundException: org.apache.hadoop.hbase.shaded.org.apache.zookeeper.KeeperException$Code
#         at java.net.URLClassLoader.findClass(URLClassLoader.java:382)
#         at java.lang.ClassLoader.loadClass(ClassLoader.java:424)
#         at org.apache.kafka.connect.runtime.isolation.PluginClassLoader.loadClass(PluginClassLoader.java:104)
#         at java.lang.ClassLoader.loadClass(ClassLoader.java:357)
#         ... 35 more

sleep 10

log "Verify data is in HBase:"
docker exec -i hbase hbase shell > /tmp/result.log  2>&1 <<-EOF
scan 'example_table'
EOF
cat /tmp/result.log
grep "key1" /tmp/result.log | grep "value=value1"
grep "key2" /tmp/result.log | grep "value=value2"
grep "key3" /tmp/result.log | grep "value=value3"