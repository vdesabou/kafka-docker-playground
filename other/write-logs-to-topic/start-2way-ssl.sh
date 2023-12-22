#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

playground start-environment --environment 2way-ssl --docker-compose-override-file "${PWD}/docker-compose.2way-ssl.yml"

playground topic consume --topic connect-logs --tail