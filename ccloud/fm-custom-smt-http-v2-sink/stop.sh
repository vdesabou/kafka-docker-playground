#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

connector_name="HttpSinkV2_$USER"

log "Deleting connector $connector_name"
set +e
playground connector delete --connector "$connector_name"
set -e
