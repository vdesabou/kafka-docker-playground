#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

# Need to create the TIBCO EMS image using https://github.com/mikeschippers/docker-tibco
cd ${DIR}/docker-tibco/
get_3rdparty_file "TIB_ems-ce_8.5.1_linux_x86_64.zip"
cd -
if [ ! -f ${DIR}/docker-tibco/TIB_ems-ce_8.5.1_linux_x86_64.zip ]
then
     logerror "ERROR: ${DIR}/docker-tibco/ does not contain TIBCO EMS zip file TIB_ems-ce_8.5.1_linux_x86_64.zip"
     exit 1
fi

if [ ! -f ${DIR}/tibjms.jar ]
then
     log "${DIR}/tibjms.jar missing, will get it from ${DIR}/docker-tibco/TIB_ems-ce_8.5.1_linux_x86_64.zip"
     rm -rf /tmp/TIB_ems-ce_8.5.1
     unzip ${DIR}/docker-tibco/TIB_ems-ce_8.5.1_linux_x86_64.zip -d /tmp/
     tar xvfz /tmp/TIB_ems-ce_8.5.1/tar/TIB_ems-ce_8.5.1_linux_x86_64-java_client.tar.gz opt/tibco/ems/8.5/lib/tibjms.jar
     cp ${DIR}/opt/tibco/ems/8.5/lib/tibjms.jar ${DIR}/
     rm -rf ${DIR}/opt
fi

if [ ! -f ${DIR}/jms-2.0.jar ]
then
     log "${DIR}/jms-2.0.jar missing, will get it from ${DIR}/docker-tibco/TIB_ems-ce_8.5.1_linux_x86_64.zip"
     rm -rf /tmp/TIB_ems-ce_8.5.1
     unzip ${DIR}/docker-tibco/TIB_ems-ce_8.5.1_linux_x86_64.zip -d /tmp/
     tar xvfz /tmp/TIB_ems-ce_8.5.1/tar/TIB_ems-ce_8.5.1_linux_x86_64-java_client.tar.gz opt/tibco/ems/8.5/lib/jms-2.0.jar
     cp ${DIR}/opt/tibco/ems/8.5/lib/jms-2.0.jar ${DIR}/
     rm -rf ${DIR}/opt
fi

log "Using queues-repro-illegalstateexception.conf where expiration is 3 seconds"
cp queues-repro-illegalstateexception.conf docker-tibco/queues.conf

if test -z "$(docker images -q tibems:smallexpiration)"
then
     log "Building TIBCO EMS docker image..it can take a while..."
     OLDDIR=$PWD
     cd ${DIR}/docker-tibco
     docker build -t tibbase:1.0.0 ./tibbase
     docker build -t tibems:smallexpiration . -f ./tibems/Dockerfile
     cd ${OLDDIR}
fi

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.repro-illegalstateexception.yml"

#log "Installing iptables on tibco-ems"
#docker exec --privileged --user root -i tibco-ems bash -c 'apt-get -y update && apt-get -y install iptables dsniff net-tools'

# curl --request PUT \
#   --url http://localhost:8083/admin/loggers/io.confluent.connect \
#   --header 'Accept: application/json' \
#   --header 'Content-Type: application/json' \
#   --data '{
# 	"level": "TRACE"
# }'

log "Sending EMS messages m1 m2 m3 m4 m5 in queue connector-quickstart"
docker exec tibco-ems bash -c '
cd /opt/tibco/ems/8.5/samples/java
export TIBEMS_JAVA=/opt/tibco/ems/8.5/lib
CLASSPATH=${TIBEMS_JAVA}/jms-2.0.jar:${CLASSPATH}
CLASSPATH=.:${TIBEMS_JAVA}/tibjms.jar:${TIBEMS_JAVA}/tibjmsadmin.jar:${CLASSPATH}
export CLASSPATH
javac *.java
java tibjmsMsgProducer -user admin -queue connector-quickstart m1 m2 m3 m4 m5'


