ARG CP_CONNECT_IMAGE
ARG CONNECT_TAG
FROM ${CP_CONNECT_IMAGE}:${CONNECT_TAG}
USER root
# RUN curl -L https://cdn.azul.com/zulu/bin/zulu17.42.19-ca-jdk17.0.7-linux.x86_64.rpm -o zulu17.42.19-ca-jdk17.0.7-linux.x86_64.rpm && yum install -y zulu17.42.19-ca-jdk17.0.7-linux.x86_64.rpm && alternatives --list && alternatives --set java /usr/lib/jvm/java-17-zulu-openjdk-jdk/bin/java

RUN yum install -y https://cdn.azul.com/zulu/bin/zulu-repo-1.0.0-1.noarch.rpm && yum -y install zulu22-jdk
USER appuser



playground container exec --container connect --root --command "yum install -y https://cdn.azul.com/zulu/bin/zulu-repo-1.0.0-1.noarch.rpm ; yum -y install zulu17-jdk"

playground container exec --container connect --root --command "alternatives --install /usr/bin/java java /usr/lib/jvm/java-zulu17-zulu-openjdk-ca/bin/java 2000"
playground container exec --container connect --root --command "alternatives --set java /usr/lib/jvm/java-zulu17-zulu-openjdk-ca/bin/java"