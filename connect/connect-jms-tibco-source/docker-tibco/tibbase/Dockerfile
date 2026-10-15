# debian:stretch is no longer installable: archive.debian.org returns 404 on some stretch security packages
# jammy (not the default noble) because tar fails with "Function not implemented" on the EMS archive under noble
FROM eclipse-temurin:8-jdk-jammy

RUN apt-get update && apt-get install -y bc wget unzip curl procps && \
    rm -rf /var/lib/apt/lists/* && \
    groupadd -r tibgrp -g 433 && \
    useradd -u 431 -r -m -g tibgrp -d /home/tibusr -s /bin/bash -c "TIBCO Docker image user" tibusr && \
    chown -R tibusr:tibgrp /home/tibusr && \
    mkdir /opt/tibco && \
    chown -R tibusr:tibgrp /opt/tibco && \
    mkdir /tmp/install && \
    chown -R tibusr:tibgrp /tmp/install

USER tibusr
