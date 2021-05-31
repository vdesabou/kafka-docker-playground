#!/bin/bash

set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

verify_docker_and_memory
verify_installed "docker-compose"

DOCKER_COMPOSE_FILE_OVERRIDE=$1
if [ -f "${DOCKER_COMPOSE_FILE_OVERRIDE}" ]
then

  docker-compose -f ../../environment/plaintext/docker-compose.yml -f ../../environment/sasl-plain/docker-compose.yml -f ../../environment/ldap-sasl-plain/docker-compose.yml -f ${DOCKER_COMPOSE_FILE_OVERRIDE} down -v --remove-orphans
  docker-compose -f ../../environment/plaintext/docker-compose.yml -f ../../environment/sasl-plain/docker-compose.yml -f ../../environment/ldap-sasl-plain/docker-compose.yml -f ${DOCKER_COMPOSE_FILE_OVERRIDE} up -d
else
  docker-compose -f ../../environment/plaintext/docker-compose.yml -f ../../environment/sasl-plain/docker-compose.yml -f ../../environment/ldap-sasl-plain/docker-compose.yml down -v --remove-orphans
  docker-compose -f ../../environment/plaintext/docker-compose.yml -f ../../environment/sasl-plain/docker-compose.yml -f ../../environment/ldap-sasl-plain/docker-compose.yml up -d
fi

if [ "$#" -ne 0 ]
then
    shift
fi
../../scripts/wait-for-connect-and-controlcenter.sh $@