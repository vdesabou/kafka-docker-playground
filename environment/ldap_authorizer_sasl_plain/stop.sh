#!/bin/bash

DOCKER_COMPOSE_FILE_OVERRIDE=$1
if [ -f "${DOCKER_COMPOSE_FILE_OVERRIDE}" ]
then

  docker-compose -f ../../environment/ldap_authorizer_sasl_plain/docker-compose.yml -f ${DOCKER_COMPOSE_FILE_OVERRIDE} down -v
else
  docker-compose -f ../../environment/ldap_authorizer_sasl_plain/docker-compose.yml down -v
fi
