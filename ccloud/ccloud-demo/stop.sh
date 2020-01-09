#!/bin/bash

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

verify_installed "ccloud"
verify_installed "confluent"
verify_ccloud_login  "ccloud kafka cluster list"
verify_ccloud_details
check_if_continue

# Delete topic in Confluent Cloud
set +e
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