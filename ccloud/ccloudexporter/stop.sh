#!/bin/bash

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

verify_installed "confluent"
verify_confluent_login  "confluent kafka cluster list"
check_if_continue

if [ -f api_key_cloud_to_delete ]
then
     log "Deleting API key created for this test"
     confluent api-key delete $(cat api_key_cloud_to_delete)
     rm api_key_cloud_to_delete
fi

set +e
delete_topic ccloudexporter
set -e

maybe_delete_ccloud_environment

docker-compose down -v --remove-orphans