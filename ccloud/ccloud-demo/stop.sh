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
delete_topic demo-acl-topic

echo -e "\033[0;33mDelete connector mysql-source\033[0m"
curl -X DELETE localhost:8083/connectors/mysql-source
echo -e "\033[0;33mDelete connector http-sink\033[0m"
curl -X DELETE localhost:8083/connectors/http-sink
echo -e "\033[0;33mDelete connector elasticsearch-sink\033[0m"
curl -X DELETE localhost:8083/connectors/elasticsearch-sink

docker-compose down -v