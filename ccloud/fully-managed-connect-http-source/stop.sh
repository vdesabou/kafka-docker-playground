#!/bin/bash



DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

docker compose down -f docker-compose.oauth2.yml -v --remove-orphans

maybe_delete_ccloud_environment