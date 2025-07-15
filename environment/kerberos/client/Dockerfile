ARG CP_CONNECT_TAG
ARG CP_CONNECT_IMAGE
FROM ${CP_CONNECT_IMAGE}:${CP_CONNECT_TAG}

# 4. Copy in required settings for client access to Kafka
COPY consumer.properties /etc/kafka/consumer.properties
COPY producer.properties /etc/kafka/producer.properties
COPY command.properties /etc/kafka/command.properties
COPY client.sasl.jaas.config /etc/kafka/client_jaas.conf

CMD sleep infinity
