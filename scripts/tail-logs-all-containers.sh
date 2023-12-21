#!/bin/bash

IGNORE_CHECK_FOR_DOCKER_COMPOSE=true
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../scripts/utils.sh

docker_command=$(playground state get run.docker_command)
echo "$docker_command" > /tmp/tmp

sed -e "s|up -d|logs --tail=100 -f|g" \
    /tmp/tmp > /tmp/playground-command-debugging

bash /tmp/playground-command-debugging
