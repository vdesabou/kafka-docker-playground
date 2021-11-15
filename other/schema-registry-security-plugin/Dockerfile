# workaround for https://github.com/vdesabou/kafka-docker-playground/issues/1494#issuecomment-965573878
ARG TAG
FROM confluentinc/cp-schema-registry:${TAG}
COPY ensure /etc/confluent/docker/ensure
USER root
RUN ["chmod", "+x", "/etc/confluent/docker/ensure"]