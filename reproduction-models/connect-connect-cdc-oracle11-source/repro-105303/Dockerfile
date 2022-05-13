ARG CONNECT_TAG
FROM vdesabou/kafka-docker-playground-connect:${CONNECT_TAG}
USER root
RUN wget https://cdn.azul.com/zulu/bin/zulu17.32.13-ca-jdk17.0.2-linux.x86_64.rpm && yum install -y zulu17.32.13-ca-jdk17.0.2-linux.x86_64.rpm  && alternatives --set java /usr/lib/jvm/zulu-17/bin/java
USER appuser
#jvm.spec = Oracle Corporation, Java HotSpot(TM) 64-Bit Server VM, 17.0.2, 17.0.2+8-LTS-86