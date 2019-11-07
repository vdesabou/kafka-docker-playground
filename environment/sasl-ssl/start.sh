#!/bin/bash

verify_installed()
{
  local cmd="$1"
  if [[ $(type $cmd 2>&1) =~ "not found" ]]; then
    echo -e "\nERROR: This script requires '$cmd'. Please install '$cmd' and run again.\n"
    exit 1
  fi
}
verify_installed "jq"
verify_installed "docker-compose"
verify_installed "keytool"

OLDDIR=$PWD

cd ${OLDDIR}/../../environment/sasl-ssl/security

echo "Generate keys and certificates used for SSL"
./certs-create.sh > /dev/null 2>&1

cd ${OLDDIR}/../../environment/sasl-ssl

DOCKER_COMPOSE_FILE_OVERRIDE=$1
if [ -f "${DOCKER_COMPOSE_FILE_OVERRIDE}" ]
then
  echo "Using ${DOCKER_COMPOSE_FILE_OVERRIDE}"
  docker-compose -f ../../environment/sasl-ssl/docker-compose.yml -f ${DOCKER_COMPOSE_FILE_OVERRIDE} down -v
  docker-compose -f ../../environment/sasl-ssl/docker-compose.yml -f ${DOCKER_COMPOSE_FILE_OVERRIDE} up -d
else
  docker-compose down -v
  docker-compose up -d
fi

cd ${OLDDIR}

../../WaitForConnectAndControlCenter.sh