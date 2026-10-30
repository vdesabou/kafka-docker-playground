#!/bin/bash

set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

verify_docker_and_memory

check_docker_compose_version
check_bash_version
check_and_update_playground_version

set_profiles

ENABLE_DOCKER_COMPOSE_FILE_OVERRIDE=""
DOCKER_COMPOSE_FILE_OVERRIDE=$1
if [ -f "${DOCKER_COMPOSE_FILE_OVERRIDE}" ]
then
  ENABLE_DOCKER_COMPOSE_FILE_OVERRIDE="-f ${DOCKER_COMPOSE_FILE_OVERRIDE}"
  check_arm64_support "${DIR}" "${DOCKER_COMPOSE_FILE_OVERRIDE}"
fi

DISABLE_REPLICATOR_MONITORING=""
if ! version_gt $TAG_BASE "5.4.99"; then
  logwarn "Replicator Monitoring is disabled as you're using an old version"
  DISABLE_REPLICATOR_MONITORING="-f ${DIR}/docker-compose.no-replicator-monitoring.yml"
else
  mdc_install_replicator
fi

# Support selective service startup via START_SERVICES env var
# Format: "service1 service2 service3"
SERVICES_ARGS=""
if [[ -n "$START_SERVICES" ]]
then
  SERVICES_ARGS="$START_SERVICES"
  log "🔍 Starting only services: $START_SERVICES"
fi

DOCKER_COMPOSE_ARGS="-f ${DIR}/docker-compose.yml ${MDC_KRAFT_DOCKER_COMPOSE_FILE_OVERRIDE} ${ENABLE_DOCKER_COMPOSE_FILE_OVERRIDE} ${DISABLE_REPLICATOR_MONITORING} ${profile_control_center_command} ${profile_flink} ${profile_zookeeper_command}"

# Only run 'down' if we're NOT skipping container stop (--no-stop not set)
if [[ -z "$NO_STOP" ]]
then
  docker compose ${DOCKER_COMPOSE_ARGS} down -v --remove-orphans
fi

docker compose ${DOCKER_COMPOSE_ARGS} up -d --quiet-pull $SERVICES_ARGS
log "📝 To see the actual properties file, use cli command 'playground container get-properties -c <container>'"
command="source ${DIR}/../../scripts/utils.sh && docker compose ${DOCKER_COMPOSE_ARGS} up -d --quiet-pull $SERVICES_ARGS"
playground state set run.docker_command "$command"
playground state set run.environment "mdc-plaintext"
log "✨ If you modify a docker-compose file and want to re-create the container(s), run cli command 'playground container recreate'"

wait_container_ready connect-us
wait_container_ready connect-europe