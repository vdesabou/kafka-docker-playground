ARG CONNECT_TAG
FROM vdesabou/kafka-docker-playground-connect:${CONNECT_TAG}
USER root
RUN wget https://cdn.azul.com/zulu/bin/zulu17.32.13-ca-jdk17.0.2-linux.x86_64.rpm && yum install -y zulu17.32.13-ca-jdk17.0.2-linux.x86_64.rpm  && alternatives --set java /usr/lib/jvm/zulu-17/bin/java
USER appuser
RUN cd /home/appuser && wget https://archive.apache.org/dist/kafka/3.1.0/kafka_2.13-3.1.0.tgz && tar xvfz kafka_2.13-3.1.0.tgz && mv kafka_2.13-3.1.0 kafka
COPY connect-distributed.properties /home/appuser/kafka/config/connect-distributed.properties
CMD KAFKA_OPTS='-Duser.timezone=GMT -Doracle.jdbc.timezoneAsRegion=false' /home/appuser/kafka/bin/connect-distributed.sh /home/appuser/kafka/config/connect-distributed.properties

#jvm.spec = Oracle Corporation, Java HotSpot(TM) 64-Bit Server VM, 17.0.2, 17.0.2+8-LTS-86