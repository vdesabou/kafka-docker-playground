#!/bin/bash

set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh
verify_installed "docker-compose"

DOCKER_COMPOSE_FILE_OVERRIDE=$1
# Starting broker first
if [ -f "${DOCKER_COMPOSE_FILE_OVERRIDE}" ]
then

  docker-compose -f ../../environment/plaintext/docker-compose.yml -f ../../environment/sasl-scram/docker-compose.yml -f ${DOCKER_COMPOSE_FILE_OVERRIDE} down -v
  docker-compose -f ../../environment/plaintext/docker-compose.yml -f ../../environment/sasl-scram/docker-compose.yml -f ${DOCKER_COMPOSE_FILE_OVERRIDE} up -d --build broker
else
  docker-compose -f ../../environment/plaintext/docker-compose.yml -f ../../environment/sasl-scram/docker-compose.yml down -v
  docker-compose -f ../../environment/plaintext/docker-compose.yml -f ../../environment/sasl-scram/docker-compose.yml up -d --build broker
fi

# Creating the users
docker exec broker kafka-configs --zookeeper zookeeper:2181 --alter --add-config 'SCRAM-SHA-256=[password=broker],SCRAM-SHA-512=[password=broker]' --entity-type users --entity-name broker
docker exec broker kafka-configs --zookeeper zookeeper:2181 --alter --add-config 'SCRAM-SHA-256=[password=connect-secret],SCRAM-SHA-512=[password=connect-secret]' --entity-type users --entity-name connect
docker exec broker kafka-configs --zookeeper zookeeper:2181 --alter --add-config 'SCRAM-SHA-256=[password=schemaregistry-secret],SCRAM-SHA-512=[password=schemaregistry-secret]' --entity-type users --entity-name schemaregistry
docker exec broker kafka-configs --zookeeper zookeeper:2181 --alter --add-config 'SCRAM-SHA-256=[password=client-secret],SCRAM-SHA-512=[password=client-secret]' --entity-type users --entity-name client

if [ -f "${DOCKER_COMPOSE_FILE_OVERRIDE}" ]
then
  docker-compose -f ../../environment/plaintext/docker-compose.yml -f ../../environment/sasl-scram/docker-compose.yml -f ${DOCKER_COMPOSE_FILE_OVERRIDE} up -d
else
  docker-compose -f ../../environment/plaintext/docker-compose.yml -f ../../environment/sasl-scram/docker-compose.yml up -d
fi

if [ "$#" -ne 0 ]
then
    shift
fi
../../scripts/wait-for-connect-and-controlcenter.sh $@