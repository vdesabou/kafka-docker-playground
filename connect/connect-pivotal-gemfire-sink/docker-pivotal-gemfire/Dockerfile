# LICENSE GPL 2.0
ARG PIVOTAL_GEMFIRE_VERSION
#Set the base image :
FROM ubuntu:16.04

#Set workdir :
WORKDIR /opt/pivotal

RUN apt-get update && apt-get install -y wget

#Set permissions to gemfire directory to perform operations :
RUN chmod 777 /opt/pivotal

RUN apt-get update && \
    apt-get install -y openjdk-8-jdk

RUN ln -s /usr/lib/jvm/java-8-openjdk-amd64 current_java
RUN apt-get install -y unzip zip

#Add gemfire installation file
ADD ./pivotal-gemfire.tgz /opt/pivotal/

#Set the username to root :
USER root

#Setup environment variables :
ENV JAVA_HOME /opt/pivotal/current_java
ENV PATH $PATH:/opt/pivotal/current_java:/opt/pivotal/current_java/bin:/opt/pivotal/pivotal-gemfire-9.10.2/bin
ENV GEMFIRE /opt/pivotal/pivotal-gemfire-9.10.2
ENV GF_JAVA /opt/pivotal/current_java/bin/java

#classpath setting
ENV CLASSPATH $GEMFIRE/lib/geode-dependencies.jar:$GEMFIRE/lib/gfsh-dependencies.jar:/opt/pivotal/workdir/classes:$CLASSPATH

#COPY the start scripts into container
COPY workdir /opt/pivotal/workdir
RUN chmod +x /opt/pivotal/workdir/*.sh

# Default ports:
# RMI/JMX 1099
# REST 8080
# PULSE 7070
# LOCATOR 10334
# CACHESERVER 40404
# UDP port: 53160
EXPOSE  8080 10334 40404 40405 1099 7070

# SET VOLUME directory
VOLUME ["/opt/pivotal/workdir/storage"]

#ReSet workdir :
WORKDIR /opt/pivotal/workdir

CMD sleep infinity