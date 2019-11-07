#!/bin/bash

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../ccloud-demo/Utils.sh

verify_installed "ccloud"
verify_installed "confluent"
verify_ccloud_login  "ccloud kafka cluster list"
verify_ccloud_details
check_if_continue

# Delete topic in Confluent Cloud
set +e
delete_topic customer-avro
delete_topic mysql-application

echo "Delete connector mysql-source"
curl -X DELETE localhost:8083/connectors/mysql-source
echo "Delete connector HttpSinkBasicAuth"
curl -X DELETE localhost:8083/connectors/HttpSinkBasicAuth

docker-compose down -v