ARG TAG
ARG CONNECTOR_TAG
FROM vdesabou/kafka-docker-playground-connect:${TAG}
COPY jdk-8u201-linux-x64.rpm /tmp/
USER root
RUN microdnf install yum \
    && yum -y install /tmp/jdk-8u201-linux-x64.rpm && alternatives --list \
    && rm -f /tmp/jdk-8u201-linux-x64.rpm
# && alternatives --remove java /usr/lib/jvm/zulu11/bin/java
USER appuser
ARG CONNECTOR_TAG
RUN confluent-hub install --no-prompt confluentinc/kafka-connect-hdfs:${CONNECTOR_TAG}
# https://stackoverflow.com/a/41548434/2381999
# WORKDIR /
# RUN yum -y install gcc automake autoconf libtool make git && git clone https://github.com/wolfcw/libfaketime.git
# WORKDIR /libfaketime/src
# RUN make install
# CMD ["/bin/sh", "-c", "LD_PRELOAD=/usr/local/lib/faketime/libfaketime.so.1 FAKETIME_NO_CACHE=1 python /srv/intercept/manage.py runserver 0.0.0.0:3000]