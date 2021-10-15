# 👷‍♂️ Reusables

Below is a collection of *how to* that you can re-use when you build your own reproduction models 

## Producing data

## Consuming data

## Using proxy

## Using specific JDK

WIP

```yml
COPY zulu11.48.21-ca-jdk11.0.11-linux.x86_64.rpm /tmp/zulu11.48.21-ca-jdk11.0.11-linux.x86_64.rpm
RUN yum install -y /tmp/zulu11.48.21-ca-jdk11.0.11-linux.x86_64.rpm
RUN alternatives --remove java /usr/lib/jvm/zulu11/bin/java
```