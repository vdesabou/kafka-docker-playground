#!/bin/bash

set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

verify_docker_and_memory

check_docker_compose_version
check_bash_version
check_playground_version

nb_connect_services=0
ENABLE_DOCKER_COMPOSE_FILE_OVERRIDE=""
DOCKER_COMPOSE_FILE_OVERRIDE=$1
if [ -f "${DOCKER_COMPOSE_FILE_OVERRIDE}" ]
then
  ENABLE_DOCKER_COMPOSE_FILE_OVERRIDE="-f ${DOCKER_COMPOSE_FILE_OVERRIDE}"
  set +e
  nb_connect_services=$(egrep -c "connect[0-9]+:" ${DOCKER_COMPOSE_FILE_OVERRIDE})
  set -e
  check_arm64_support "${DIR}" "${DOCKER_COMPOSE_FILE_OVERRIDE}"
fi
set_profiles

docker compose -f ../../environment/plaintext/docker-compose.yml -f ../../environment/sasl-plain/docker-compose.yml ${ENABLE_DOCKER_COMPOSE_FILE_OVERRIDE} build
docker compose -f ../../environment/plaintext/docker-compose.yml -f ../../environment/sasl-plain/docker-compose.yml ${ENABLE_DOCKER_COMPOSE_FILE_OVERRIDE} down -v --remove-orphans
docker compose -f ../../environment/plaintext/docker-compose.yml -f ../../environment/sasl-plain/docker-compose.yml ${ENABLE_DOCKER_COMPOSE_FILE_OVERRIDE} ${profile_control_center_command} ${profile_ksqldb_command} ${profile_grafana_command} ${profile_conduktor_command} ${profile_kafka_nodes_command} ${profile_connect_nodes_command} up -d --quiet-pull
log "📝 To see the actual properties file, use cli command 'playground container get-properties -c <container>'"
command="source ${DIR}/../../scripts/utils.sh && docker compose -f ${DIR}/../../environment/plaintext/docker-compose.yml -f ${DIR}/../../environment/sasl-plain/docker-compose.yml ${ENABLE_DOCKER_COMPOSE_FILE_OVERRIDE} ${profile_control_center_command} ${profile_ksqldb_command} ${profile_grafana_command} ${profile_conduktor_command} ${profile_kafka_nodes_command} ${profile_connect_nodes_command} up -d --quiet-pull"
playground state set run.docker_command "$command"
playground state set run.environment "sasl-plain"
log "✨ If you modify a docker-compose file and want to re-create the container(s), run cli command 'playground container recreate'"



wait_container_ready

display_jmx_info