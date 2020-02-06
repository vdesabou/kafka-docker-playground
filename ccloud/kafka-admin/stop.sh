#!/bin/bash

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

verify_installed "ccloud"
verify_ccloud_login  "ccloud kafka cluster list"
verify_ccloud_details
check_if_continue

# Delete topic in Confluent Cloud
delete_topic kafka-admin-acl-topic

docker-compose down -v