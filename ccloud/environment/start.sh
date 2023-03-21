#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

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
log "Cleanup connect worker topics"
delete_topic connect-status-${TAG}
delete_topic connect-offsets-${TAG}
delete_topic connect-configs-${TAG}
set -e

# https://docs.docker.com/compose/profiles/
profile_control_center_command=""
if [ -z "$DISABLE_CONTROL_CENTER" ]
then
  profile_control_center_command="--profile control-center"
else
  log "🛑 control-center is disabled"
fi

if [ -z "$ENABLE_CONDUKTOR" ]
then
  log "🛑 conduktor is disabled"
else
  log "🐺 conduktor is enabled"
  log "Use http://localhost:8080/console (admin/admin) to login"
  profile_conduktor_command="--profile conduktor"
fi

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

docker-compose -f ../../ccloud/environment/docker-compose.yml ${ENABLE_DOCKER_COMPOSE_FILE_OVERRIDE} ${DISABLE_REPLICATOR_MONITORING} build
docker-compose -f ../../ccloud/environment/docker-compose.yml ${ENABLE_DOCKER_COMPOSE_FILE_OVERRIDE} ${DISABLE_REPLICATOR_MONITORING} down -v --remove-orphans
docker-compose -f ../../ccloud/environment/docker-compose.yml ${ENABLE_DOCKER_COMPOSE_FILE_OVERRIDE} ${DISABLE_REPLICATOR_MONITORING} ${profile_control_center_command} ${profile_conduktor_command} up -d
log "📝 To see the actual properties file, use cli command playground get-properties -c <container>"
command="source ../../scripts/utils.sh && docker-compose -f ../../ccloud/environment/docker-compose.yml ${ENABLE_DOCKER_COMPOSE_FILE_OVERRIDE} ${profile_control_center_command} ${profile_conduktor_command} up -d"
echo "$command" > /tmp/playground-command
log "✨ If you modify a docker-compose file and want to re-create the container(s), run cli command playground recreate-container"


if [ "$#" -ne 0 ]
then
    shift
fi
../../scripts/wait-for-connect-and-controlcenter.sh $@
