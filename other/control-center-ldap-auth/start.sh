#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

playground start-environment --environment plaintext --docker-compose-override-file "${PWD}/docker-compose.plaintext.yml"
