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

cd ${DIR}/security
log "🔐 Generate keys and certificates used for SSL"
docker run -u0 --rm -v $PWD:/tmp vdesabou/kafka-docker-playground-connect:${CONNECT_TAG} bash -c "/tmp/certs-create.sh > /dev/null 2>&1 && chown -R $(id -u $USER):$(id -g $USER) /tmp/"
cd ${DIR}

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.ssl.repro-88346-mqrc_unsupported_cipher_suite.yml"

log "Verify TLS is active on IBM MQ: it should display SSLCIPH(ANY_TLS12)"
docker exec -i ibmmq runmqsc QM1 << EOF
DISPLAY CHANNEL(DEV.APP.SVRCONN)
EOF

log "Creating IBM MQ source connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.confluent.connect.ibm.mq.IbmMQSourceConnector",
               "kafka.topic": "MyKafkaTopicName",
               "mq.hostname": "ibmmq",
               "mq.port": "1414",
               "mq.transport.type": "client",
               "mq.queue.manager": "QM1",
               "mq.channel": "DEV.APP.SVRCONN",
               "mq.username": "app",
               "mq.password": "passw0rd",
               "jms.destination.name": "DEV.QUEUE.1",
               "jms.destination.type": "queue",
               "mq.tls.truststore.location": "/tmp/truststore.jks",
               "mq.tls.truststore.password": "confluent",
               "mq.ssl.cipher.suite":"TLS_RSA_WITH_AES_256_CBC_SHA256",
               "confluent.license": "",
               "confluent.topic.bootstrap.servers": "broker:9092",
               "confluent.topic.replication.factor": "1"
          }' \
     http://localhost:8083/connectors/ibm-mq-source-ssl/config | jq .

sleep 5

