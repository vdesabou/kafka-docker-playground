#!/bin/bash
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if ! version_gt $TAG_BASE "7.3.99"
then
  KRAFT_DOCKER_COMPOSE="docker-compose.yml"
else
  KRAFT_DOCKER_COMPOSE="docker-compose.controller.yml"
fi

DOCKER_COMPOSE_FILE_OVERRIDE=$1
if [ -f "${DOCKER_COMPOSE_FILE_OVERRIDE}" ]
then
  docker-compose -f ../../environment/plaintext/$$KRAFT_DOCKER_COMPOSE -f ${DOCKER_COMPOSE_FILE_OVERRIDE} down -v --remove-orphans
else
  docker-compose -f ../../environment/plaintext/$$KRAFT_DOCKER_COMPOSE down -v --remove-orphans
fi
