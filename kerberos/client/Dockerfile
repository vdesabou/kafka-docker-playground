FROM centos
MAINTAINER d.gasparina@gmail.com
ENV container docker

# 1. Adding Confluent repository
RUN rpm --import https://packages.confluent.io/rpm/5.3/archive.key
COPY confluent.repo /etc/yum.repos.d/confluent.repo
RUN yum clean all

# 2. Install confluent kafka tools:
RUN yum install -y java-1.8.0-openjdk
RUN yum install -y confluent-kafka-2.12
#schema-registry package is rquiterd to run kafka-avro-console-producer
RUN yum install -y confluent-schema-registry

# 3. Install Kerberos libaries
RUN yum install -y krb5-workstation krb5-libs

# 4. Copy in required settings for client access to Kafka
COPY consumer.properties /etc/kafka/consumer.properties
COPY producer.properties /etc/kafka/producer.properties
COPY command.properties /etc/kafka/command.properties
COPY client.sasl.jaas.config /etc/kafka/client_jaas.conf

ENV KAFKA_OPTS=-Djava.security.auth.login.config=/etc/kafka/kafka_server_jaas.conf

CMD sleep infinity
