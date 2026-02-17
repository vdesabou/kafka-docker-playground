FROM --platform=linux/amd64 icr.io/ibm-messaging/mq:9.3.2.0-r2
USER root
RUN curl -o zulu17.32.13-ca-jdk17.0.2-linux.x86_64.rpm https://cdn.azul.com/zulu/bin/zulu17.32.13-ca-jdk17.0.2-linux.x86_64.rpm && rpm -i zulu17.32.13-ca-jdk17.0.2-linux.x86_64.rpm  && alternatives --set java /usr/lib/jvm/zulu-17/bin/java
RUN (microdnf install -y unzip || yum -y install unzip) \
	&& (microdnf clean all || yum clean all)
USER 1001

RUN cd /mnt && rm -rf confluent && curl -O http://packages.confluent.io/archive/8.1/confluent-8.1.0.zip && unzip confluent-8.1.0.zip && mv confluent-8.1.0 confluent
RUN cd /mnt && curl -o confluentinc-kafka-connect-ibmmq-13.0.5.zip https://hub-downloads.confluent.io/api/plugins/confluentinc/kafka-connect-ibmmq/versions/13.0.5/confluentinc-kafka-connect-ibmmq-13.0.5.zip && unzip confluentinc-kafka-connect-ibmmq-13.0.5.zip && mv confluentinc-kafka-connect-ibmmq-13.0.5 confluentinc-kafka-connect-ibmmq
COPY connect-distributed.properties /mnt/confluent/config/connect-distributed.properties 
COPY connect-log4j2.yaml /mnt/confluent/etc/kafka/connect-log4j2.yaml