#!/bin/bash

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

verify_installed "confluent"
verify_confluent_login  "confluent kafka cluster list"
verify_confluent_details
check_if_continue

# Delete topic in Confluent Cloud
delete_topic kafka-admin-acl-topic

${DIR}/../../ccloud/environment/stop.sh "${PWD}/docker-compose.yml"