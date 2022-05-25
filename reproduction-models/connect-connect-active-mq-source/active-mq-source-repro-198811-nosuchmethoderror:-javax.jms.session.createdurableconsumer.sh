#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.repro-198811-nosuchmethoderror:-javax.jms.session.createdurableconsumer.yml"


log "Creating ActiveMQ source connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.confluent.connect.activemq.ActiveMQSourceConnector",
               "kafka.topic": "MyKafkaTopicName",
               "activemq.url": "tcp://activemq:61616",
               "jms.destination.name": "DEV.QUEUE.1",
               "jms.destination.type": "topic",
               "jms.subscription.durable": "true",
	          "jms.subscription.name": "NON_EXISTING-QUEUE",
               "confluent.license": "",
               "confluent.topic.bootstrap.servers": "broker:9092",
               "confluent.topic.replication.factor": "1"
          }' \
     http://localhost:8083/connectors/active-mq-source/config | jq .

sleep 5

log "Sending messages to DEV.QUEUE.1 JMS queue:"
curl -XPOST -u admin:admin -d "body=message" http://localhost:8161/api/message/DEV.QUEUE.1?type=queue

sleep 5

log "Verify we have received the data in MyKafkaTopicName topic"
timeout 60 docker exec connect kafka-avro-console-consumer -bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic MyKafkaTopicName --from-beginning --max-messages 1


# [2022-05-25 08:43:21,308] INFO [active-mq-source|task-0] WorkerSourceTask{id=active-mq-source-0} Either no records were produced by the task since the last offset commit, or every record has been filtered out by a transformation or dropped due to transformation or conversion errors. (org.apache.kafka.connect.runtime.WorkerSourceTask:502)
# [2022-05-25 08:43:21,309] ERROR [active-mq-source|task-0] WorkerSourceTask{id=active-mq-source-0} Task threw an uncaught and unrecoverable exception. Task is being killed and will not recover until manually restarted (org.apache.kafka.connect.runtime.WorkerTask:207)
# java.lang.NoSuchMethodError: javax.jms.Session.createDurableConsumer(Ljavax/jms/Topic;Ljava/lang/String;)Ljavax/jms/MessageConsumer;
#         at io.confluent.connect.jms.core.source.JmsClientHelper.createConsumer(JmsClientHelper.java:169)
#         at io.confluent.connect.jms.core.source.JmsClientHelper.connect(JmsClientHelper.java:105)
#         at io.confluent.connect.jms.core.source.BaseJmsSourceTask.receive(BaseJmsSourceTask.java:181)
#         at io.confluent.connect.jms.core.source.BaseJmsSourceTask.lambda$poll$0(BaseJmsSourceTask.java:292)
#         at io.confluent.connect.utils.retry.RetryPolicy.lambda$call$1(RetryPolicy.java:337)
#         at io.confluent.connect.utils.retry.RetryPolicy.callWith(RetryPolicy.java:417)
#         at io.confluent.connect.utils.retry.RetryPolicy.call(RetryPolicy.java:337)
#         at io.confluent.connect.jms.core.source.BaseJmsSourceTask.poll(BaseJmsSourceTask.java:290)
#         at org.apache.kafka.connect.runtime.WorkerSourceTask.poll(WorkerSourceTask.java:307)
#         at org.apache.kafka.connect.runtime.WorkerSourceTask.execute(WorkerSourceTask.java:263)
#         at org.apache.kafka.connect.runtime.WorkerTask.doRun(WorkerTask.java:200)
#         at org.apache.kafka.connect.runtime.WorkerTask.run(WorkerTask.java:255)
#         at java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:511)
#         at java.util.concurrent.FutureTask.run(FutureTask.java:266)
#         at java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1149)
#         at java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:624)
#         at java.lang.Thread.run(Thread.java:750)