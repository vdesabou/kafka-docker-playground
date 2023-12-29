#!/bin/bash

set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

set +e
docker rm -f dotnet-ccloud-consumer dotnet-ccloud-producer
set -e

CORE_DOT_VERSION=${1:-3.1}

bootstrap_ccloud_environment

if [ -f ${DIR}/../../.ccloud/env.delta ]
then
     source ${DIR}/../../.ccloud/env.delta
else
     logerror "ERROR: ${DIR}/../../.ccloud/env.delta has not been generated"
     exit 1
fi

# generate librdkafka.config config
sed -e "s|:BOOTSTRAP_SERVERS:|$BOOTSTRAP_SERVERS|g" \
    -e "s|:CLOUD_KEY:|$CLOUD_KEY|g" \
    -e "s|:CLOUD_SECRET:|$CLOUD_SECRET|g" \
    ${DIR}/librdkafka.config.template > ${DIR}/librdkafka.config


if [[ "$CORE_DOT_VERSION" = "3.1" ]]
then
     log "Using .NET Core version 3.1"
     CORE_RUNTIME_TAG="3.1.2-bionic"
     CORE_SDK_TAG="3.1.102-bionic"
     CSPROJ_FILE="CCloud3.1.csproj"
else
     log "Using .NET Core version 2.2"
     CORE_RUNTIME_TAG="2.2-stretch-slim"
     CORE_SDK_TAG="2.2-stretch"
     CSPROJ_FILE="CCloud2.2.csproj"
fi

log "Creating topic in Confluent Cloud (auto.create.topics.enable=false)"
set +e
playground topic delete --topic client_dotnet_$TAG
sleep 3
playground topic create --topic client_dotnet_$TAG
set -e

log "Building docker image"
docker build --build-arg CORE_RUNTIME_TAG=$CORE_RUNTIME_TAG --build-arg CORE_SDK_TAG=$CORE_SDK_TAG --build-arg CSPROJ_FILE=$CSPROJ_FILE -t vdesabou/dotnet-ccloud-example-docker . > /dev/null 2>&1

log "Starting producer"
docker run --name dotnet-ccloud-producer --sysctl net.ipv4.tcp_keepalive_time=60 --sysctl net.ipv4.tcp_keepalive_intvl=30 -v ${DIR}/librdkafka.config:/tmp/librdkafka.config -e TAG=$TAG vdesabou/dotnet-ccloud-example-docker produce client_dotnet_$TAG /tmp/librdkafka.config

# docker run -v ${DIR}/librdkafka.config:/tmp/librdkafka.config vdesabou/dotnet-ccloud-example-docker produce client_dotnet_$TAG /tmp/librdkafka.config

# log "Starting producer with curl certificate https://curl.haxx.se/ca/cacert.pem"
# docker run -v ${DIR}/librdkafka.config:/tmp/librdkafka.config -v ${DIR}/curl-cacert.txt:/tmp/cacert.pem vdesabou/dotnet-ccloud-example-docker produce client_dotnet_$TAG /tmp/librdkafka.config /tmp/cacert.pem
# log "Starting producer with let's encrypt certificate https://letsencrypt.org/certificates/"
# docker run -v ${DIR}/librdkafka.config:/tmp/librdkafka.config -v ${DIR}/letsencrypt-cacert.txt:/tmp/cacert.pem vdesabou/dotnet-ccloud-example-docker produce client_dotnet_$TAG /tmp/librdkafka.config /tmp/cacert.pem

log "Starting consumer. Logs are in /tmp/result.log"
docker run --name dotnet-ccloud-consumer --sysctl net.ipv4.tcp_keepalive_time=60 --sysctl net.ipv4.tcp_keepalive_intvl=30 -v ${DIR}/librdkafka.config:/tmp/librdkafka.config -e TAG=$TAG vdesabou/dotnet-ccloud-example-docker consume client_dotnet_$TAG /tmp/librdkafka.config > /tmp/result.log 2>&1 &

sleep 5
cat /tmp/result.log
grep "alice" /tmp/result.log

# docker run -v ${DIR}/librdkafka.config:/tmp/librdkafka.config vdesabou/dotnet-ccloud-example-docker consume client_dotnet_$TAG /tmp/librdkafka.config