FROM debian:stretch

RUN apt-get update && apt-get install bc wget default-jdk unzip curl lib32z1 bc lib32ncurses5 lib32stdc++6 lib32z1 lib32z1-dev -y &&\ 
	groupadd -r tibgrp -g 433 && \
	useradd -u 431 -r -m -g tibgrp -d /home/tibusr -s /bin/bash -c "TIBCO Docker image user" tibusr && \
	chown -R tibusr:tibgrp /home/tibusr && \
	mkdir /opt/tibco && \
	chown -R tibusr:tibgrp /opt/tibco && \
	mkdir /tmp/install && \
	chown -R tibusr:tibgrp /tmp/install
	
USER tibusr	