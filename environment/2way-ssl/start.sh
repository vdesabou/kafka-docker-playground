#!/bin/bash

set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

verify_docker_and_memory

check_docker_compose_version
check_bash_version
check_playground_version
set_profiles

OLDDIR=$PWD
cd ${OLDDIR}/../../environment/2way-ssl/security
log "🔐 Generate keys and certificates used for SSL"
docker run -u0 --rm -v $PWD:/tmp ${CP_CONNECT_IMAGE}:${CONNECT_TAG} bash -c "/tmp/certs-create.sh > /dev/null 2>&1 && chown -R $(id -u $USER):$(id -g $USER) /tmp/"
cd ${OLDDIR}

ENABLE_DOCKER_COMPOSE_FILE_OVERRIDE=""
DOCKER_COMPOSE_FILE_OVERRIDE=$1
if [ -f "${DOCKER_COMPOSE_FILE_OVERRIDE}" ]
then
  ENABLE_DOCKER_COMPOSE_FILE_OVERRIDE="-f ${DOCKER_COMPOSE_FILE_OVERRIDE}"
  check_arm64_support "${DIR}" "${DOCKER_COMPOSE_FILE_OVERRIDE}"
fi

docker compose -f ../../environment/plaintext/docker-compose.yml -f ../../environment/2way-ssl/docker-compose.yml ${ENABLE_DOCKER_COMPOSE_FILE_OVERRIDE} build
docker compose -f ../../environment/plaintext/docker-compose.yml -f ../../environment/2way-ssl/docker-compose.yml ${ENABLE_DOCKER_COMPOSE_FILE_OVERRIDE} down -v --remove-orphans
docker compose -f ../../environment/plaintext/docker-compose.yml -f ../../environment/2way-ssl/docker-compose.yml ${ENABLE_DOCKER_COMPOSE_FILE_OVERRIDE} ${profile_control_center_command} ${profile_ksqldb_command} ${profile_grafana_command} ${profile_kcat_command} ${profile_conduktor_command} ${profile_kafka_nodes_command} up -d
log "📝 To see the actual properties file, use cli command playground container get-properties -c <container>"
command="source ${DIR}/../../scripts/utils.sh && docker compose -f ${DIR}/../../environment/plaintext/docker-compose.yml -f ${DIR}/../../environment/2way-ssl/docker-compose.yml ${ENABLE_DOCKER_COMPOSE_FILE_OVERRIDE} ${profile_control_center_command} ${profile_ksqldb_command} ${profile_grafana_command} ${profile_kcat_command} ${profile_conduktor_command} ${profile_kafka_nodes_command} up -d"
playground state set run.docker_command "$command"
playground state set run.environment "2way-ssl"
log "✨ If you modify a docker-compose file and want to re-create the container(s), run cli command playground container recreate"


if [ "$#" -ne 0 ]
then
    shift
fi
../../scripts/wait-for-connect-and-controlcenter.sh $@

display_jmx_info