log "Creating JMS TIBCO source connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.confluent.connect.jms.JmsSourceConnector",
               "tasks.max": "1",
               "kafka.topic": "from-tibco-messages",
               "java.naming.factory.initial": "com.tibco.tibjms.naming.TibjmsInitialContextFactory",
               "java.naming.provider.url": "tibjmsnaming://tibco-ems:7222",
               "jms.destination.type": "queue",
               "jms.destination.name": "connector-quickstart",
               "key.converter": "org.apache.kafka.connect.storage.StringConverter",
               "value.converter": "org.apache.kafka.connect.storage.StringConverter",
               "confluent.license": "",
               "confluent.topic.bootstrap.servers": "broker:9092",
               "confluent.topic.replication.factor": "1"
          }' \
     http://localhost:8083/connectors/jms-tibco-source/config | jq .

sleep 5

log "Verify we have received the data in from-tibco-messages topic"
timeout 60 docker exec connect kafka-console-consumer -bootstrap-server broker:9092 --topic from-tibco-messages --from-beginning --max-messages 2

log "Add 10 seconds latency for ACK"
add_latency connect tibco-ems 10000ms

log "Sending EMS messages m1 m2 m3 m4 m5 in queue connector-quickstart"
docker exec tibco-ems bash -c '
cd /opt/tibco/ems/8.5/samples/java
export TIBEMS_JAVA=/opt/tibco/ems/8.5/lib
CLASSPATH=${TIBEMS_JAVA}/jms-2.0.jar:${CLASSPATH}
CLASSPATH=.:${TIBEMS_JAVA}/tibjms.jar:${TIBEMS_JAVA}/tibjmsadmin.jar:${CLASSPATH}
export CLASSPATH
javac *.java
java tibjmsMsgProducer -user admin -queue connector-quickstart m1 m2 m3 m4 m5'


