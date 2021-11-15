#!/bin/bash

set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if ! version_gt $TAG_BASE "5.3.99"; then
    logwarn "WARN: This RBAC example is working starting from CP 5.4 only"
    exit 111
fi

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

../../environment/rbac-sasl-plain/stop.sh $@

# Generating public and private keys for token signing
log "Generating public and private keys for token signing"
mkdir -p ../../environment/rbac-sasl-plain/conf
openssl genrsa -out ../../environment/rbac-sasl-plain/conf/keypair.pem 2048
openssl rsa -in ../../environment/rbac-sasl-plain/conf/keypair.pem -outform PEM -pubout -out ../../environment/rbac-sasl-plain/conf/public.pem
log "Enable Docker appuser to read files when created by a different UID"
chmod 644 ../../environment/rbac-sasl-plain/conf/keypair.pem

# Bring up base cluster and Confluent CLI
if [ -f "${DOCKER_COMPOSE_FILE_OVERRIDE}" ]
then
  docker-compose -f ../../environment/plaintext/docker-compose.yml -f ../../environment/rbac-sasl-plain/docker-compose.yml -f ${DOCKER_COMPOSE_FILE_OVERRIDE} up -d zookeeper broker tools openldap
else
  docker-compose -f ../../environment/plaintext/docker-compose.yml -f ../../environment/rbac-sasl-plain/docker-compose.yml up -d zookeeper broker tools openldap
fi

ENABLE_DOCKER_COMPOSE_FILE_OVERRIDE=""
DOCKER_COMPOSE_FILE_OVERRIDE=$1
if [ -f "${DOCKER_COMPOSE_FILE_OVERRIDE}" ]
then
  ENABLE_DOCKER_COMPOSE_FILE_OVERRIDE="-f ${DOCKER_COMPOSE_FILE_OVERRIDE}"
fi

docker-compose -f ../../environment/plaintext/docker-compose.yml -f ../../environment/rbac-sasl-plain/docker-compose.yml ${ENABLE_DOCKER_COMPOSE_FILE_OVERRIDE} up -d zookeeper broker tools openldap

# Verify Kafka brokers have started
MAX_WAIT=30
log "Waiting up to $MAX_WAIT seconds for Kafka brokers to be registered in ZooKeeper"
retrycmd $MAX_WAIT 5 host_check_kafka_cluster_registered || exit 1

# Verify MDS has started
MAX_WAIT=120
log "Waiting up to $MAX_WAIT seconds for MDS to start"
retrycmd $MAX_WAIT 5 host_check_mds_up || exit 1
sleep 5

log "Available LDAP users:"
docker exec openldap ldapsearch -x -h localhost -b dc=confluentdemo,dc=io -D "cn=admin,dc=confluentdemo,dc=io" -w admin | grep uid:

log "Creating role bindings for principals"
docker exec -i tools bash -c "/tmp/helper/create-role-bindings.sh"

docker-compose -f ../../environment/plaintext/docker-compose.yml -f ../../environment/rbac-sasl-plain/docker-compose.yml ${ENABLE_DOCKER_COMPOSE_FILE_OVERRIDE} build
docker-compose -f ../../environment/plaintext/docker-compose.yml -f ../../environment/rbac-sasl-plain/docker-compose.yml ${ENABLE_DOCKER_COMPOSE_FILE_OVERRIDE} ${profile_control_center_command} ${profile_ksqldb_command} up -d
log "📝 To see the actual properties file, use ../../scripts/get-properties.sh <container>"
log "🔃 If you modify a docker-compose file and want to re-create the container(s), use this command:"
log "🔃 source ../../scripts/utils.sh && docker-compose -f ../../environment/plaintext/docker-compose.yml -f ../../environment/rbac-sasl-plain/docker-compose.yml ${ENABLE_DOCKER_COMPOSE_FILE_OVERRIDE} ${profile_control_center_command} ${profile_ksqldb_command} up -d"

if [ "$#" -ne 0 ]
then
    shift
fi
../../scripts/wait-for-connect-and-controlcenter.sh $@

log "You can use ksqlDB with CLI using:"
log "docker exec -i ksqldb-cli ksql -u ksqlDBUser -p ksqlDBUser http://ksqldb-server:8088"

display_jmx_info

if [ -z "$DISABLE_CONTROL_CENTER" ]
then
  log "Control Center is reachable at http://127.0.0.1:9021, use superUser/superUser to login"
fi