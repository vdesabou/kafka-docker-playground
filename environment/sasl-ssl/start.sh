#!/bin/bash

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

verify_installed "docker-compose"
verify_installed "keytool"

OLDDIR=$PWD

cd ${OLDDIR}/../../environment/sasl-ssl/security

log "Generate keys and certificates used for SSL"
./certs-create.sh > /dev/null 2>&1

cd ${OLDDIR}/../../environment/sasl-ssl

DOCKER_COMPOSE_FILE_OVERRIDE=$1
if [ -f "${DOCKER_COMPOSE_FILE_OVERRIDE}" ]
then

  docker-compose -f ../../environment/sasl-ssl/docker-compose.yml -f ${DOCKER_COMPOSE_FILE_OVERRIDE} down -v
  docker-compose -f ../../environment/sasl-ssl/docker-compose.yml -f ${DOCKER_COMPOSE_FILE_OVERRIDE} up -d
else
  docker-compose -f ../../environment/sasl-ssl/docker-compose.yml down -v
  docker-compose -f ../../environment/sasl-ssl/docker-compose.yml up -d
fi

cd ${OLDDIR}

shift
../../scripts/wait-for-connect-and-controlcenter.sh $@