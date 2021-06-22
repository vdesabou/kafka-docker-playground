#!/bin/bash

set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

verify_docker_and_memory
verify_installed "docker-compose"
check_docker_compose_version

# https://docs.docker.com/compose/profiles/
profile_control_center_command=""
if [ -z "$DISABLE_CONTROL_CENTER" ]
then
  profile_control_center_command="--profile control-center"
else
  log "🛑 control-center is disabled"
fi

DOCKER_COMPOSE_FILE_OVERRIDE=$1
if [ -f "${DOCKER_COMPOSE_FILE_OVERRIDE}" ]
then
  docker-compose -f ../../environment/mdc-plaintext/docker-compose.yml -f ${DOCKER_COMPOSE_FILE_OVERRIDE} down -v --remove-orphans
  docker-compose -f ../../environment/mdc-plaintext/docker-compose.yml -f ${DOCKER_COMPOSE_FILE_OVERRIDE} ${profile_control_center_command} up -d
  log "⚡If you modify a docker-compose file and want to re-create the container(s), use this command:"
  log "⚡source ../../scripts/utils.sh && docker-compose -f ../../environment/mdc-plaintext/docker-compose.yml -f ${DOCKER_COMPOSE_FILE_OVERRIDE} ${profile_control_center_command} up -d"
else
  docker-compose -f ../../environment/mdc-plaintext/docker-compose.yml down -v --remove-orphans
  docker-compose -f ../../environment/mdc-plaintext/docker-compose.yml ${profile_control_center_command} up -d
  log "⚡If you modify a docker-compose file and want to re-create the container(s), use this command:"
  log "⚡source ../../scripts/utils.sh && docker-compose -f ../../environment/mdc-plaintext/docker-compose.yml ${profile_control_center_command} up -d"
fi

if [ "$#" -ne 0 ]
then
    shift
fi
../../scripts/wait-for-connect-and-controlcenter.sh connect-us $@
../../scripts/wait-for-connect-and-controlcenter.sh connect-europe $@