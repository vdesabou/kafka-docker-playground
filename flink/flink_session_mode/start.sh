#!/bin/bash

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
# loading env variables
source ${DIR}/../../scripts/utils.sh


source ${DIR}/../../scripts/flink_download_connectors.sh

docker compose --profile grafana up -d