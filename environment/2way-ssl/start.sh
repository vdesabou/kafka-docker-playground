#!/bin/bash

set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

verify_installed "docker-compose"
verify_installed "keytool"

OLDDIR=$PWD

cd ${OLDDIR}/../../environment/2way-ssl/security

log "Generate keys and certificates used for SSL"
verify_installed "keytool"
if [ ! -f $(find $JAVA_HOME -follow -name cacerts) ]
then
  logerror "ERROR: Cannot find JAVA cacerts"
  exit 1
fi

./certs-create.sh > /dev/null 2>&1

cd ${OLDDIR}/../../environment/2way-ssl

DOCKER_COMPOSE_FILE_OVERRIDE=$1
if [ -f "${DOCKER_COMPOSE_FILE_OVERRIDE}" ]
then

  docker-compose -f ../../environment/plaintext/docker-compose.yml -f ../../environment/2way-ssl/docker-compose.yml -f ${DOCKER_COMPOSE_FILE_OVERRIDE} down -v
  docker-compose -f ../../environment/plaintext/docker-compose.yml -f ../../environment/2way-ssl/docker-compose.yml -f ${DOCKER_COMPOSE_FILE_OVERRIDE} up -d
else
  docker-compose -f ../../environment/plaintext/docker-compose.yml -f ../../environment/2way-ssl/docker-compose.yml down -v
  docker-compose -f ../../environment/plaintext/docker-compose.yml -f ../../environment/2way-ssl/docker-compose.yml up -d
fi

cd ${OLDDIR}

if [ "$#" -ne 0 ]
then
    shift
fi
../../scripts/wait-for-connect-and-controlcenter.sh $@