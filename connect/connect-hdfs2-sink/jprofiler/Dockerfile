ARG TAG_BASE
FROM ${CP_CONNECT_IMAGE}:${TAG_BASE}
RUN rm -rf /tmp/jprofiler_linux_12_0_2 && wget https://download-gcdn.ej-technologies.com/jprofiler/jprofiler_linux_12_0_2.tar.gz -P /tmp/ && \
  cd /tmp && tar xvfz jprofiler_linux_12_0_2.tar.gz && \
  rm /tmp/jprofiler_linux_12_0_2.tar.gz
EXPOSE 8849