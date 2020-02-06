#!/bin/bash

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

verify_installed "ccloud"
if [ -z "$TRAVIS" ]
then
     # not running with TRAVIS
     verify_ccloud_login  "ccloud kafka cluster list"
     verify_ccloud_details
     check_if_continue
else
     # running with travis
     CONFIG_FILE=~/.ccloud/config

     if [ ! -f ${CONFIG_FILE} ]
     then
          logerror "ERROR: ${CONFIG_FILE} is not set"
          exit 1
     fi

     if [ -f ./delta_configs/env.delta ]
     then
          source ./delta_configs/env.delta
     else
          logerror "ERROR: delta_configs/env.delta has not been generated"
          exit 1
     fi
     log "##################################################"
     log "Log in to Confluent Cloud"
     log "##################################################"

OUTPUT=$(
expect <<END
log_user 1
spawn ccloud login
expect "Email: "
send "$CCLOUD_USER\r";
expect "Password: "
send "$CCLOUD_PASSWORD\r";
expect "Logged in as "
set result $expect_out(buffer)
END
)
     if [[ ! "$OUTPUT" =~ "Logged in as" ]]; then
          logerror "Failed to log into your cluster.  Please check all parameters and run again"
          exit 1
     fi

     log "Using travis cluster"
     ccloud kafka cluster use lkc-6kv2j
fi

# Delete topic in Confluent Cloud
delete_topic customer-avro
delete_topic mysql-application
delete_topic demo-acl-topic

log "Delete connector mysql-source"
curl -X DELETE localhost:8083/connectors/mysql-source
log "Delete connector http-sink"
curl -X DELETE localhost:8083/connectors/http-sink
log "Delete connector elasticsearch-sink"
curl -X DELETE localhost:8083/connectors/elasticsearch-sink

docker-compose down -v