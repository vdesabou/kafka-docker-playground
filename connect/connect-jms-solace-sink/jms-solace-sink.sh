#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"

if [ ! -f ${DIR}/sol-jms-10.6.3.jar ]
then
     echo "Downloading sol-jms-10.6.3.jar"
     wget http://central.maven.org/maven2/com/solacesystems/sol-jms/10.6.3/sol-jms-10.6.3.jar
fi

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"

echo "Wait 60 seconds for Solace to be up and running"
sleep 60
echo "Solace UI is accessible at http://127.0.0.1:8080 (admin/admin)"

echo "Sending messages to topic sink-messages"
seq 10 | docker exec -i broker kafka-console-producer --broker-list broker:9092 --topic sink-messages

echo "Creating Solace sink connector"
docker exec connect \
     curl -X POST \
     -H "Content-Type: application/json" \
     --data '{
               "name": "JMSSolaceSinkConnector9",
               "config": {
                    "connector.class": "io.confluent.connect.jms.JmsSinkConnector",
                    "tasks.max": "1",
                    "topics": "sink-messages",
                    "java.naming.factory.initial": "com.solacesystems.jndi.SolJNDIInitialContextFactory",
                    "java.naming.provider.url": "smf://solace:55555",
                    "java.naming.security.principal": "admin",
                    "java.naming.security.credentials": "admin",
                    "jndi.connection.factory": "/jms/cf/default",
                    "Solace_JMS_VPN": "default",
                    "jms.destination.type": "queue",
                    "jms.destination.name": "connector-quickstart",
                    "key.converter": "org.apache.kafka.connect.storage.StringConverter",
                    "value.converter": "org.apache.kafka.connect.storage.StringConverter",
                    "confluent.topic.bootstrap.servers": "broker:9092",
                    "confluent.topic.replication.factor": "1"
          }}' \
     http://localhost:8083/connectors | jq .

sleep 10

echo "Confirm the messages were delivered to the connector-quickstart queue in the default Message VPN using CLI"
docker exec solace bash -c "/usr/sw/loads/currentload/bin/cli -A -s cliscripts/show_queue_cmd"


