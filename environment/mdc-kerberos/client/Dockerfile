FROM centos
ENV container docker

# 1. Adding Confluent repository
RUN rpm --import https://packages.confluent.io/rpm/5.3/archive.key
COPY confluent.repo /etc/yum.repos.d/confluent.repo
RUN yum clean all

# 2. Install confluent kafka tools:
RUN yum install -y java-1.8.0-openjdk
RUN yum install -y confluent-kafka-2.12
#schema-registry package is required to run kafka-avro-console-producer
RUN yum install -y confluent-schema-registry

# 3. Install Kerberos libaries
RUN yum install -y krb5-workstation krb5-libs

# 4. Copy in required settings for client access to Kafka
COPY consumer-us.properties /etc/kafka/consumer-us.properties
COPY producer-us.properties /etc/kafka/producer-us.properties
COPY command-us.properties /etc/kafka/command-us.properties
COPY consumer-europe.properties /etc/kafka/consumer-europe.properties
COPY producer-europe.properties /etc/kafka/producer-europe.properties
COPY command-europe.properties /etc/kafka/command-europe.properties
COPY client.sasl.jaas.config /etc/kafka/client_jaas.conf

ENV KAFKA_OPTS=-Djava.security.auth.login.config=/etc/kafka/kafka_server_jaas.conf

CMD sleep infinity
