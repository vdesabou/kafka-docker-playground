#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh


check_docker_compose_version
check_bash_version
check_playground_version
bootstrap_ccloud_environment

# generate data file for externalizing secrets
sed -e "s|:BOOTSTRAP_SERVERS:|$BOOTSTRAP_SERVERS|g" \
    -e "s|:CLOUD_KEY:|$CLOUD_KEY|g" \
    -e "s|:CLOUD_SECRET:|$CLOUD_SECRET|g" \
    -e "s|:SCHEMA_REGISTRY_URL:|$SCHEMA_REGISTRY_URL|g" \
    -e "s|:SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO:|$SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO|g" \
    ../../ccloud/environment/data.template > ../../ccloud/environment/data

export SR_USER=$(echo "$SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO" | cut -d":" -f1)
export SR_PASSWORD=$(echo "$SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO" | cut -d":" -f2)

set +e
playground topic delete --topic _confluent-monitoring
log "Cleanup connect worker topics"
playground topic delete --topic connect-status-${TAG}
playground topic delete --topic connect-offsets-${TAG}
playground topic delete --topic connect-configs-${TAG}
playground topic create --topic _confluent-monitoring
set -e

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
  DISABLE_REPLICATOR_MONITORING="-f ../../ccloud/environment/docker-compose.no-replicator-monitoring.yml"
fi

docker compose -f ../../ccloud/environment/docker-compose.yml ${ENABLE_DOCKER_COMPOSE_FILE_OVERRIDE} ${DISABLE_REPLICATOR_MONITORING} build
docker compose -f ../../ccloud/environment/docker-compose.yml ${ENABLE_DOCKER_COMPOSE_FILE_OVERRIDE} ${DISABLE_REPLICATOR_MONITORING} down -v --remove-orphans
docker compose -f ../../ccloud/environment/docker-compose.yml ${ENABLE_DOCKER_COMPOSE_FILE_OVERRIDE} ${DISABLE_REPLICATOR_MONITORING} ${profile_control_center_command} ${profile_conduktor_command} ${profile_grafana_command} up -d --quiet-pull
log "📝 To see the actual properties file, use cli command 'playground container get-properties -c <container>'"
command="source ${DIR}/../../scripts/utils.sh && docker compose -f ${DIR}/../../ccloud/environment/docker-compose.yml ${ENABLE_DOCKER_COMPOSE_FILE_OVERRIDE} ${profile_control_center_command} ${profile_conduktor_command} ${profile_grafana_command} up -d --quiet-pull"
playground state set run.docker_command "$command"
playground state set run.environment "ccloud"
log "✨ If you modify a docker-compose file and want to re-create the container(s), run cli command 'playground container recreate'"



wait_container_ready
