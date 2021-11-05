#!/bin/bash

set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

CONFIG_FILE=~/.confluent/config

if [ ! -f ${CONFIG_FILE} ]
then
     logerror "ERROR: ${CONFIG_FILE} is not set"
     exit 1
fi

${DIR}/../ccloud-demo/confluent-generate-env-vars.sh ${CONFIG_FILE}

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
    -e "s|:SCHEMA_REGISTRY_URL:|$SCHEMA_REGISTRY_URL|g" \
    -e "s|:SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO:|$SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO|g" \
    ${DIR}/librdkafka.config.template > ${DIR}/librdkafka.config

log "Building docker image"
docker build -t vdesabou/python-ccloud-example-docker .

log "Starting producer"
docker run --rm -v ${DIR}/librdkafka.config:/tmp/librdkafka.config vdesabou/python-ccloud-example-docker ./producer.py -f /tmp/librdkafka.config -t testpython


log "Starting consumer (use CTLR+c to stop)"
docker run --rm -it -v ${DIR}/librdkafka.config:/tmp/librdkafka.config vdesabou/python-ccloud-example-docker ./consumer.py -f /tmp/librdkafka.config -t testpython

log "Starting AVRO producer"
docker run --rm -v ${DIR}/librdkafka.config:/tmp/librdkafka.config vdesabou/python-ccloud-example-docker ./producer.py -f /tmp/librdkafka.config -t testpythonavro


log "Starting AVRO consumer (use CTLR+c to stop)"
docker run --rm -it -v ${DIR}/librdkafka.config:/tmp/librdkafka.config vdesabou/python-ccloud-example-docker ./consumer.py -f /tmp/librdkafka.config -t testpythonavro