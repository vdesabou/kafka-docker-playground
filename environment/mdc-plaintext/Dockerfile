ARG TAG_BASE
ARG CONNECT_TAG
ARG CP_CONNECT_IMAGE
FROM ${CP_CONNECT_IMAGE}:${CONNECT_TAG}
ARG TAG_BASE
RUN confluent-hub install --no-prompt confluentinc/kafka-connect-replicator:${TAG_BASE}