# [2019-11-07 13:18:52,190] ERROR WorkerSinkTask{id=JMSSolaceSinkConnector-0} Task threw an uncaught and unrecoverable exception (org.apache.kafka.connect.runtime.WorkerTask)
# org.apache.kafka.connect.errors.ConnectException: Unable to open JmsConnection.
#         at io.confluent.connect.jms.JmsConnection.open(JmsConnection.java:125)
#         at io.confluent.connect.jms.BaseJmsSinkTask.start(BaseJmsSinkTask.java:79)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.initializeAndStart(WorkerSinkTask.java:300)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.execute(WorkerSinkTask.java:189)
#         at org.apache.kafka.connect.runtime.WorkerTask.doRun(WorkerTask.java:177)
#         at org.apache.kafka.connect.runtime.WorkerTask.run(WorkerTask.java:227)
#         at java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:511)
#         at java.util.concurrent.FutureTask.run(FutureTask.java:266)
#         at java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1149)
#         at java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:624)
#         at java.lang.Thread.run(Thread.java:748)
# Caused by: java.lang.NoClassDefFoundError: org/apache/commons/lang/exception/NestableException
#         at java.lang.ClassLoader.defineClass1(Native Method)
#         at java.lang.ClassLoader.defineClass(ClassLoader.java:763)
#         at java.security.SecureClassLoader.defineClass(SecureClassLoader.java:142)
#         at java.net.URLClassLoader.defineClass(URLClassLoader.java:468)
#         at java.net.URLClassLoader.access$100(URLClassLoader.java:74)
#         at java.net.URLClassLoader$1.run(URLClassLoader.java:369)
#         at java.net.URLClassLoader$1.run(URLClassLoader.java:363)
#         at java.security.AccessController.doPrivileged(Native Method)
#         at java.net.URLClassLoader.findClass(URLClassLoader.java:362)
#         at org.apache.kafka.connect.runtime.isolation.PluginClassLoader.loadClass(PluginClassLoader.java:96)
#         at java.lang.ClassLoader.loadClass(ClassLoader.java:357)
#         at java.lang.ClassLoader.defineClass1(Native Method)
#         at java.lang.ClassLoader.defineClass(ClassLoader.java:763)
#         at java.security.SecureClassLoader.defineClass(SecureClassLoader.java:142)
#         at java.net.URLClassLoader.defineClass(URLClassLoader.java:468)
#         at java.net.URLClassLoader.access$100(URLClassLoader.java:74)
#         at java.net.URLClassLoader$1.run(URLClassLoader.java:369)
#         at java.net.URLClassLoader$1.run(URLClassLoader.java:363)
#         at java.security.AccessController.doPrivileged(Native Method)
#         at java.net.URLClassLoader.findClass(URLClassLoader.java:362)
#         at org.apache.kafka.connect.runtime.isolation.PluginClassLoader.loadClass(PluginClassLoader.java:96)
#         at java.lang.ClassLoader.loadClass(ClassLoader.java:357)
#         at java.lang.ClassLoader.defineClass1(Native Method)
#         at java.lang.ClassLoader.defineClass(ClassLoader.java:763)
#         at java.security.SecureClassLoader.defineClass(SecureClassLoader.java:142)
#         at java.net.URLClassLoader.defineClass(URLClassLoader.java:468)
#         at java.net.URLClassLoader.access$100(URLClassLoader.java:74)
#         at java.net.URLClassLoader$1.run(URLClassLoader.java:369)
#         at java.net.URLClassLoader$1.run(URLClassLoader.java:363)
#         at java.security.AccessController.doPrivileged(Native Method)
#         at java.net.URLClassLoader.findClass(URLClassLoader.java:362)
#         at org.apache.kafka.connect.runtime.isolation.PluginClassLoader.loadClass(PluginClassLoader.java:96)
#         at java.lang.ClassLoader.loadClass(ClassLoader.java:357)
#         at java.lang.ClassLoader.defineClass1(Native Method)
#         at java.lang.ClassLoader.defineClass(ClassLoader.java:763)
#         at java.security.SecureClassLoader.defineClass(SecureClassLoader.java:142)
#         at java.net.URLClassLoader.defineClass(URLClassLoader.java:468)
#         at java.net.URLClassLoader.access$100(URLClassLoader.java:74)
#         at java.net.URLClassLoader$1.run(URLClassLoader.java:369)
#         at java.net.URLClassLoader$1.run(URLClassLoader.java:363)
#         at java.security.AccessController.doPrivileged(Native Method)
#         at java.net.URLClassLoader.findClass(URLClassLoader.java:362)
#         at org.apache.kafka.connect.runtime.isolation.PluginClassLoader.loadClass(PluginClassLoader.java:96)
#         at java.lang.ClassLoader.loadClass(ClassLoader.java:357)
#         at com.solacesystems.jndi.SolJNDIInitialContextFactory$SolJNDIInitialContext.getDefaultInitCtx(SolJNDIInitialContextFactory.java:745)
#         at javax.naming.InitialContext.init(InitialContext.java:244)
#         at javax.naming.InitialContext.<init>(InitialContext.java:216)
#         at com.solacesystems.jndi.SolJNDIInitialContextFactory$SolJNDIInitialContext.<init>(SolJNDIInitialContextFactory.java:739)
#         at com.solacesystems.jndi.SolJNDIInitialContextFactory.getInitialContext(SolJNDIInitialContextFactory.java:70)
#         at javax.naming.spi.NamingManager.getInitialContext(NamingManager.java:684)
#         at javax.naming.InitialContext.getDefaultInitCtx(InitialContext.java:313)
#         at javax.naming.InitialContext.init(InitialContext.java:244)
#         at javax.naming.InitialContext.<init>(InitialContext.java:216)
#         at io.confluent.connect.jms.DefaultJmsConnection.createInitialContext(DefaultJmsConnection.java:62)
#         at io.confluent.connect.jms.DefaultJmsConnection.createConnectionFactory(DefaultJmsConnection.java:37)
#         at io.confluent.connect.jms.JmsConnection.lambda$open$0(JmsConnection.java:111)
#         at net.jodah.failsafe.Functions.lambda$resultSupplierOf$11(Functions.java:283)
#         at net.jodah.failsafe.internal.executor.RetryPolicyExecutor.lambda$supply$0(RetryPolicyExecutor.java:67)
#         at net.jodah.failsafe.Execution.executeSync(Execution.java:117)
#         at net.jodah.failsafe.FailsafeExecutor.call(FailsafeExecutor.java:319)
#         at net.jodah.failsafe.FailsafeExecutor.get(FailsafeExecutor.java:71)
#         at io.confluent.connect.jms.JmsConnection.open(JmsConnection.java:111)
#         ... 10 more
# Caused by: java.lang.ClassNotFoundException: org.apache.commons.lang.exception.NestableException
#         at java.net.URLClassLoader.findClass(URLClassLoader.java:382)
#         at java.lang.ClassLoader.loadClass(ClassLoader.java:424)
#         at org.apache.kafka.connect.runtime.isolation.PluginClassLoader.loadClass(PluginClassLoader.java:104)
#         at java.lang.ClassLoader.loadClass(ClassLoader.java:357)
#         ... 72 more
# [2019-11-07 13:18:52,191] ERROR WorkerSinkTask{id=JMSSolaceSinkConnector-0} Task is being killed and will not recover until manually restarted (org.apache.kafka.connect.runtime.WorkerTask)
