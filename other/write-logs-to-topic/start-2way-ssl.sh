#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

${DIR}/../../environment/2way-ssl/start.sh "${PWD}/docker-compose.2way-ssl.yml"

playground topic consume --topic connect-logs --tail