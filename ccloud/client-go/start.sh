#!/bin/bash

set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

set +e
docker rm -f go-ccloud-consumer go-ccloud-producer
set -e

bootstrap_ccloud_environment

if [ -f ${DIR}/../../.ccloud/env.delta ]
then
     source ${DIR}/../../.ccloud/env.delta
else
     logerror "ERROR: ${DIR}/../../.ccloud/env.delta has not been generated"
     exit 1
fi

# generate kafka-admin.properties config
sed -e "s|:BOOTSTRAP_SERVERS:|$BOOTSTRAP_SERVERS|g" \
    -e "s|:CLOUD_KEY:|$CLOUD_KEY|g" \
    -e "s|:CLOUD_SECRET:|$CLOUD_SECRET|g" \
    ${DIR}/librdkafka.config.template > ${DIR}/librdkafka.config

log "Creating topic in Confluent Cloud (auto.create.topics.enable=false)"
set +e
playground topic delete --topic client_go_$TAG
sleep 3
playground topic create --topic client_go_$TAG
set -e

log "Building docker image"
docker build -t vdesabou/go-ccloud-example-docker . > /dev/null 2>&1

log "Starting producer"
docker run --name go-ccloud-producer -v ${DIR}/librdkafka.config:/tmp/librdkafka.config -e TAG=$TAG vdesabou/go-ccloud-example-docker ./producer -f /tmp/librdkafka.config -t client_go_$TAG

log "Starting consumer. Logs are in /tmp/result.log"
docker run --name go-ccloud-consumer -v ${DIR}/librdkafka.config:/tmp/librdkafka.config -e TAG=$TAG vdesabou/go-ccloud-example-docker ./consumer -f /tmp/librdkafka.config -t client_go_$TAG > /tmp/result.log 2>&1 &
sleep 5
cat /tmp/result.log
grep "alice" /tmp/result.log