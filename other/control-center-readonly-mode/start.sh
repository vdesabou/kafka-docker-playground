#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

JAAS_CONFIG_FILE="/tmp/jaas_config.file"
if version_gt $TAG_BASE "7.9.9"; then
  export JAAS_CONFIG_FILE="/tmp/jaas_config_8_plus.file"
fi

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.yml"
