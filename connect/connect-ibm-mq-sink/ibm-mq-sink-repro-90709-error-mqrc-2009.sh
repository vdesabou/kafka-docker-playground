#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

get_3rdparty_file "IBM-MQ-Install-Java-All.jar"

if [ ! -f ${DIR}/IBM-MQ-Install-Java-All.jar ]
then
     # not running with github actions
     logerror "ERROR: ${DIR}/IBM-MQ-Install-Java-All.jar is missing. It must be downloaded manually in order to acknowledge user agreement"
     exit 1
fi

if [ ! -f ${DIR}/com.ibm.mq.allclient.jar ]
then
     # install deps
     log "Getting com.ibm.mq.allclient.jar and jms.jar from IBM-MQ-Install-Java-All.jar"
     if [[ "$OSTYPE" == "darwin"* ]]
     then
          # workaround for issue on linux, see https://github.com/vdesabou/kafka-docker-playground/issues/851#issuecomment-821151962
          rm -rf ${DIR}/install/
     else
          sudo rm -rf ${DIR}/install/
     fi
     docker run --rm -v ${DIR}/IBM-MQ-Install-Java-All.jar:/tmp/IBM-MQ-Install-Java-All.jar -v ${DIR}/install:/tmp/install openjdk:8 java -jar /tmp/IBM-MQ-Install-Java-All.jar --acceptLicense /tmp/install
     cp ${DIR}/install/wmq/JavaSE/lib/jms.jar ${DIR}/
     cp ${DIR}/install/wmq/JavaSE/lib/com.ibm.mq.allclient.jar ${DIR}/
fi

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.repro-90709-error-mqrc-2009.yml"

log "Sending messages to topic sink-messages"
docker exec -i broker kafka-console-producer --broker-list broker:9092 --topic sink-messages << EOF
This is my message
EOF

curl --request PUT \
  --url http://localhost:8083/admin/loggers/io.confluent.connect.jms \
  --header 'Accept: application/json' \
  --header 'Content-Type: application/json' \
  --data '{
	"level": "TRACE"
}'

log "Creating IBM MQ source connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.confluent.connect.jms.IbmMqSinkConnector",
                    "topics": "sink-messages",
                    "mq.hostname": "ibmmq",
                    "mq.port": "1414",
                    "mq.transport.type": "client",
                    "mq.queue.manager": "QM1",
                    "mq.channel": "DEV.APP.SVRCONN",
                    "mq.username": "app",
                    "mq.password": "passw0rd",
                    "jms.destination.name": "DEV.QUEUE.1",
                    "jms.destination.type": "queue",
                    "value.converter": "org.apache.kafka.connect.storage.StringConverter",
                    "key.converter": "org.apache.kafka.connect.storage.StringConverter",
                    "confluent.license": "",
                    "confluent.topic.bootstrap.servers": "broker:9092",
                    "confluent.topic.replication.factor": "1"
          }' \
     http://localhost:8083/connectors/ibm-mq-sink4/config | jq .

sleep 10

log "Verify message received in DEV.QUEUE.1 queue"
docker exec ibmmq bash -c "/opt/mqm/samp/bin/amqsbcg DEV.QUEUE.1" > /tmp/result.log  2>&1
cat /tmp/result.log
grep "my message" /tmp/result.log