# [2021-11-25 13:45:06,406] ERROR [jms-tibco-source|task-0] WorkerSourceTask{id=jms-tibco-source-0} Exception thrown while calling task.commitRecord() (org.apache.kafka.connect.runtime.WorkerSourceTask:480)
# org.apache.kafka.connect.errors.ConnectException: Failed on attempt 1 of 2147483647 to Acknowledge Jms Message: javax.jms.IllegalStateException: Attempt to acknowledge message(s) not valid for this consumer
#         at io.confluent.connect.utils.retry.RetryPolicy.callWith(RetryPolicy.java:423)
#         at io.confluent.connect.utils.retry.RetryPolicy.call(RetryPolicy.java:337)
#         at io.confluent.connect.jms.core.source.BaseJmsSourceTask.commitRecord(BaseJmsSourceTask.java:365)
#         at org.apache.kafka.connect.source.SourceTask.commitRecord(SourceTask.java:138)
#         at org.apache.kafka.connect.runtime.WorkerSourceTask.commitTaskRecord(WorkerSourceTask.java:478)
#         at org.apache.kafka.connect.runtime.WorkerSourceTask.lambda$sendRecords$6(WorkerSourceTask.java:389)
#         at org.apache.kafka.clients.producer.KafkaProducer$InterceptorCallback.onCompletion(KafkaProducer.java:1369)
#         at org.apache.kafka.clients.producer.internals.ProducerBatch.completeFutureAndFireCallbacks(ProducerBatch.java:270)
#         at org.apache.kafka.clients.producer.internals.ProducerBatch.done(ProducerBatch.java:234)
#         at org.apache.kafka.clients.producer.internals.ProducerBatch.complete(ProducerBatch.java:180)
#         at org.apache.kafka.clients.producer.internals.Sender.completeBatch(Sender.java:678)
#         at org.apache.kafka.clients.producer.internals.Sender.completeBatch(Sender.java:649)
#         at org.apache.kafka.clients.producer.internals.Sender.lambda$null$1(Sender.java:575)
#         at java.base/java.util.ArrayList.forEach(ArrayList.java:1541)
#         at org.apache.kafka.clients.producer.internals.Sender.lambda$handleProduceResponse$2(Sender.java:562)
#         at java.base/java.lang.Iterable.forEach(Iterable.java:75)
#         at org.apache.kafka.clients.producer.internals.Sender.handleProduceResponse(Sender.java:562)
#         at org.apache.kafka.clients.producer.internals.Sender.lambda$sendProduceRequest$5(Sender.java:836)
#         at org.apache.kafka.clients.ClientResponse.onComplete(ClientResponse.java:109)
#         at org.apache.kafka.clients.NetworkClient.completeResponses(NetworkClient.java:658)
#         at org.apache.kafka.clients.NetworkClient.poll(NetworkClient.java:650)
#         at org.apache.kafka.clients.producer.internals.Sender.runOnce(Sender.java:328)
#         at org.apache.kafka.clients.producer.internals.Sender.run(Sender.java:243)
#         at java.base/java.lang.Thread.run(Thread.java:829)
# Caused by: org.apache.kafka.connect.errors.ConnectException: javax.jms.IllegalStateException: Attempt to acknowledge message(s) not valid for this consumer
#         at io.confluent.connect.jms.core.source.BaseJmsSourceTask.acknowledge(BaseJmsSourceTask.java:411)
#         at io.confluent.connect.jms.core.source.BaseJmsSourceTask.lambda$commitRecord$1(BaseJmsSourceTask.java:367)
#         at io.confluent.connect.utils.retry.RetryPolicy.lambda$call$1(RetryPolicy.java:337)
#         at io.confluent.connect.utils.retry.RetryPolicy.callWith(RetryPolicy.java:417)
#         ... 23 more
# Caused by: javax.jms.IllegalStateException: Attempt to acknowledge message(s) not valid for this consumer
#         at com.tibco.tibjms.Tibjmsx.buildException(Tibjmsx.java:734)
#         at com.tibco.tibjms.TibjmsxSessionImp._confirmNonTransacted(TibjmsxSessionImp.java:3882)
#         at com.tibco.tibjms.TibjmsxSessionImp._confirm(TibjmsxSessionImp.java:3983)
#         at com.tibco.tibjms.TibjmsxSessionImp._confirmNonAuto(TibjmsxSessionImp.java:5497)
#         at com.tibco.tibjms.TibjmsMessage.acknowledge(TibjmsMessage.java:627)
#         at io.confluent.connect.jms.core.source.JmsClientHelper.acknowledge(JmsClientHelper.java:244)
#         at io.confluent.connect.jms.core.source.BaseJmsSourceTask.acknowledge(BaseJmsSourceTask.java:398)
#         ... 26 more
# [2021-11-25 13:45:07,438] TRACE [jms-tibco-source|task-0] Received no message from consumer in 5001 ms (io.confluent.connect.jms.core.source.JmsClientHelper:205)
# [2021-11-25 13:45:07,438] TRACE [jms-tibco-source|task-0] jms-tibco-source-0 No message received. (io.confluent.connect.jms.core.source.BaseJmsSourceTask:185)
# [2021-11-25 13:45:07,438] DEBUG [jms-tibco-source|task-0] jms-tibco-source-0 Returning 0 records after receiving no new messages within 5000ms (io.confluent.connect.jms.core.source.BaseJmsSourceTask:295)
# [2021-11-25 13:45:07,439] INFO [jms-tibco-source|task-0] WorkerSourceTask{id=jms-tibco-source-0} flushing 0 outstanding messages for offset commit (org.apache.kafka.connect.runtime.WorkerSourceTask:518)
# [2021-11-25 13:45:07,457] ERROR [jms-tibco-source|task-0] WorkerSourceTask{id=jms-tibco-source-0} Task threw an uncaught and unrecoverable exception. Task is being killed and will not recover until manually restarted (org.apache.kafka.connect.runtime.WorkerTask:205)
# org.apache.kafka.connect.errors.ConnectException: Encountered an unrecoverable exception while committing a record.
#         at io.confluent.connect.jms.core.source.BaseJmsSourceTask.poll(BaseJmsSourceTask.java:220)
#         at org.apache.kafka.connect.runtime.WorkerSourceTask.poll(WorkerSourceTask.java:289)
#         at org.apache.kafka.connect.runtime.WorkerSourceTask.execute(WorkerSourceTask.java:252)
#         at org.apache.kafka.connect.runtime.WorkerTask.doRun(WorkerTask.java:198)
#         at org.apache.kafka.connect.runtime.WorkerTask.run(WorkerTask.java:253)
#         at java.base/java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:515)
#         at java.base/java.util.concurrent.FutureTask.run(FutureTask.java:264)
#         at java.base/java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1128)
#         at java.base/java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:628)
#         at java.base/java.lang.Thread.run(Thread.java:829)
# Caused by: javax.jms.IllegalStateException: Attempt to acknowledge message(s) not valid for this consumer
#         at com.tibco.tibjms.Tibjmsx.buildException(Tibjmsx.java:734)
#         at com.tibco.tibjms.TibjmsxSessionImp._confirmNonTransacted(TibjmsxSessionImp.java:3882)
#         at com.tibco.tibjms.TibjmsxSessionImp._confirm(TibjmsxSessionImp.java:3983)
#         at com.tibco.tibjms.TibjmsxSessionImp._confirmNonAuto(TibjmsxSessionImp.java:5497)
#         at com.tibco.tibjms.TibjmsMessage.acknowledge(TibjmsMessage.java:627)
#         at io.confluent.connect.jms.core.source.JmsClientHelper.acknowledge(JmsClientHelper.java:244)
#         at io.confluent.connect.jms.core.source.BaseJmsSourceTask.acknowledge(BaseJmsSourceTask.java:398)
#         at io.confluent.connect.jms.core.source.BaseJmsSourceTask.lambda$commitRecord$1(BaseJmsSourceTask.java:367)
#         at io.confluent.connect.utils.retry.RetryPolicy.lambda$call$1(RetryPolicy.java:337)
#         at io.confluent.connect.utils.retry.RetryPolicy.callWith(RetryPolicy.java:417)
#         at io.confluent.connect.utils.retry.RetryPolicy.call(RetryPolicy.java:337)
#         at io.confluent.connect.jms.core.source.BaseJmsSourceTask.commitRecord(BaseJmsSourceTask.java:365)
#         at org.apache.kafka.connect.source.SourceTask.commitRecord(SourceTask.java:138)
#         at org.apache.kafka.connect.runtime.WorkerSourceTask.commitTaskRecord(WorkerSourceTask.java:478)
#         at org.apache.kafka.connect.runtime.WorkerSourceTask.lambda$sendRecords$6(WorkerSourceTask.java:389)
#         at org.apache.kafka.clients.producer.KafkaProducer$InterceptorCallback.onCompletion(KafkaProducer.java:1369)
#         at org.apache.kafka.clients.producer.internals.ProducerBatch.completeFutureAndFireCallbacks(ProducerBatch.java:270)
#         at org.apache.kafka.clients.producer.internals.ProducerBatch.done(ProducerBatch.java:234)
#         at org.apache.kafka.clients.producer.internals.ProducerBatch.complete(ProducerBatch.java:180)
#         at org.apache.kafka.clients.producer.internals.Sender.completeBatch(Sender.java:678)
#         at org.apache.kafka.clients.producer.internals.Sender.completeBatch(Sender.java:649)
#         at org.apache.kafka.clients.producer.internals.Sender.lambda$null$1(Sender.java:575)
#         at java.base/java.util.ArrayList.forEach(ArrayList.java:1541)
#         at org.apache.kafka.clients.producer.internals.Sender.lambda$handleProduceResponse$2(Sender.java:562)
#         at java.base/java.lang.Iterable.forEach(Iterable.java:75)
#         at org.apache.kafka.clients.producer.internals.Sender.handleProduceResponse(Sender.java:562)
#         at org.apache.kafka.clients.producer.internals.Sender.lambda$sendProduceRequest$5(Sender.java:836)
#         at org.apache.kafka.clients.ClientResponse.onComplete(ClientResponse.java:109)
#         at org.apache.kafka.clients.NetworkClient.completeResponses(NetworkClient.java:658)
#         at org.apache.kafka.clients.NetworkClient.poll(NetworkClient.java:650)
#         at org.apache.kafka.clients.producer.internals.Sender.runOnce(Sender.java:328)
#         at org.apache.kafka.clients.producer.internals.Sender.run(Sender.java:243)
#         ... 1 more
