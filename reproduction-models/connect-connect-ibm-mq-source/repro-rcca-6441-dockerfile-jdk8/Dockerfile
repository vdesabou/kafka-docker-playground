ARG CONNECT_TAG
FROM vdesabou/kafka-docker-playground-connect:${CONNECT_TAG}
USER root
RUN wget https://cdn.azul.com/zulu/bin/zulu8.60.0.21-ca-jdk8.0.322-linux.x86_64.rpm && yum install -y zulu8.60.0.21-ca-jdk8.0.322-linux.x86_64.rpm && alternatives --set java /usr/lib/jvm/zulu-8/jre/bin/java
USER appuser
