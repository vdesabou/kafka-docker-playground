#!/bin/bash

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

verify_installed "ccloud"
if [ -z "$CI" ]
then
     # not running with github actions
     verify_ccloud_login  "ccloud kafka cluster list"
     verify_ccloud_details
     check_if_continue
else
     # running with github actions
     if [ ! -f ../../secrets.properties ]
     then
          logerror "../../secrets.properties is not present!"
          exit 1
     fi
     source ../../secrets.properties > /dev/null 2>&1

     CONFIG_FILE=~/.ccloud/config

     if [ ! -f ${CONFIG_FILE} ]
     then
          logerror "ERROR: ${CONFIG_FILE} is not set"
          exit 1
     fi

     if [ -f /tmp/delta_configs/env.delta ]
     then
          source /tmp/delta_configs/env.delta
     else
          logerror "ERROR: /tmp/delta_configs/env.delta has not been generated"
          exit 1
     fi
     log "##################################################"
     log "Log in to Confluent Cloud"
     log "##################################################"
     ccloud login --save
     log "Use environment $ENVIRONMENT"
     ccloud environment use $ENVIRONMENT
     log "Use cluster $CLUSTER_LKC"
     ccloud kafka cluster use $CLUSTER_LKC
     log "Use api key $CLOUD_KEY"
     ccloud api-key use $CLOUD_KEY --resource $CLUSTER_LKC
fi

set +e

log "Delete connector mysql-source"
curl -X DELETE localhost:8083/connectors/mysql-source
log "Delete connector http-sink"
curl -X DELETE localhost:8083/connectors/http-sink
log "Delete connector elasticsearch-sink"
curl -X DELETE localhost:8083/connectors/elasticsearch-sink

# Delete topic in Confluent Cloud
delete_topic customer-avro
delete_topic mysql-application
delete_topic demo-acl-topic

${DIR}/../../ccloud/environment/stop.sh "${PWD}/docker-compose.ccloud-demo.yml"