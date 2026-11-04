#!/bin/bash

set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

verify_docker_and_memory

check_docker_compose_version
check_bash_version
check_and_update_playground_version

# org.apache.kafka.common.security.oauthbearer.OAuthBearer{Login,Validator}CallbackHandler: Apache Kafka 3.4+ (CP 7.4+)
if ! version_gt $TAG "7.3.99"
then
  logwarn "sasl-oauthbearer environment needs CP 7.4 or later (it is $TAG)"
  exit 111
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

docker compose -f ../../environment/plaintext/docker-compose.yml ${KRAFT_DOCKER_COMPOSE_FILE_OVERRIDE} ${TELEMETRY_DOCKER_COMPOSE_FILE_OVERRIDE} -f ../../environment/sasl-oauthbearer/docker-compose.yml ${ENABLE_DOCKER_COMPOSE_FILE_OVERRIDE}  ${profile_control_center_command} ${profile_ksqldb_command} ${profile_zookeeper_command}  ${profile_grafana_command} ${profile_conduktor_command} ${profile_kafka_nodes_command} ${profile_controller_nodes_command} ${profile_connect_nodes_command} build --quiet

# Only run 'down' if we're NOT skipping container stop (--no-stop not set)
if [[ -z "$NO_STOP" ]]
then
  docker compose -f ../../environment/plaintext/docker-compose.yml ${KRAFT_DOCKER_COMPOSE_FILE_OVERRIDE} ${TELEMETRY_DOCKER_COMPOSE_FILE_OVERRIDE} -f ../../environment/sasl-oauthbearer/docker-compose.yml ${ENABLE_DOCKER_COMPOSE_FILE_OVERRIDE}  ${profile_control_center_command} ${profile_ksqldb_command} ${profile_zookeeper_command}  ${profile_grafana_command} ${profile_conduktor_command} ${profile_kafka_nodes_command} ${profile_controller_nodes_command} ${profile_connect_nodes_command} down -v --remove-orphans
fi

docker compose -f ../../environment/plaintext/docker-compose.yml ${KRAFT_DOCKER_COMPOSE_FILE_OVERRIDE} ${TELEMETRY_DOCKER_COMPOSE_FILE_OVERRIDE} -f ../../environment/sasl-oauthbearer/docker-compose.yml ${ENABLE_DOCKER_COMPOSE_FILE_OVERRIDE}  ${profile_control_center_command} ${profile_ksqldb_command} ${profile_zookeeper_command}  ${profile_grafana_command} ${profile_conduktor_command} ${profile_kafka_nodes_command} ${profile_controller_nodes_command} ${profile_connect_nodes_command} up -d --quiet-pull $SERVICES_ARGS
log "🔑 Keycloak (OIDC identity provider): realm kafka, token endpoint http://keycloak:8080/realms/kafka/protocol/openid-connect/token, admin console http://localhost:8180/admin (admin/admin)"
log "📝 To see the actual properties file, use cli command 'playground container get-properties -c <container>'"
command="source ${DIR}/../../scripts/utils.sh && docker compose -f ${DIR}/../../environment/plaintext/docker-compose.yml ${KRAFT_DOCKER_COMPOSE_FILE_OVERRIDE} ${TELEMETRY_DOCKER_COMPOSE_FILE_OVERRIDE} -f ${DIR}/../../environment/sasl-oauthbearer/docker-compose.yml ${ENABLE_DOCKER_COMPOSE_FILE_OVERRIDE} ${profile_control_center_command} ${profile_ksqldb_command} ${profile_zookeeper_command}  ${profile_grafana_command} ${profile_conduktor_command} ${profile_kafka_nodes_command} ${profile_controller_nodes_command} ${profile_connect_nodes_command} up -d --quiet-pull $SERVICES_ARGS"
playground state set run.docker_command "$command"
playground state set run.environment "sasl-oauthbearer"
log "✨ If you modify a docker-compose file and want to re-create the container(s), run cli command 'playground container recreate'"



wait_container_ready

display_jmx_info