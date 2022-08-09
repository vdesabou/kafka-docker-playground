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

# defined grafana variable and when profile is included/excluded
profile_grafana_command=""
if [ -z "$ENABLE_JMX_GRAFANA" ]
then
  log "🛑 Grafana is disabled"
else
  log "📊 Grafana is enabled"
  profile_grafana_command="--profile grafana"
fi
profile_kcat_command=""
if [ -z "$ENABLE_KCAT" ]
then
  log "🛑 kcat is disabled"
else
  log "🧰 kcat is enabled"
  profile_kcat_command="--profile kcat"
fi

mkdir -p ${DIR}/scripts/security/ldap_certs
cd ${DIR}/scripts/security/ldap_certs
if [[ "$OSTYPE" == "darwin"* ]]
then
    # workaround for issue on linux, see https://github.com/vdesabou/kafka-docker-playground/issues/851#issuecomment-821151962
    chmod -R a+rw .
else
    # on CI, docker is run as runneradmin user, need to use sudo
    ls -lrt
    sudo chmod -R a+rw .
    ls -lrt
fi
log "LDAPS: Creating a Root Certificate Authority (CA)"
docker run --rm -v $PWD:/tmp vdesabou/kafka-docker-playground-connect:${CONNECT_TAG} openssl req -new -x509 -days 365 -nodes -out /tmp/ca.crt -keyout /tmp/ca.key -subj "/CN=root-ca"
log "LDAPS: Generate the LDAPS server key and certificate"
docker run --rm -v $PWD:/tmp vdesabou/kafka-docker-playground-connect:${CONNECT_TAG} openssl req -new -nodes -out /tmp/server.csr -keyout /tmp/server.key -subj "/CN=openldap"
docker run --rm -v $PWD:/tmp vdesabou/kafka-docker-playground-connect:${CONNECT_TAG} openssl x509 -req -in /tmp/server.csr -days 365 -CA /tmp/ca.crt -CAkey /tmp/ca.key -CAcreateserial -out /tmp/server.crt
log "LDAPS: Create a JKS truststore"
rm -f ldap_truststore.jks
# We import the test CA certificate
docker run --rm -v $PWD:/tmp vdesabou/kafka-docker-playground-connect:${CONNECT_TAG} keytool -import -v -alias testroot -file /tmp/ca.crt -keystore /tmp/ldap_truststore.jks -storetype JKS -storepass 'welcome123' -noprompt
log "LDAPS: Displaying truststore"
docker run --rm -v $PWD:/tmp vdesabou/kafka-docker-playground-connect:${CONNECT_TAG} keytool -list -keystore /tmp/ldap_truststore.jks -storepass 'welcome123' -v
cd -

../../environment/rbac-sasl-plain/stop.sh $@

# Generating public and private keys for token signing
log "Generating public and private keys for token signing"
mkdir -p ../../environment/rbac-sasl-plain/conf
cd ../../environment/rbac-sasl-plain/
docker run -v $PWD:/tmp -u0 ${CP_KAFKA_IMAGE}:${TAG} bash -c "mkdir -p /tmp/conf; openssl genrsa -out /tmp/conf/keypair.pem 2048; openssl rsa -in /tmp/conf/keypair.pem -outform PEM -pubout -out /tmp/conf/public.pem && chown -R $(id -u $USER):$(id -g $USER) /tmp/conf && chmod 644 /tmp/conf/keypair.pem"
cd -

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
log "⌛ Waiting up to $MAX_WAIT seconds for Kafka brokers to be registered in ZooKeeper"
retrycmd $MAX_WAIT 5 host_check_kafka_cluster_registered || exit 1

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

docker-compose -f ../../environment/plaintext/docker-compose.yml -f ../../environment/rbac-sasl-plain/docker-compose.yml ${ENABLE_DOCKER_COMPOSE_FILE_OVERRIDE} build
docker-compose -f ../../environment/plaintext/docker-compose.yml -f ../../environment/rbac-sasl-plain/docker-compose.yml ${ENABLE_DOCKER_COMPOSE_FILE_OVERRIDE} ${profile_control_center_command} ${profile_ksqldb_command} ${profile_grafana_command} ${profile_kcat_command} up -d
log "📝 To see the actual properties file, use ../../scripts/get-properties.sh <container>"
command="source ../../scripts/utils.sh && docker-compose -f ../../environment/plaintext/docker-compose.yml -f ../../environment/rbac-sasl-plain/docker-compose.yml ${ENABLE_DOCKER_COMPOSE_FILE_OVERRIDE} ${profile_control_center_command} ${profile_ksqldb_command} ${profile_grafana_command} ${profile_kcat_command} up -d"
echo "$command" > /tmp/playground-command
log "✨ If you modify a docker-compose file and want to re-create the container(s), run ../../scripts/recreate-containers.sh or use this command:"
log "✨ $command"


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