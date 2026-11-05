#!/bin/bash

set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

# OAuth / OIDC for MDS and the Confluent Platform components (confluent.metadata.server.user.store=OAUTH): CP 7.7+
if ! version_gt $TAG_BASE "7.6.99"
then
  logwarn "rbac-oauth environment needs CP 7.7 or later (it is $TAG)"
  exit 111
fi

if [ -z "$ENABLE_KRAFT" ]
then
  logwarn "rbac-oauth environment needs KRaft mode (default with CP 8, set ENABLE_KRAFT=true with CP 7.7 to 7.9)"
  exit 111
fi

verify_docker_and_memory

check_docker_compose_version
check_bash_version
check_and_update_playground_version

# Control Center logs users in with OIDC SSO (authorization code flow in the browser), not set up here
if [ -n "$ENABLE_CONTROL_CENTER" ]
then
  logwarn "⚠️ control-center is not available with the rbac-oauth environment (it needs OIDC SSO), starting without it"
  unset ENABLE_CONTROL_CENTER
fi

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

# Support selective service startup via START_SERVICES env var
# Format: "service1 service2 service3"
SERVICES_ARGS=""
if [[ -n "$START_SERVICES" ]]
then
  SERVICES_ARGS="$START_SERVICES"
  log "🔍 Starting only services: $START_SERVICES"
fi

# the 3 voters of --enable-multiple-controllers: the quorum needs 2 of them
INITIAL_CONTAINER_LIST="keycloak controller broker ${controller_nodes_containers}"

DOCKER_COMPOSE_FILES="-f ../../environment/plaintext/docker-compose.yml ${KRAFT_DOCKER_COMPOSE_FILE_OVERRIDE} ${TELEMETRY_DOCKER_COMPOSE_FILE_OVERRIDE} -f ../../environment/rbac-oauth/docker-compose.yml -f ../../environment/rbac-oauth/docker-compose-kraft.yml ${ENABLE_DOCKER_COMPOSE_FILE_OVERRIDE}"
PROFILES="${profile_ksqldb_command} ${profile_zookeeper_command} ${profile_grafana_command} ${profile_conduktor_command} ${profile_kcat_command} ${profile_kafka_nodes_command} ${profile_controller_nodes_command} ${profile_connect_nodes_command}"

docker compose ${DOCKER_COMPOSE_FILES} ${PROFILES} build --quiet

# Only run 'down' if we're NOT skipping container stop (--no-stop not set)
if [[ -z "$NO_STOP" ]]
then
  docker compose ${DOCKER_COMPOSE_FILES} ${PROFILES} down -v --remove-orphans
fi

# key pair of MDS, to sign its own tokens (impersonation, ksqlDB): the brokers and the REST servers check them
# with public.pem
log "🔑 Generating the key pair of MDS (token signing)"
mkdir -p ${DIR}/conf
docker run --quiet --rm -v ${DIR}/conf:/tmp/conf -u0 alpine/openssl genrsa -out /tmp/conf/keypair.pem 2048
docker run --quiet --rm -v ${DIR}/conf:/tmp/conf -u0 alpine/openssl rsa -in /tmp/conf/keypair.pem -outform PEM -pubout -out /tmp/conf/public.pem
if [[ "$OSTYPE" == "darwin"* ]]
then
  # workaround for issue on linux, see https://github.com/vdesabou/kafka-docker-playground/issues/851#issuecomment-821151962
  chmod -R a+rw ${DIR}/conf
else
  # on CI, docker is run as runneradmin user, need to use sudo
  sudo chmod -R a+rw ${DIR}/conf
fi

# keycloak, the controller and the broker first: the role bindings must exist before the other components start
docker compose ${DOCKER_COMPOSE_FILES} ${PROFILES} up -d --quiet-pull ${INITIAL_CONTAINER_LIST}
log "🔑 Keycloak (OIDC identity provider): realm kafka, token endpoint http://keycloak:8080/realms/kafka/protocol/openid-connect/token, admin console http://localhost:8180/admin (admin/admin)"

MAX_WAIT=180
log "⌛ Waiting up to $MAX_WAIT seconds for MDS to accept a token of the Keycloak client superuser"
retrycmd $((MAX_WAIT / 5)) 5 host_check_mds_up_oauth || exit 1

# playground rbac commands only run in the rbac environments
playground state set run.environment "rbac-oauth"

log "🔐 Creating default role bindings from ${DIR}/role-bindings.txt"
playground rbac role-binding create --file "${DIR}/role-bindings.txt"

# role bindings of the example (playground start-environment --rbac-role-bindings-file), created
# before connect, schema-registry and ksqldb start
if [ -n "$RBAC_ROLE_BINDINGS_FILE" ]
then
  if [ ! -f "$RBAC_ROLE_BINDINGS_FILE" ]
  then
    logerror "❌ RBAC_ROLE_BINDINGS_FILE $RBAC_ROLE_BINDINGS_FILE does not exist"
    exit 1
  fi
  log "🔐 Creating role bindings from $RBAC_ROLE_BINDINGS_FILE"
  (source "$RBAC_ROLE_BINDINGS_FILE")
fi

docker compose ${DOCKER_COMPOSE_FILES} ${PROFILES} up -d --quiet-pull $SERVICES_ARGS
log "📝 To see the actual properties file, use cli command 'playground container get-properties -c <container>'"
command="source ${DIR}/../../scripts/utils.sh && docker compose -f ${DIR}/../../environment/plaintext/docker-compose.yml ${KRAFT_DOCKER_COMPOSE_FILE_OVERRIDE} ${TELEMETRY_DOCKER_COMPOSE_FILE_OVERRIDE} -f ${DIR}/../../environment/rbac-oauth/docker-compose.yml -f ${DIR}/../../environment/rbac-oauth/docker-compose-kraft.yml ${ENABLE_DOCKER_COMPOSE_FILE_OVERRIDE} ${PROFILES} up -d --quiet-pull $SERVICES_ARGS"
playground state set run.docker_command "$command"
playground state set run.environment "rbac-oauth"
log "✨ If you modify a docker-compose file and want to re-create the container(s), run cli command 'playground container recreate'"


wait_container_ready

display_jmx_info
