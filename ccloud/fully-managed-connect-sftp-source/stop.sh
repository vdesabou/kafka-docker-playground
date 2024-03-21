#!/bin/bash



DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

docker compose -f docker-compose.oauth2.yml down -v --remove-orphans


maybe_delete_ccloud_environment