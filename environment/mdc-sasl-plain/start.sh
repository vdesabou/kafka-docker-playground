#!/bin/bash

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh
verify_installed "jq"
verify_installed "docker-compose"

DOCKER_COMPOSE_FILE_OVERRIDE=$1
if [ -f "${DOCKER_COMPOSE_FILE_OVERRIDE}" ]
then
  docker-compose -f ../../environment/mdc-plaintext/docker-compose.yml -f ../../environment/mdc-sasl-plain/docker-compose.sasl-plain.yml -f ${DOCKER_COMPOSE_FILE_OVERRIDE} down -v
  docker-compose -f ../../environment/mdc-plaintext/docker-compose.yml -f ../../environment/mdc-sasl-plain/docker-compose.sasl-plain.yml -f ${DOCKER_COMPOSE_FILE_OVERRIDE} up -d
else
  docker-compose -f ../../environment/mdc-plaintext/docker-compose.yml -f ../../environment/mdc-sasl-plain/docker-compose.sasl-plain.yml down -v
  docker-compose -f ../../environment/mdc-plaintext/docker-compose.yml -f ../../environment/mdc-sasl-plain/docker-compose.sasl-plain.yml up -d
fi

shift

../../scripts/wait-for-connect-and-controlcenter.sh connect-us $@
../../scripts/wait-for-connect-and-controlcenter.sh connect-europe $@