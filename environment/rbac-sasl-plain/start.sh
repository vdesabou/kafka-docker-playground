#!/bin/bash

set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if ! version_gt $TAG_BASE "5.3.99"; then
    logwarn "This RBAC example is working starting from CP 5.4 only"
    exit 111
fi

verify_docker_and_memory

check_docker_compose_version
check_bash_version
check_and_update_playground_version
nb_connect_services=0
ENABLE_DOCKER_COMPOSE_FILE_OVERRIDE=""
DOCKER_COMPOSE_FILE_OVERRIDE=$1
if [ -f "${DOCKER_COMPOSE_FILE_OVERRIDE}" ]
then
  ENABLE_DOCKER_COMPOSE_FILE_OVERRIDE="-f ${DOCKER_COMPOSE_FILE_OVERRIDE}"
  set +e
  nb_connect_services=$(grep -Ec "connect[0-9]+:" ${DOCKER_COMPOSE_FILE_OVERRIDE})
  set -e
  check_arm64_support "${DIR}" "${DOCKER_COMPOSE_FILE_OVERRIDE}"
fi
set_profiles

if [ ! -z $ENABLE_KRAFT ]
then
  # KRAFT mode
  INITIAL_CONTAINER_LIST="controller broker tools openldap"
  KRAFT_RBAC_DOCKER_COMPOSE_FILE_OVERRIDE="-f ${DIR}/../../environment/rbac-sasl-plain/docker-compose-kraft.yml"
else
  # Zookeeper mode
  INITIAL_CONTAINER_LIST="zookeeper broker tools openldap"
  KRAFT_RBAC_DOCKER_COMPOSE_FILE_OVERRIDE=""
fi

mkdir -p ${DIR}/scripts/security/ldap_certs
cd ${DIR}/scripts/security/ldap_certs
if [[ "$OSTYPE" == "darwin"* ]]
then
    # workaround for issue on linux, see https://github.com/vdesabou/kafka-docker-playground/issues/851#issuecomment-821151962
    chmod -R a+rw .
else
    # on CI, docker is run as runneradmin user, need to use sudo
    sudo chmod -R a+rw .
fi
log "LDAPS: Creating a Root Certificate Authority (CA)"
docker run --quiet --rm -v $PWD:/tmp alpine/openssl req -new -x509 -days 365 -nodes -out /tmp/ca.crt -keyout /tmp/ca.key -subj "/CN=root-ca"
log "LDAPS: Generate the LDAPS server key and certificate"
docker run --quiet --rm -v $PWD:/tmp alpine/openssl req -new -nodes -out /tmp/server.csr -keyout /tmp/server.key -subj "/CN=openldap"
docker run --quiet --rm -v $PWD:/tmp alpine/openssl x509 -req -in /tmp/server.csr -days 365 -CA /tmp/ca.crt -CAkey /tmp/ca.key -CAcreateserial -out /tmp/server.crt
log "LDAPS: Create a JKS truststore"
rm -f ldap_truststore.jks
# We import the test CA certificate
docker run --quiet --rm -v $PWD:/tmp ${CP_CONNECT_IMAGE}:${CP_CONNECT_TAG} keytool -import -v -alias testroot -file /tmp/ca.crt -keystore /tmp/ldap_truststore.jks -storetype JKS -storepass 'welcome123' -noprompt
log "LDAPS: Displaying truststore"
docker run --quiet --rm -v $PWD:/tmp ${CP_CONNECT_IMAGE}:${CP_CONNECT_TAG} keytool -list -keystore /tmp/ldap_truststore.jks -storepass 'welcome123' -v
cd -

../../environment/rbac-sasl-plain/stop.sh $@

# Generating public and private keys for token signing
log "Generating public and private keys for token signing"


maybe_provider=""
if version_gt $TAG "7.7.99"
then
    maybe_provider="-provider base"
fi

mkdir -p ../../environment/rbac-sasl-plain/conf
cd ../../environment/rbac-sasl-plain/
OLDDIR=$PWD
mkdir -p conf
docker run -v $PWD:/tmp -u0 alpine/openssl genrsa -out /tmp/conf/keypair.pem 2048
docker run -v $PWD:/tmp -u0 alpine/openssl rsa -in /tmp/conf/keypair.pem -outform PEM -pubout -out /tmp/conf/public.pem
cd conf
if [[ "$OSTYPE" == "darwin"* ]]
then
    # workaround for issue on linux, see https://github.com/vdesabou/kafka-docker-playground/issues/851#issuecomment-821151962
    chmod -R a+rw .
else
    # on CI, docker is run as runneradmin user, need to use sudo
    sudo chmod -R a+rw .
fi
cd -
cd ${OLDDIR}

# Bring up base cluster and Confluent CLI
if [ -f "${DOCKER_COMPOSE_FILE_OVERRIDE}" ]
then
  docker compose -f ../../environment/plaintext/docker-compose.yml ${KRAFT_DOCKER_COMPOSE_FILE_OVERRIDE} -f ../../environment/rbac-sasl-plain/docker-compose.yml ${KRAFT_RBAC_DOCKER_COMPOSE_FILE_OVERRIDE} -f ${DOCKER_COMPOSE_FILE_OVERRIDE} up -d --quiet-pull ${INITIAL_CONTAINER_LIST}
