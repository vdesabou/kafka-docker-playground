FROM debian:stretch
#Update stretch repositories
RUN sed -i s/deb.debian.org/archive.debian.org/g /etc/apt/sources.list
RUN sed -i 's|security.debian.org|archive.debian.org/|g' /etc/apt/sources.list
RUN sed -i '/stretch-updates/d' /etc/apt/sources.list

RUN apt-get update && apt-get install bc wget default-jdk unzip curl procps -y && \
    if [ "$(dpkg --print-architecture)" = "amd64" ]; then \
    apt-get install -y lib32z1 lib32ncurses5 lib32stdc++6 lib32z1-dev || true; \
    fi && \
    groupadd -r tibgrp -g 433 && \
    useradd -u 431 -r -m -g tibgrp -d /home/tibusr -s /bin/bash -c "TIBCO Docker image user" tibusr && \
    chown -R tibusr:tibgrp /home/tibusr && \
    mkdir /opt/tibco && \
    chown -R tibusr:tibgrp /opt/tibco && \
    mkdir /tmp/install && \
    chown -R tibusr:tibgrp /tmp/install

USER tibusr