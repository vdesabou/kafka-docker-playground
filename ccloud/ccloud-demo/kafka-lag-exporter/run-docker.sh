#!/usr/bin/env bash

DIR="$(cd "$(dirname "$0")" && pwd)"

# If you want to connect to a Kafka host on your local machine you can use host networking mode with `--network="host"`.
# Note that this will only work on Linux.
docker run -p 8000:8000 \
    -v $DIR:/opt/docker/conf/ \
    lightbend/kafka-lag-exporter:0.6.6 \
    /opt/docker/bin/kafka-lag-exporter \
    -Dconfig.file=/opt/docker/conf/application.conf \
    -Dlogback.configurationFile=/opt/docker/conf/logback.xml