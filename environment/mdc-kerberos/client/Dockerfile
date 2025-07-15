ARG CP_CONNECT_TAG
ARG CP_CONNECT_IMAGE
FROM ${CP_CONNECT_IMAGE}:${CP_CONNECT_TAG}

# 4. Copy in required settings for client access to Kafka
COPY consumer-us.properties /etc/kafka/consumer-us.properties
COPY producer-us.properties /etc/kafka/producer-us.properties
COPY command-us.properties /etc/kafka/command-us.properties
COPY consumer-europe.properties /etc/kafka/consumer-europe.properties
COPY producer-europe.properties /etc/kafka/producer-europe.properties
COPY command-europe.properties /etc/kafka/command-europe.properties
COPY client.sasl.jaas.config /etc/kafka/client_jaas.conf

CMD sleep infinity