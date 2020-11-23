#!/bin/bash

set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

verify_memory
verify_installed "docker-compose"

DOCKER_COMPOSE_FILE_OVERRIDE=$1

../../environment/rbac-sasl-plain/stop.sh $@

# Generating public and private keys for token signing
echo "Generating public and private keys for token signing"
mkdir -p ../../environment/rbac-sasl-plain/conf
openssl genrsa -out ../../environment/rbac-sasl-plain/conf/keypair.pem 2048
openssl rsa -in ../../environment/rbac-sasl-plain/conf/keypair.pem -outform PEM -pubout -out ../../environment/rbac-sasl-plain/conf/public.pem

# Bring up base cluster and Confluent CLI
if [ -f "${DOCKER_COMPOSE_FILE_OVERRIDE}" ]
then
  docker-compose -f ../../environment/plaintext/docker-compose.yml -f ../../environment/rbac-sasl-plain/docker-compose.yml -f ${DOCKER_COMPOSE_FILE_OVERRIDE} up -d zookeeper broker tools openldap
else
  docker-compose -f ../../environment/plaintext/docker-compose.yml -f ../../environment/rbac-sasl-plain/docker-compose.yml up -d zookeeper broker tools openldap
fi

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

if [ -f "${DOCKER_COMPOSE_FILE_OVERRIDE}" ]
then
  docker-compose -f ../../environment/plaintext/docker-compose.yml -f ../../environment/rbac-sasl-plain/docker-compose.yml -f ${DOCKER_COMPOSE_FILE_OVERRIDE} up -d  schema-registry replicator-for-jar-transfer connect control-center
else
  docker-compose -f ../../environment/plaintext/docker-compose.yml -f ../../environment/rbac-sasl-plain/docker-compose.yml up -d schema-registry replicator-for-jar-transfer connect control-center
fi

if [ "$#" -ne 0 ]
then
    shift
fi
../../scripts/wait-for-connect-and-controlcenter.sh $@

log "Control Center is reachable at http://127.0.0.1:9021, use superUser/superUser to login"
