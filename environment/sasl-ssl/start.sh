#!/bin/bash

set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

verify_docker_and_memory
verify_installed "docker-compose"

# https://docs.docker.com/compose/profiles/
profile_control_center_command=""
if [ -z "$DISABLE_CONTROL_CENTER" ]
then
  log "🛑 control-center is disabled"
  profile_control_center_command="--profile control-center"
fi

profile_ksqldb_command=""
if [ -z "$DISABLE_KSQLDB" ]
then
  log "🛑 ksqldb is disabled"
  profile_ksqldb_command="--profile ksqldb"
fi

OLDDIR=$PWD

cd ${OLDDIR}/../../environment/sasl-ssl/security

log "🔐 Generate keys and certificates used for SSL"
./certs-create.sh > /dev/null 2>&1
cd ${OLDDIR}/../../environment/sasl-ssl

DOCKER_COMPOSE_FILE_OVERRIDE=$1
if [ -f "${DOCKER_COMPOSE_FILE_OVERRIDE}" ]
then

  docker-compose -f ../../environment/plaintext/docker-compose.yml -f ../../environment/sasl-ssl/docker-compose.yml -f ${DOCKER_COMPOSE_FILE_OVERRIDE} down -v --remove-orphans
  docker-compose -f ../../environment/plaintext/docker-compose.yml -f ../../environment/sasl-ssl/docker-compose.yml -f ${DOCKER_COMPOSE_FILE_OVERRIDE} ${profile_control_center_command} ${profile_ksqldb_command} up -d
else
  docker-compose -f ../../environment/plaintext/docker-compose.yml -f ../../environment/sasl-ssl/docker-compose.yml down -v --remove-orphans
  docker-compose -f ../../environment/plaintext/docker-compose.yml -f ../../environment/sasl-ssl/docker-compose.yml ${profile_control_center_command} ${profile_ksqldb_command} up -d
fi

cd ${OLDDIR}

if [ "$#" -ne 0 ]
then
    shift
fi
../../scripts/wait-for-connect-and-controlcenter.sh $@

display_jmx_info