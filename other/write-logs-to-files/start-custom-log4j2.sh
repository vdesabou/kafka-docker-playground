#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

set +e
if connect_cp_version_greater_than_8
then
     logwarn "CP 8.0 or above should be used as log4j2 is not supported in CP 5/6/7"
     exit 111
fi
set -e 

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.custom-log4j2.yml"

playground container  logs -c connect