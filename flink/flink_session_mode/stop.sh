#!/bin/bash

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"

source ${DIR}/../../scripts/utils.sh

docker-compose --profile grafana down -v --remove-orphans

stop_all "$DIR"