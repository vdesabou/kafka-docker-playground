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
  DISABLE_REPLICATOR_MONITORING="-f ../../environment/mdc-plaintext/docker-compose.no-replicator-monitoring.yml"
else
  set +e
  log "🎱 Installing replicator confluentinc/kafka-connect-replicator:$TAG for Replicator Monitoring"
  docker run -u0 -i --rm -v ${DIR}/../../confluent-hub:/usr/share/confluent-hub-components ${CP_CONNECT_IMAGE}:${CP_CONNECT_TAG} bash -c "confluent-hub install --no-prompt confluentinc/kafka-connect-replicator:$TAG && chown -R $(id -u $USER):$(id -g $USER) /usr/share/confluent-hub-components"
  if [ $? -ne 0 ]
  then
    LATEST_TAG=$(grep "export TAG" ${DIR}/../../scripts/utils.sh | head -1 | cut -d "=" -f 2 | cut -d " " -f 1)
    logwarn "Installing replicator confluentinc/kafka-connect-replicator:$TAG failed, trying now with default tag $LATEST_TAG"
    docker run -u0 -i --rm -v ${DIR}/../../confluent-hub:/usr/share/confluent-hub-components ${CP_CONNECT_IMAGE}:${CP_CONNECT_TAG} bash -c "confluent-hub install --no-prompt confluentinc/kafka-connect-replicator:$LATEST_TAG && chown -R $(id -u $USER):$(id -g $USER) /usr/share/confluent-hub-components"
    if [ -z "$LATEST_TAG" ]
    then
        logerror "❌ error while getting default TAG "
        exit 1
    fi
  fi
  set -e
fi

docker compose -f ../../environment/mdc-plaintext/docker-compose.yml ${MDC_KRAFT_DOCKER_COMPOSE_FILE_OVERRIDE} -f ../../environment/mdc-sasl-plain/docker-compose.sasl-plain.yml ${ENABLE_DOCKER_COMPOSE_FILE_OVERRIDE} ${DISABLE_REPLICATOR_MONITORING} ${profile_control_center_command} ${profile_flink} ${profile_zookeeper_command} build
docker compose -f ../../environment/mdc-plaintext/docker-compose.yml ${MDC_KRAFT_DOCKER_COMPOSE_FILE_OVERRIDE} -f ../../environment/mdc-sasl-plain/docker-compose.sasl-plain.yml ${ENABLE_DOCKER_COMPOSE_FILE_OVERRIDE} ${DISABLE_REPLICATOR_MONITORING} ${profile_control_center_command} ${profile_flink} ${profile_zookeeper_command} down -v --remove-orphans
docker compose -f ../../environment/mdc-plaintext/docker-compose.yml ${MDC_KRAFT_DOCKER_COMPOSE_FILE_OVERRIDE} -f ../../environment/mdc-sasl-plain/docker-compose.sasl-plain.yml ${ENABLE_DOCKER_COMPOSE_FILE_OVERRIDE} ${DISABLE_REPLICATOR_MONITORING} ${profile_control_center_command} ${profile_flink} ${profile_zookeeper_command} up -d --quiet-pull
log "📝 To see the actual properties file, use cli command 'playground container get-properties -c <container>'"
command="source ${DIR}/../../scripts/utils.sh && docker compose -f ${DIR}/../../environment/mdc-plaintext/docker-compose.yml ${MDC_KRAFT_DOCKER_COMPOSE_FILE_OVERRIDE} -f ${DIR}/../../environment/mdc-sasl-plain/docker-compose.sasl-plain.yml ${ENABLE_DOCKER_COMPOSE_FILE_OVERRIDE} ${DISABLE_REPLICATOR_MONITORING} ${profile_control_center_command} ${profile_flink} ${profile_zookeeper_command} up -d --quiet-pull"
playground state set run.docker_command "$command"
playground state set run.environment "mdc-sasl-plain"
log "✨ If you modify a docker-compose file and want to re-create the container(s), run cli command 'playground container recreate'"

wait_container_ready connect-us
wait_container_ready connect-europe