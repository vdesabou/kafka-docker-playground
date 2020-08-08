FROM tibbase:1.0.0

ADD ./TIB_ems-ce_8.5.1_linux_x86_64.zip /tmp/install/

RUN unzip /tmp/install/TIB_ems*.zip -d /tmp/install/tibems/ && \
cd / && \
tar xvfz /tmp/install/tibems/TIB_ems-ce_8.5.1/tar/TIB_ems-ce_8.5.1_linux_x86_64-server.tar.gz && \
tar xvfz /tmp/install/tibems/TIB_ems-ce_8.5.1/tar/TIB_ems-ce_8.5.1_linux_x86_64-samples_src.tar.gz && \
tar xvfz /tmp/install/tibems/TIB_ems-ce_8.5.1/tar/TIB_ems-ce_8.5.1_linux_x86_64-thirdparty.tar.gz && \
tar xvfz /tmp/install/tibems/TIB_ems-ce_8.5.1/tar/TIB_ems-ce_8.5.1_linux_x86_64-java_client.tar.gz && \
rm -rf /tmp/install/tibems /tmp/install/TIB_ems*.zip

EXPOSE 7222

ADD --chown=tibusr:tibgrp ./queues.conf /home/tibusr/
ADD --chown=tibusr:tibgrp ./factories.conf /home/tibusr/

WORKDIR /home/tibusr
ENTRYPOINT ["/opt/tibco/ems/8.5/bin/tibemsd"]