#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

cd ../../connect/connect-rabbitmq-source/security
log "🔐 Generate keys and certificates used for SSL"
docker run -u0 --rm -v $PWD:/tmp ${CP_CONNECT_IMAGE}:${CONNECT_TAG} bash -c "/tmp/certs-create.sh > /dev/null 2>&1 && chown -R $(id -u $USER):$(id -g $USER) /tmp/ && chmod a+r /tmp/*"
cd -

playground start-environment --environment plaintext --docker-compose-override-file "${PWD}/docker-compose.plaintext-ssl.yml"

sleep 5

log "Send message to RabbitMQ in myqueue"
docker exec rabbitmq_producer bash -c "python /producer.py myqueue 5"

log "Creating RabbitMQ Source connector"
playground connector create-or-update --connector rabbitmq-source << EOF
{
     "connector.class" : "io.confluent.connect.rabbitmq.RabbitMQSourceConnector",
     "tasks.max" : "1",
     "kafka.topic" : "rabbitmq",
     "rabbitmq.queue" : "myqueue",
     "rabbitmq.host" : "rabbitmq",
     "rabbitmq.port" : "5671",
     "rabbitmq.username" : "myuser",
     "rabbitmq.password" : "mypassword",
     "confluent.topic.bootstrap.servers": "broker:9092",
     "confluent.topic.replication.factor": "1",
     "rabbitmq.security.protocol": "SSL",
     "rabbitmq.https.ssl.truststore.location": "/tmp/truststore.jks",
     "rabbitmq.https.ssl.truststore.password": "confluent",
     "rabbitmq.https.ssl.keystore.location": "/tmp/keystore.jks",
     "rabbitmq.https.ssl.keystore.password": "confluent"
}
EOF


sleep 5

log "Verify we have received the data in rabbitmq topic"
playground topic consume --topic rabbitmq --min-expected-messages 5 --timeout 60

#log "Consume messages in RabbitMQ"
#docker exec -i rabbitmq_consumer bash -c "python /consumer.py myqueue"