#!/bin/bash

DOCKER_COMPOSE_FILE_OVERRIDE=$1
if [ -f "${DOCKER_COMPOSE_FILE_OVERRIDE}" ]
then
  echo "Using ${DOCKER_COMPOSE_FILE_OVERRIDE}"
  docker-compose -f ../../environment/plaintext/docker-compose.yml -f ${DOCKER_COMPOSE_FILE_OVERRIDE} down -v
else
  docker-compose down -v
fi
