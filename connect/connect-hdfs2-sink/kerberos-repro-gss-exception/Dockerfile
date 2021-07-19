FROM vdesabou/kafka-docker-playground-connect:5.4.0-1-ubi8
COPY jdk-8u201-linux-x64.rpm /tmp/
RUN microdnf install yum \
    && yum -y install /tmp/jdk-8u201-linux-x64.rpm && alternatives --remove java /usr/lib/jvm/zulu-8/jre/bin/java \
    && rm -f /tmp/jdk-8u201-linux-x64.rpm \