else
  docker compose -f ../../environment/plaintext/docker-compose.yml ${KRAFT_DOCKER_COMPOSE_FILE_OVERRIDE} -f ../../environment/rbac-sasl-plain/docker-compose.yml ${KRAFT_RBAC_DOCKER_COMPOSE_FILE_OVERRIDE} up -d --quiet-pull ${INITIAL_CONTAINER_LIST}
fi

ENABLE_DOCKER_COMPOSE_FILE_OVERRIDE=""
DOCKER_COMPOSE_FILE_OVERRIDE=$1
if [ -f "${DOCKER_COMPOSE_FILE_OVERRIDE}" ]
then
  ENABLE_DOCKER_COMPOSE_FILE_OVERRIDE="-f ${DOCKER_COMPOSE_FILE_OVERRIDE}"
  check_arm64_support "${DIR}" "${DOCKER_COMPOSE_FILE_OVERRIDE}"
fi

docker compose -f ../../environment/plaintext/docker-compose.yml ${KRAFT_DOCKER_COMPOSE_FILE_OVERRIDE} -f ../../environment/rbac-sasl-plain/docker-compose.yml ${KRAFT_RBAC_DOCKER_COMPOSE_FILE_OVERRIDE} ${ENABLE_DOCKER_COMPOSE_FILE_OVERRIDE} up -d --quiet-pull ${INITIAL_CONTAINER_LIST}


if [ ! -z $ENABLE_KRAFT ]
then
  # KRAFT mode
  :
else
  # Zookeeper mode
  # Verify Kafka brokers have started
  MAX_WAIT=30
  log "⌛ Waiting up to $MAX_WAIT seconds for Kafka brokers to be registered in ZooKeeper"
  retrycmd $MAX_WAIT 5 host_check_kafka_cluster_registered || exit 1
fi

# Verify MDS has started
MAX_WAIT=120
log "⌛ Waiting up to $MAX_WAIT seconds for MDS to start"
retrycmd $MAX_WAIT 5 host_check_mds_up || exit 1

sleep 5

log "Available LDAP users:"
docker exec openldap ldapsearch -x -h localhost -b dc=confluentdemo,dc=io -D "cn=admin,dc=confluentdemo,dc=io" -w admin | grep uid:

log "Creating role bindings for principals"
docker exec -i tools bash -c "/tmp/helper/create-role-bindings.sh"

log "Validate bindings"
docker exec -i tools bash -c "/tmp/helper/validate_bindings.sh"

docker compose -f ../../environment/plaintext/docker-compose.yml ${KRAFT_DOCKER_COMPOSE_FILE_OVERRIDE} -f ../../environment/rbac-sasl-plain/docker-compose.yml ${KRAFT_RBAC_DOCKER_COMPOSE_FILE_OVERRIDE} ${ENABLE_DOCKER_COMPOSE_FILE_OVERRIDE}  ${profile_control_center_command} ${profile_ksqldb_command} ${profile_zookeeper_command}  ${profile_grafana_command} ${profile_conduktor_command} ${profile_kafka_nodes_command} ${profile_connect_nodes_command} build
docker compose -f ../../environment/plaintext/docker-compose.yml ${KRAFT_DOCKER_COMPOSE_FILE_OVERRIDE} -f ../../environment/rbac-sasl-plain/docker-compose.yml ${KRAFT_RBAC_DOCKER_COMPOSE_FILE_OVERRIDE} ${ENABLE_DOCKER_COMPOSE_FILE_OVERRIDE} ${profile_control_center_command} ${profile_ksqldb_command} ${profile_zookeeper_command}  ${profile_grafana_command} ${profile_kcat_command} ${profile_kafka_nodes_command} ${profile_connect_nodes_command} up -d --quiet-pull
log "📝 To see the actual properties file, use cli command 'playground container get-properties -c <container>'"
command="source ${DIR}/../../scripts/utils.sh && docker compose -f ${DIR}/../../environment/plaintext/docker-compose.yml ${KRAFT_DOCKER_COMPOSE_FILE_OVERRIDE} -f ${DIR}/../../environment/rbac-sasl-plain/docker-compose.yml ${KRAFT_RBAC_DOCKER_COMPOSE_FILE_OVERRIDE} ${ENABLE_DOCKER_COMPOSE_FILE_OVERRIDE} ${profile_control_center_command} ${profile_ksqldb_command} ${profile_zookeeper_command}  ${profile_grafana_command} ${profile_kcat_command} ${profile_kafka_nodes_command} ${profile_connect_nodes_command} up -d --quiet-pull"
playground state set run.docker_command "$command"
playground state set run.environment "rbac-sasl-plain"
log "✨ If you modify a docker-compose file and want to re-create the container(s), run cli command 'playground container recreate'"


wait_container_ready

display_jmx_info