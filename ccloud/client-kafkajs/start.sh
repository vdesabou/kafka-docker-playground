#!/bin/bash

set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

set +e
docker rm -f kafkajs-ccloud-consumer kafkajs-ccloud-producer
set -e

bootstrap_ccloud_environment

if [ -f ${DIR}/../../.ccloud/env.delta ]
then
     source ${DIR}/../../.ccloud/env.delta
else
     logerror "ERROR: ${DIR}/../../.ccloud/env.delta has not been generated"
     exit 1
fi

# generate producer.js
sed -e "s|:BOOTSTRAP_SERVERS:|$BOOTSTRAP_SERVERS|g" \
    -e "s|:CLOUD_KEY:|$CLOUD_KEY|g" \
    -e "s|:CLOUD_SECRET:|$CLOUD_SECRET|g" \
    ${DIR}/producer-template.js > ${DIR}/producer.js
# generate consumer.js
sed -e "s|:BOOTSTRAP_SERVERS:|$BOOTSTRAP_SERVERS|g" \
    -e "s|:CLOUD_KEY:|$CLOUD_KEY|g" \
    -e "s|:CLOUD_SECRET:|$CLOUD_SECRET|g" \
    ${DIR}/consumer-template.js > ${DIR}/consumer.js

log "Creating topic in Confluent Cloud (auto.create.topics.enable=false)"
set +e
playground topic delete --topic client_kafkajs_$TAG
sleep 3
playground topic create --topic client_kafkajs_$TAG
set -e

log "Building docker image"
docker build -t vdesabou/kafkajs-ccloud-example-docker . > /dev/null 2>&1

log "Starting producer"
docker run -i --name kafkajs-ccloud-producer -e TAG=$TAG vdesabou/kafkajs-ccloud-example-docker node /usr/src/app/producer.js client_kafkajs_$TAG > /dev/null 2>&1 &

sleep 3

log "Starting consumer. Logs are in /tmp/result.log"
docker run -i --name kafkajs-ccloud-consumer -e TAG=$TAG vdesabou/kafkajs-ccloud-example-docker node /usr/src/app/consumer.js client_kafkajs_$TAG > /tmp/result.log 2>&1 &
sleep 15
cat /tmp/result.log
grep "value-" /tmp/result.log