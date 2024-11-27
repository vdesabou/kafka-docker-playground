#!/bin/bash

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
# loading env variables
source ${DIR}/../../scripts/utils.sh

profile_grafana_command=""
  if [ -z "$ENABLE_JMX_GRAFANA" ]
  then
    log "🛑 Grafana is disabled"
  else
    log "📊 Grafana is enabled"
    profile_grafana_command="--profile grafana"
    playground state set flags.ENABLE_JMX_GRAFANA 1
  fi

source ${DIR}/../../scripts/flink_download_connectors.sh
docker compose ${profile_grafana_command} up -d