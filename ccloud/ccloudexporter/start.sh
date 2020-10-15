#!/bin/bash

set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

verify_installed "ccloud"
check_ccloud_version 1.7.0 || exit 1
verify_ccloud_login  "ccloud kafka cluster list"
verify_ccloud_details
check_if_continue

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

# Offer to refresh images
ret=$(docker images --format "{{.Repository}}|{{.Tag}}|{{.CreatedSince}}" | grep dabz/ccloudexporter | cut -d "|" -f 3)
if [ "$ret" != "" ]
then
  log "Your dabz/ccloudexporter Docker images was pulled $ret"
  read -p "Do you want to download new one? (y/n)?" choice
  case "$choice" in
  y|Y )
    docker pull dabz/ccloudexporter:latest
  ;;
  n|N ) ;;
  * ) logerror "ERROR: invalid response!";exit 1;;
  esac
fi

export CCLOUD_CLUSTER=$(ccloud prompt -f "%k")

# generate config.yml
sed -e "s|:CCLOUD_CLUSTER:|$CCLOUD_CLUSTER|g" \
    ${DIR}/config-template.yml > ${DIR}/config.yml

set +e
create_topic ccloudexporter
set -e

log "Create API key and secret with cloud resource for Metrics API"
log "ccloud api-key create --resource cloud"
OUTPUT=$(ccloud api-key create --resource cloud)
export API_KEY_CLOUD=$(echo "$OUTPUT" | grep '| API Key' | awk '{print $5;}')
export API_SECRET_CLOUD=$(echo "$OUTPUT" | grep '| Secret' | awk '{print $4;}')

echo "$API_KEY_CLOUD" > api_key_cloud_to_delete

docker-compose down -v
docker-compose up -d

log "Producing data to ccloudexporter topic"
docker exec tools bash -c "kafka-producer-perf-test --throughput 1000 --num-records 60000 --topic ccloudexporter --record-size 100 --producer.config /tmp/config"

log "Consuming data from ccloudexporter topic"
docker exec -e BOOTSTRAP_SERVERS=$BOOTSTRAP_SERVERS tools bash -c "kafka-consumer-perf-test --messages 60000 --topic ccloudexporter --consumer.config /tmp/config --broker-list $BOOTSTRAP_SERVERS"

log "Open a brower and visit http://127.0.0.1:3000 (login/password is admin/admin)"