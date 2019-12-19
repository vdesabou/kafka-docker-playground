#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"

echo -e "\033[0;33mSend message to RabbitMQ in myqueue\033[0m"
docker exec rabbitmq_producer bash -c "python /producer.py myqueue 5"

echo -e "\033[0;33mCreating RabbitMQ Source connector\033[0m"
docker exec connect \
     curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class" : "io.confluent.connect.rabbitmq.RabbitMQSourceConnector",
                  "tasks.max" : "1",
                  "kafka.topic" : "rabbitmq",
                  "rabbitmq.queue" : "myqueue",
                  "rabbitmq.host" : "rabbitmq",
                  "rabbitmq.username" : "myuser",
                  "rabbitmq.password" : "mypassword"
          }' \
     http://localhost:8083/connectors/rabbitmq-source/config | jq .


sleep 5

echo -e "\033[0;33mVerify we have received the data in rabbitmq topic\033[0m"
docker exec schema-registry kafka-avro-console-consumer -bootstrap-server broker:9092 --topic rabbitmq --from-beginning --max-messages 5

#echo -e "\033[0;33mConsume messages in RabbitMQ\033[0m"
#docker exec -it rabbitmq_consumer bash -c "python /consumer.py myqueue"