#!/bin/bash

set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

set +e
docker rm -f python-ccloud-consumer python-ccloud-producer
set -e

bootstrap_ccloud_environment

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

log "Creating topic in Confluent Cloud (auto.create.topics.enable=false)"
set +e
playground topic delete --topic client_python_$TAG
sleep 3
playground topic create --topic client_python_$TAG
playground topic delete --topic client_python_avro_$TAG
sleep 3
playground topic create --topic client_python_avro_$TAG
set -e

log "Building docker image"
docker build -t vdesabou/python-ccloud-example-docker . > /dev/null 2>&1

log "Starting producer"
docker run --name python-ccloud-producer --rm -v ${DIR}/librdkafka.config:/tmp/librdkafka.config -e TAG=$TAG vdesabou/python-ccloud-example-docker ./producer.py -f /tmp/librdkafka.config -t client_python_$TAG

log "Starting consumer. Logs are in /tmp/result.log"
docker run --name python-ccloud-consumer --rm -v ${DIR}/librdkafka.config:/tmp/librdkafka.config -e TAG=$TAG vdesabou/python-ccloud-example-docker ./consumer.py -f /tmp/librdkafka.config -t client_python_$TAG > /tmp/result.log
cat /tmp/result.log
grep "alice" /tmp/result.log

set +e
docker rm -f python-ccloud-consumer python-ccloud-producer
set -e

log "Starting AVRO producer"
docker run --name python-ccloud-producer --rm -v ${DIR}/librdkafka.config:/tmp/librdkafka.config -e TAG=$TAG vdesabou/python-ccloud-example-docker ./producer.py -f /tmp/librdkafka.config -t client_python_avro_$TAG

log "Starting AVRO consumer. Logs are in /tmp/result.log"
docker run --name python-ccloud-consumer --rm -i -v ${DIR}/librdkafka.config:/tmp/librdkafka.config -e TAG=$TAG vdesabou/python-ccloud-example-docker ./consumer.py -f /tmp/librdkafka.config -t client_python_avro_$TAG > /tmp/result.log
cat /tmp/result.log
grep "alice" /tmp/result.log