# [2022-01-24 16:17:32,735] ERROR [ibm-mq-source-ssl|task-0] Exception (re)establishing connection with connection 1 (io.confluent.connect.jms.core.source.MessageProcessor:294)
# org.apache.kafka.connect.errors.ConnectException: Failed on attempt 1 of 2147483647 to Connecting with connection 1: Failed to start new JMS session connection 1: JMSWMQ0018: Failed to connect to queue manager 'QM1' with connection mode 'Client' and host name 'null'.
#         at io.confluent.connect.utils.retry.RetryPolicy.callWith(RetryPolicy.java:423)
#         at io.confluent.connect.utils.retry.RetryPolicy.call(RetryPolicy.java:337)
#         at io.confluent.connect.jms.core.source.MessageProcessor.startConnectionWithRetries(MessageProcessor.java:275)
#         at io.confluent.connect.jms.core.source.MessageProcessor.poll(MessageProcessor.java:243)
#         at io.confluent.connect.jms.core.source.BaseJmsAsyncSourceTask.poll(BaseJmsAsyncSourceTask.java:149)
#         at org.apache.kafka.connect.runtime.WorkerSourceTask.poll(WorkerSourceTask.java:308)
#         at org.apache.kafka.connect.runtime.WorkerSourceTask.execute(WorkerSourceTask.java:263)
#         at org.apache.kafka.connect.runtime.WorkerTask.doRun(WorkerTask.java:199)
#         at org.apache.kafka.connect.runtime.WorkerTask.run(WorkerTask.java:254)
#         at java.base/java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:515)
#         at java.base/java.util.concurrent.FutureTask.run(FutureTask.java:264)
#         at java.base/java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1128)
#         at java.base/java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:628)
#         at java.base/java.lang.Thread.run(Thread.java:829)
# Caused by: org.apache.kafka.connect.errors.ConnectException: Failed to start new JMS session connection 1: JMSWMQ0018: Failed to connect to queue manager 'QM1' with connection mode 'Client' and host name 'null'.
#         at io.confluent.connect.jms.core.source.JmsConnection.start(JmsConnection.java:175)
#         at io.confluent.connect.jms.core.source.MessageProcessor.tryStartConnection(MessageProcessor.java:308)
#         at io.confluent.connect.jms.core.source.MessageProcessor.lambda$startConnectionWithRetries$1(MessageProcessor.java:280)
#         at io.confluent.connect.utils.retry.RetryPolicy.lambda$call$1(RetryPolicy.java:337)
#         at io.confluent.connect.utils.retry.RetryPolicy.callWith(RetryPolicy.java:417)
#         ... 13 more
# Caused by: com.ibm.msg.client.jms.DetailedJMSException: JMSWMQ0018: Failed to connect to queue manager 'QM1' with connection mode 'Client' and host name 'null'.
# Check the queue manager is started and if running in client mode, check there is a listener running. Please see the linked exception for more information.
#         at com.ibm.msg.client.wmq.common.internal.Reason.reasonToException(Reason.java:595)
#         at com.ibm.msg.client.wmq.common.internal.Reason.createException(Reason.java:215)
#         at com.ibm.msg.client.wmq.internal.WMQConnection.getConnectOptions(WMQConnection.java:1511)
#         at com.ibm.msg.client.wmq.internal.WMQConnection.<init>(WMQConnection.java:380)
#         at com.ibm.msg.client.wmq.factories.WMQConnectionFactory.createV7ProviderConnection(WMQConnectionFactory.java:8475)
#         at com.ibm.msg.client.wmq.factories.WMQConnectionFactory.createProviderConnection(WMQConnectionFactory.java:7815)
#         at com.ibm.msg.client.jms.admin.JmsConnectionFactoryImpl._createConnection(JmsConnectionFactoryImpl.java:322)
#         at com.ibm.msg.client.jms.admin.JmsConnectionFactoryImpl.createConnection(JmsConnectionFactoryImpl.java:242)
#         at com.ibm.mq.jms.MQConnectionFactory.createCommonConnection(MQConnectionFactory.java:6026)
#         at com.ibm.mq.jms.MQConnectionFactory.createConnection(MQConnectionFactory.java:6086)
#         at io.confluent.connect.jms.core.source.JmsConnection.start(JmsConnection.java:132)
#         ... 17 more
# Caused by: com.ibm.mq.MQException: JMSCMQ0001: IBM MQ call failed with compcode '2' ('MQCC_FAILED') reason '2400' ('MQRC_UNSUPPORTED_CIPHER_SUITE').
#         at com.ibm.msg.client.wmq.common.internal.Reason.createException(Reason.java:203)
#         ... 26 more
# [2022-01-24 16:17:32,736] WARN [ibm-mq-source-ssl|task-0] The initial JMS connection wasn't created (io.confluent.connect.jms.core.source.MessageProcessor:245)
# [2022-01-24 16:17:32,736] INFO [ibm-mq-source-ssl|task-0] WorkerSourceTask{id=ibm-mq-source-ssl-0} Either no records were produced by the task since the last offset commit, or every record has been filtered out by a transformation or dropped due to transformation or conversion errors. (org.apache.kafka.connect.runtime.WorkerSourceTask:503)
# [2022-01-24 16:17:32,736] ERROR [ibm-mq-source-ssl|task-0] WorkerSourceTask{id=ibm-mq-source-ssl-0} Task threw an uncaught and unrecoverable exception. Task is being killed and will not recover until manually restarted (org.apache.kafka.connect.runtime.WorkerTask:206)
# org.apache.kafka.connect.errors.ConnectException: Failed to create the initial JMS connection
#         at io.confluent.connect.jms.core.source.MessageProcessor.poll(MessageProcessor.java:247)
#         at io.confluent.connect.jms.core.source.BaseJmsAsyncSourceTask.poll(BaseJmsAsyncSourceTask.java:149)
#         at org.apache.kafka.connect.runtime.WorkerSourceTask.poll(WorkerSourceTask.java:308)
#         at org.apache.kafka.connect.runtime.WorkerSourceTask.execute(WorkerSourceTask.java:263)
#         at org.apache.kafka.connect.runtime.WorkerTask.doRun(WorkerTask.java:199)
#         at org.apache.kafka.connect.runtime.WorkerTask.run(WorkerTask.java:254)
#         at java.base/java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:515)
#         at java.base/java.util.concurrent.FutureTask.run(FutureTask.java:264)
#         at java.base/java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1128)
#         at java.base/java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:628)
#         at java.base/java.lang.Thread.run(Thread.java:829)

log "Sending messages to DEV.QUEUE.1 JMS queue:"
docker exec -i ibmmq /opt/mqm/samp/bin/amqsput DEV.QUEUE.1 << EOF
Message 1
Message 2

EOF

sleep 5

log "Verify we have received the data in MyKafkaTopicName topic"
timeout 60 docker exec connect kafka-avro-console-consumer -bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic MyKafkaTopicName --from-beginning --max-messages 2
