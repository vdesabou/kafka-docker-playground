#!/bin/bash

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

verify_installed "ccloud"
verify_ccloud_login  "ccloud kafka cluster list"
verify_ccloud_details
check_if_continue

if [ -f api_key_cloud_to_delete ]
then
     log "Deleting API key created for this test"
     ccloud api-key delete $(cat api_key_cloud_to_delete)
     rm api_key_cloud_to_delete
fi

set +e
delete_topic ccloudexporter
set -e

docker-compose down -v