#!/bin/bash

set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

verify_docker_and_memory
verify_installed "docker-compose"
check_docker_compose_version

# https://docs.docker.com/compose/profiles/
profile_control_center_command=""
if [ -z "$DISABLE_CONTROL_CENTER" ]
then
  profile_control_center_command="--profile control-center"
else
  log "🛑 control-center is disabled"
fi

profile_ksqldb_command=""
if [ -z "$DISABLE_KSQLDB" ]
then
  profile_ksqldb_command="--profile ksqldb"
else
  log "🛑 ksqldb is disabled"
fi

ENABLE_DOCKER_COMPOSE_FILE_OVERRIDE=""
DOCKER_COMPOSE_FILE_OVERRIDE=$1
if [ -f "${DOCKER_COMPOSE_FILE_OVERRIDE}" ]
then
  ENABLE_DOCKER_COMPOSE_FILE_OVERRIDE="-f ${DOCKER_COMPOSE_FILE_OVERRIDE}"
fi

docker-compose -f ../../environment/plaintext/docker-compose.yml -f ../../environment/sasl-scram/docker-compose.yml ${ENABLE_DOCKER_COMPOSE_FILE_OVERRIDE} build
docker-compose -f ../../environment/plaintext/docker-compose.yml ${ENABLE_DOCKER_COMPOSE_FILE_OVERRIDE} down -v --remove-orphans
docker-compose -f ../../environment/plaintext/docker-compose.yml ${ENABLE_DOCKER_COMPOSE_FILE_OVERRIDE} ${profile_control_center_command} ${profile_ksqldb_command} up -d --build broker

# Creating the users
docker exec broker kafka-configs --zookeeper zookeeper:2181 --alter --add-config 'SCRAM-SHA-256=[password=broker],SCRAM-SHA-512=[password=broker]' --entity-type users --entity-name broker
docker exec broker kafka-configs --zookeeper zookeeper:2181 --alter --add-config 'SCRAM-SHA-256=[password=connect-secret],SCRAM-SHA-512=[password=connect-secret]' --entity-type users --entity-name connect
docker exec broker kafka-configs --zookeeper zookeeper:2181 --alter --add-config 'SCRAM-SHA-256=[password=schemaregistry-secret],SCRAM-SHA-512=[password=schemaregistry-secret]' --entity-type users --entity-name schemaregistry
docker exec broker kafka-configs --zookeeper zookeeper:2181 --alter --add-config 'SCRAM-SHA-256=[password=ksqldb-secret],SCRAM-SHA-512=[password=ksqldb-secret]' --entity-type users --entity-name ksqldb
docker exec broker kafka-configs --zookeeper zookeeper:2181 --alter --add-config 'SCRAM-SHA-256=[password=client-secret],SCRAM-SHA-512=[password=client-secret]' --entity-type users --entity-name client

docker-compose -f ../../environment/plaintext/docker-compose.yml -f ../../environment/sasl-scram/docker-compose.yml ${ENABLE_DOCKER_COMPOSE_FILE_OVERRIDE} ${profile_control_center_command} ${profile_ksqldb_command} up -d
log "📝 To see the actual properties file, use ../../scripts/get-properties.sh <container>"
log "🔃 If you modify a docker-compose file and want to re-create the container(s), use this command:"
log "🔃 source ../../scripts/utils.sh && docker-compose -f ../../environment/plaintext/docker-compose.yml -f ../../environment/sasl-scram/docker-compose.yml ${ENABLE_DOCKER_COMPOSE_FILE_OVERRIDE} ${profile_control_center_command} ${profile_ksqldb_command} up -d"

if [ "$#" -ne 0 ]
then
    shift
fi
../../scripts/wait-for-connect-and-controlcenter.sh $@

display_jmx_info