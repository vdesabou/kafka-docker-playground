#!/bin/bash

set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

CONFIG_FILE=~/.ccloud/config

if [ ! -f ${CONFIG_FILE} ]
then
     logerror "ERROR: ${CONFIG_FILE} is not set"
     exit 1
fi

CORE_DOT_VERSION=${1:-2.1}

${DIR}/../ccloud-demo/ccloud-generate-env-vars.sh ${CONFIG_FILE}

if [ -f /tmp/delta_configs/env.delta ]
then
     source /tmp/delta_configs/env.delta
else
     logerror "ERROR: /tmp/delta_configs/env.delta has not been generated"
     exit 1
fi

# generate kafka-admin.properties config
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
     CSPROJ_FILE="CCloud2.1.csproj"
fi

log "Building docker image"
docker build --build-arg CORE_RUNTIME_TAG=$CORE_RUNTIME_TAG --build-arg CORE_SDK_TAG=$CORE_SDK_TAG --build-arg CSPROJ_FILE=$CSPROJ_FILE -t vdesabou/dotnet-ccloud-example-docker .

log "Starting producer"
docker run -v ${DIR}/librdkafka.config:/tmp/librdkafka.config vdesabou/dotnet-ccloud-example-docker produce test1 /tmp/librdkafka.config

# log "Starting producer with curl certificate https://curl.haxx.se/ca/cacert.pem"
# docker run -v ${DIR}/librdkafka.config:/tmp/librdkafka.config -v ${DIR}/curl-cacert.txt:/tmp/cacert.pem vdesabou/dotnet-ccloud-example-docker produce test1 /tmp/librdkafka.config /tmp/cacert.pem
# log "Starting producer with let's encrypt certificate https://letsencrypt.org/certificates/"
# docker run -v ${DIR}/librdkafka.config:/tmp/librdkafka.config -v ${DIR}/letsencrypt-cacert.txt:/tmp/cacert.pem vdesabou/dotnet-ccloud-example-docker produce test1 /tmp/librdkafka.config /tmp/cacert.pem

log "Starting consumer"
docker run -v ${DIR}/librdkafka.config:/tmp/librdkafka.config vdesabou/dotnet-ccloud-example-docker consume test1 /tmp/librdkafka.config