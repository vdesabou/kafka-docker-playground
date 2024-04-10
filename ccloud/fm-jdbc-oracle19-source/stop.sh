#!/bin/bash



DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

export ORACLE_IMAGE="oracle/database:19.3.0-ee"

docker compose down -v --remove-orphans


maybe_delete_ccloud_environment
