#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

cd ../../connect/connect-ibm-mq-source

export mq_client=9.3.3.0
curl --silent https://repo1.maven.org/maven2/com/ibm/mq/com.ibm.mq.allclient/$mq_client/com.ibm.mq.allclient-$mq_client.jar --output com.ibm.mq.allclient-$mq_client.jar

wget http://www.java2s.com/Code/JarDownload/jms/jms-1.1.jar.zip ; unzip jms-1.1.jar.zip

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"

log "Creating IBM MQ source connector"
playground connector create-or-update --connector ibm-mq-source << EOF
{
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
}
EOF

sleep 5

log "Sending messages to DEV.QUEUE.1 JMS queue:"
docker exec -i ibmmq /opt/mqm/samp/bin/amqsput DEV.QUEUE.1 << EOF
Message 1
Message 1
EOF

sleep 5

log "Verify we have received the data in MyKafkaTopicName topic"
playground topic consume --topic MyKafkaTopicName --min-expected-messages 2 --timeout 60

docker exec -it connect sh -c "ls /usr/share/confluent-hub-components/confluentinc-kafka-connect-ibmmq/lib | grep ibm"