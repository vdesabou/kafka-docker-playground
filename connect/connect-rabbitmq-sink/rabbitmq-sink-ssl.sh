#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

cd ../../connect/connect-rabbitmq-sink/security
playground tools certs-create --output-folder "$PWD" --container connect --container rabbitmq
cd -

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext-ssl.yml"


log "Create RabbitMQ exchange, queue and binding"
docker exec -i rabbitmq rabbitmqadmin -u myuser -p mypassword -V / declare exchange name=exchange1 type=direct
docker exec -i rabbitmq rabbitmqadmin -u myuser -p mypassword -V / declare queue name=queue1 durable=true
docker exec -i rabbitmq rabbitmqadmin -u myuser -p mypassword -V / declare binding source=exchange1 destination=queue1 routing_key=rkey1


log "Sending messages to topic rabbitmq-messages"
playground topic produce -t rabbitmq-messages --nb-messages 10 << 'EOF'
%g
EOF

log "Creating RabbitMQ Sink connector"
playground connector create-or-update --connector rabbitmq-sink  << EOF
{
     "connector.class" : "io.confluent.connect.rabbitmq.sink.RabbitMQSinkConnector",
     "tasks.max" : "1",
     "topics": "rabbitmq-messages",
     "key.converter": "org.apache.kafka.connect.storage.StringConverter",
     "value.converter": "org.apache.kafka.connect.converters.ByteArrayConverter",
     "rabbitmq.queue" : "myqueue",
     "rabbitmq.host" : "rabbitmq",
     "rabbitmq.port" : "5671",
     "rabbitmq.username" : "myuser",
     "rabbitmq.password" : "mypassword",
     "rabbitmq.exchange": "exchange1",
     "rabbitmq.routing.key": "rkey1",
     "rabbitmq.delivery.mode": "PERSISTENT",
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

log "Check messages received in RabbitMQ"
docker exec -i rabbitmq rabbitmqadmin -u myuser -p mypassword get queue=queue1 count=10 > /tmp/result.log  2>&1
cat /tmp/result.log
grep "rkey1" /tmp/result.log