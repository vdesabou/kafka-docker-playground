#!/bin/bash

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
echo "Pops ${DIR}"
source ${DIR}/../../scripts/utils.sh

docker-compose down -v --remove-orphans

stop_all "$DIR"