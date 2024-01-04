#!/bin/bash



DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

docker compose down -f docker-compose.oauth2.yml -v --remove-orphans

log "Do you want to delete the fully managed connector $connector_name ?"
check_if_continue

playground fully-managed-connector delete --connector $connector_name

maybe_delete_ccloud_environment