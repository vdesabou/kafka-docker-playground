ARG TAG_BASE
ARG CONNECT_TAG
FROM vdesabou/kafka-docker-playground-connect:${CONNECT_TAG}
ARG TAG_BASE
RUN confluent-hub install --no-prompt confluentinc/kafka-connect-replicator:${TAG_BASE}
