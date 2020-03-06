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

log "Building docker image"
docker build -t vdesabou/dotnet-example-docker .

log "Starting producer"
docker run -v ${DIR}/librdkafka.config:/tmp/librdkafka.config vdesabou/dotnet-example-docker produce test1 /tmp/librdkafka.config

log "Starting consumer"
docker run -v ${DIR}/librdkafka.config:/tmp/librdkafka.config vdesabou/dotnet-example-docker consume test1 /tmp/librdkafka.config