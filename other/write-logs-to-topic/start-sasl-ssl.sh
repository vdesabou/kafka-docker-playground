#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

playground start-environment --environment sasl-ssl --docker-compose-override-file "${PWD}/docker-compose.sasl-ssl.yml"

playground topic consume --topic connect-logs --tail