log "Blocking traffic from IBM MQ $IP"
IP=$(docker inspect -f '{{.Name}} - {{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $(docker ps -aq) | grep ibmmq | cut -d " " -f 3)
docker exec --privileged --user root connect bash -c "iptables -A INPUT -p tcp -s $IP -j DROP"


# [2022-02-02 15:08:49,763] WARN [ibm-mq-sink|task-0] Could not produce message. Will retry for 60000 millis (io.confluent.connect.jms.BaseJmsSinkTask:182)
# com.ibm.msg.client.jms.DetailedJMSException: JMSWMQ2007: Failed to send a message to destination 'DEV.QUEUE.1'.
# JMS attempted to perform an MQPUT or MQPUT1; however IBM MQ reported an error.
# Use the linked exception to determine the cause of this error.
#         at com.ibm.msg.client.wmq.common.internal.Reason.reasonToException(Reason.java:595)
#         at com.ibm.msg.client.wmq.common.internal.Reason.createException(Reason.java:215)
#         at com.ibm.msg.client.wmq.internal.WMQMessageProducer.checkJmqiCallSuccess(WMQMessageProducer.java:1293)
#         at com.ibm.msg.client.wmq.internal.WMQMessageProducer.checkJmqiCallSuccess(WMQMessageProducer.java:1250)
#         at com.ibm.msg.client.wmq.internal.WMQMessageProducer.access$800(WMQMessageProducer.java:76)
#         at com.ibm.msg.client.wmq.internal.WMQMessageProducer$SpiIdentifiedProducerShadow.sendInternal(WMQMessageProducer.java:911)
#         at com.ibm.msg.client.wmq.internal.WMQMessageProducer$ProducerShadow.send(WMQMessageProducer.java:567)
#         at com.ibm.msg.client.wmq.internal.WMQMessageProducer.send(WMQMessageProducer.java:1433)
#         at com.ibm.msg.client.jms.internal.JmsMessageProducerImpl.sendMessage(JmsMessageProducerImpl.java:855)
#         at com.ibm.msg.client.jms.internal.JmsMessageProducerImpl.synchronousSendInternal(JmsMessageProducerImpl.java:2055)
#         at com.ibm.msg.client.jms.internal.JmsMessageProducerImpl.sendInternal(JmsMessageProducerImpl.java:1993)
#         at com.ibm.msg.client.jms.internal.JmsMessageProducerImpl.send(JmsMessageProducerImpl.java:1486)
#         at com.ibm.mq.jms.MQMessageProducer.send(MQMessageProducer.java:293)
#         at io.confluent.connect.jms.BaseJmsSinkTask.send(BaseJmsSinkTask.java:174)
#         at java.base/java.util.stream.ForEachOps$ForEachOp$OfRef.accept(ForEachOps.java:183)
#         at java.base/java.util.stream.ReferencePipeline$2$1.accept(ReferencePipeline.java:177)
#         at java.base/java.util.ArrayList$ArrayListSpliterator.forEachRemaining(ArrayList.java:1655)
#         at java.base/java.util.stream.AbstractPipeline.copyInto(AbstractPipeline.java:484)
#         at java.base/java.util.stream.AbstractPipeline.wrapAndCopyInto(AbstractPipeline.java:474)
#         at java.base/java.util.stream.ForEachOps$ForEachOp.evaluateSequential(ForEachOps.java:150)
#         at java.base/java.util.stream.ForEachOps$ForEachOp$OfRef.evaluateSequential(ForEachOps.java:173)
#         at java.base/java.util.stream.AbstractPipeline.evaluate(AbstractPipeline.java:234)
#         at java.base/java.util.stream.ReferencePipeline.forEach(ReferencePipeline.java:497)
#         at io.confluent.connect.jms.BaseJmsSinkTask.put(BaseJmsSinkTask.java:111)
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
# Caused by: com.ibm.mq.MQException: JMSCMQ0001: IBM MQ call failed with compcode '2' ('MQCC_FAILED') reason '2009' ('MQRC_CONNECTION_BROKEN').
#         at com.ibm.msg.client.wmq.common.internal.Reason.createException(Reason.java:203)
#         ... 33 more
# Caused by: com.ibm.mq.jmqi.JmqiException: CC=2;RC=2009;AMQ9206: Error sending data to host 'ibmmq/192.168.240.4:1414 (ibmmq)'. [1=com.ibm.mq.jmqi.JmqiException[CC=2;RC=2009],3=ibmmq/192.168.240.4:1414 (ibmmq),4=TCP,5=RemoteTCPConnection.send(byte [ ],int,int,int,int)]
#         at com.ibm.mq.jmqi.remote.impl.RemoteTCPConnection.send(RemoteTCPConnection.java:1708)
#         at com.ibm.mq.jmqi.remote.impl.RemoteConnection.wrapSend(RemoteConnection.java:2976)
#         at com.ibm.mq.jmqi.remote.impl.RemoteConnection.sendTSH(RemoteConnection.java:2742)
#         at com.ibm.mq.jmqi.remote.impl.RemoteSession.sendTSH(RemoteSession.java:775)
#         at com.ibm.mq.jmqi.remote.impl.RemoteSession.sendTSH(RemoteSession.java:691)
#         at com.ibm.mq.jmqi.remote.api.RemoteFAP.jmqiPutMessageWithProps(RemoteFAP.java:8143)
#         at com.ibm.mq.jmqi.remote.api.RemoteFAP.jmqiPut(RemoteFAP.java:7037)
#         at com.ibm.mq.ese.jmqi.InterceptedJmqiImpl.jmqiPut(InterceptedJmqiImpl.java:636)
#         at com.ibm.mq.ese.jmqi.ESEJMQI.jmqiPut(ESEJMQI.java:637)
#         at com.ibm.msg.client.wmq.internal.WMQMessageProducer$SpiIdentifiedProducerShadow.sendInternal(WMQMessageProducer.java:897)
#         ... 29 more
# Caused by: com.ibm.mq.jmqi.JmqiException: CC=2;RC=2009
#         at com.ibm.mq.jmqi.remote.impl.RemoteConnection.asyncConnectionBroken(RemoteConnection.java:3837)
#         at com.ibm.mq.jmqi.remote.impl.RemoteRcvThread.run(RemoteRcvThread.java:587)
#         at com.ibm.msg.client.commonservices.workqueue.WorkQueueItem.runTask(WorkQueueItem.java:319)
#         at com.ibm.msg.client.commonservices.workqueue.SimpleWorkQueueItem.runItem(SimpleWorkQueueItem.java:99)
#         at com.ibm.msg.client.commonservices.workqueue.WorkQueueItem.run(WorkQueueItem.java:343)
#         at com.ibm.msg.client.commonservices.workqueue.WorkQueueManager.runWorkQueueItem(WorkQueueManager.java:312)
#         at com.ibm.msg.client.commonservices.j2se.workqueue.WorkQueueManagerImplementation$ThreadPoolWorker.run(WorkQueueManagerImplementation.java:1227)
# Caused by: com.ibm.mq.jmqi.JmqiException: CC=2;RC=2009;AMQ9208: Error on receive from host 'ibmmq/192.168.240.4:1414 (ibmmq)'. [1=-1,2=ffffffff,3=ibmmq/192.168.240.4:1414 (ibmmq),4=TCP]
#         at com.ibm.mq.jmqi.remote.impl.RemoteRcvThread.receiveBuffer(RemoteRcvThread.java:796)
#         at com.ibm.mq.jmqi.remote.impl.RemoteRcvThread.receiveOneTSH(RemoteRcvThread.java:739)
#         at com.ibm.mq.jmqi.remote.impl.RemoteRcvThread.run(RemoteRcvThread.java:156)
#         ... 5 more