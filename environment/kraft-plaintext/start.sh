#!/bin/bash

set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if ! version_gt $TAG_BASE "6.1.99"; then
    logwarn "WARN: KRaft (KIP-500) is available since CP 6.2 only"
    exit 111
fi

verify_docker_and_memory

check_docker_compose_version
check_bash_version
check_playground_versionset_profiles

ENABLE_DOCKER_COMPOSE_FILE_OVERRIDE=""
DOCKER_COMPOSE_FILE_OVERRIDE=$1
if [ -f "${DOCKER_COMPOSE_FILE_OVERRIDE}" ]
then
  ENABLE_DOCKER_COMPOSE_FILE_OVERRIDE="-f ${DOCKER_COMPOSE_FILE_OVERRIDE}"
  check_arm64_support "${DIR}" "${DOCKER_COMPOSE_FILE_OVERRIDE}"
fi

if ! version_gt $TAG_BASE "7.3.99"
then
  KRAFT_DOCKER_COMPOSE="docker-compose.yml"
else
  KRAFT_DOCKER_COMPOSE="docker-compose.controller.yml"
fi

docker compose -f ../../environment/plaintext/docker-compose.yml -f ../../environment/kraft-plaintext/$KRAFT_DOCKER_COMPOSE ${ENABLE_DOCKER_COMPOSE_FILE_OVERRIDE} build
docker compose -f ../../environment/plaintext/docker-compose.yml -f ../../environment/kraft-plaintext/$KRAFT_DOCKER_COMPOSE ${ENABLE_DOCKER_COMPOSE_FILE_OVERRIDE} down -v --remove-orphans
docker compose -f ../../environment/plaintext/docker-compose.yml -f ../../environment/kraft-plaintext/$KRAFT_DOCKER_COMPOSE ${ENABLE_DOCKER_COMPOSE_FILE_OVERRIDE} ${profile_control_center_command} ${profile_ksqldb_command} ${profile_grafana_command} ${profile_kcat_command} up -d
log "📝 To see the actual properties file, use cli command playground container get-properties -c <container>"
command="source ${DIR}/../../scripts/utils.sh && docker compose -f ${DIR}/../../environment/plaintext/docker-compose.yml -f ${DIR}/../../environment/kraft-plaintext/$KRAFT_DOCKER_COMPOSE ${ENABLE_DOCKER_COMPOSE_FILE_OVERRIDE} ${profile_control_center_command} ${profile_ksqldb_command} ${profile_grafana_command} ${profile_kcat_command} up -d"
playground state set run.docker_command "$command"
playground state set run.environment "kraft-plaintext"
log "✨ If you modify a docker-compose file and want to re-create the container(s), run cli command playground container recreate"


if [ "$#" -ne 0 ]
then
    shift
fi
../../scripts/wait-for-connect-and-controlcenter.sh $@

display_jmx_info