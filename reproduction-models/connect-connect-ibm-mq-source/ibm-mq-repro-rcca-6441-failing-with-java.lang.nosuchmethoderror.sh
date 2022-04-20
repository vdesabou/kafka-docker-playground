#!/bin/bash
set -e

echo "This issue happens with JDK 8, CP 6.2.1 and 11.0.11"
echo "C3 must be disabled, and there should be at lease 2 brokers"
export TAG=6.1.2
export CONNECTOR_TAG=11.0.11
export DISABLE_CONTROL_CENTER=1

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

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.repro-rcca-6441-failing-with-java.lang.nosuchmethoderror.yml"

log "Make sure JDK 8 is used"
docker exec connect java -version

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
                    "confluent.license": "",
                    "confluent.topic.bootstrap.servers": "broker:9092",
                    "confluent.topic.replication.factor": "1"
          }' \
     http://localhost:8083/connectors/ibm-mq-source/config | jq .

sleep 5

log "Sending messages to DEV.QUEUE.1 JMS queue:"
docker exec -i ibmmq /opt/mqm/samp/bin/amqsput DEV.QUEUE.1 << EOF
Message 1
Message 2

EOF

# [2022-04-15 07:47:25,480] ERROR [ibm-mq-source|worker] WorkerConnector{id=ibm-mq-source} Error while starting connector (org.apache.kafka.connect.runtime.WorkerConnector:194)
# java.lang.NoSuchMethodError: java.nio.ByteBuffer.position(I)Ljava/nio/ByteBuffer;
#         at com.google.protobuf.CodedOutputStream$HeapNioEncoder.flush(CodedOutputStream.java:1546)
#         at io.confluent.serializers.ProtoSerde.serializeUntyped(ProtoSerde.java:63)
#         at io.confluent.serializers.ProtoSerde.serialize(ProtoSerde.java:46)
#         at io.confluent.serializers.ProtoSerde.serialize(ProtoSerde.java:51)
#         at io.confluent.serializers.ProtoSerde.serialize(ProtoSerde.java:24)
#         at org.apache.kafka.common.serialization.Serializer.serialize(Serializer.java:62)
#         at org.apache.kafka.clients.producer.KafkaProducer.doSend(KafkaProducer.java:918)
#         at org.apache.kafka.clients.producer.KafkaProducer.send(KafkaProducer.java:886)
#         at org.apache.kafka.connect.util.KafkaBasedLog.send(KafkaBasedLog.java:292)
#         at io.confluent.license.LicenseStore.registerLicense(LicenseStore.java:284)
#         at io.confluent.license.LicenseStore.registerLicense(LicenseStore.java:277)
#         at io.confluent.license.LicenseManager.registerOrValidateLicense(LicenseManager.java:420)
#         at io.confluent.connect.utils.licensing.ConnectLicenseManager.registerOrValidateLicense(ConnectLicenseManager.java:260)
#         at io.confluent.connect.jms.core.source.BaseJmsSourceConnector.start(BaseJmsSourceConnector.java:38)
#         at org.apache.kafka.connect.runtime.WorkerConnector.doStart(WorkerConnector.java:186)
#         at org.apache.kafka.connect.runtime.WorkerConnector.start(WorkerConnector.java:211)
#         at org.apache.kafka.connect.runtime.WorkerConnector.doTransitionTo(WorkerConnector.java:350)
#         at org.apache.kafka.connect.runtime.WorkerConnector.doTransitionTo(WorkerConnector.java:333)
#         at org.apache.kafka.connect.runtime.WorkerConnector.doRun(WorkerConnector.java:141)
#         at org.apache.kafka.connect.runtime.WorkerConnector.run(WorkerConnector.java:118)
#         at java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:511)
#         at java.util.concurrent.FutureTask.run(FutureTask.java:266)
#         at java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1149)
#         at java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:624)
#         at java.lang.Thread.run(Thread.java:750)
# [2022-04-15 07:47:25,494] ERROR [ibm-mq-source|worker] [Worker clientId=connect-1, groupId=connect-cluster] Failed to start connector 'ibm-mq-source' (org.apache.kafka.connect.runtime.distributed.DistributedHerder:1380)
# org.apache.kafka.connect.errors.ConnectException: Failed to start connector: ibm-mq-source
#         at org.apache.kafka.connect.runtime.distributed.DistributedHerder.lambda$startConnector$6(DistributedHerder.java:1346)
#         at org.apache.kafka.connect.runtime.WorkerConnector.doTransitionTo(WorkerConnector.java:336)
#         at org.apache.kafka.connect.runtime.WorkerConnector.doRun(WorkerConnector.java:141)
#         at org.apache.kafka.connect.runtime.WorkerConnector.run(WorkerConnector.java:118)
#         at java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:511)
#         at java.util.concurrent.FutureTask.run(FutureTask.java:266)
#         at java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1149)
#         at java.util.concurrent.ThreadPoolExecutor$

sleep 5

log "Verify we have received the data in MyKafkaTopicName topic"
timeout 60 docker exec connect kafka-avro-console-consumer -bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic MyKafkaTopicName --from-beginning --max-messages 2
