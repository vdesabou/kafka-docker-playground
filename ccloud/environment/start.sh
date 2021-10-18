#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

CONFIG_FILE=~/.ccloud/config

if [ ! -f ${CONFIG_FILE} ]
then
     logerror "ERROR: ${CONFIG_FILE} is not set"
     exit 1
fi

${DIR}/../ccloud-demo/ccloud-generate-env-vars.sh ${CONFIG_FILE}

if [ -f /tmp/delta_configs/env.delta ]
then
     source /tmp/delta_configs/env.delta
else
     logerror "ERROR: /tmp/delta_configs/env.delta has not been generated"
     exit 1
fi

if [ -z "$CI" ] && [ -z "$CLOUDFORMATION" ]
then
     # not running with CI
     verify_installed "ccloud"
     check_ccloud_version 1.7.0 || exit 1
     verify_ccloud_login  "ccloud kafka cluster list"
     verify_ccloud_details
     check_if_continue
else
     # running with github actions or cloudformation
     log "Installing ccloud CLI"
     curl -L --http1.1 https://cnfl.io/ccloud-cli | sudo sh -s -- -b /usr/local/bin
     export PATH=$PATH:/usr/local/bin
     log "##################################################"
     log "Log in to Confluent Cloud"
     log "##################################################"
     ccloud login --save
     log "Use environment $ENVIRONMENT"
     ccloud environment use $ENVIRONMENT
     log "Use cluster $CLUSTER_LKC"
     ccloud kafka cluster use $CLUSTER_LKC
     log "Store api key $CLOUD_KEY"
     ccloud api-key store $CLOUD_KEY $CLOUD_SECRET --resource $CLUSTER_LKC --force
     log "Use api key $CLOUD_KEY"
     ccloud api-key use $CLOUD_KEY --resource $CLUSTER_LKC
fi

# generate data file for externalizing secrets
sed -e "s|:BOOTSTRAP_SERVERS:|$BOOTSTRAP_SERVERS|g" \
    -e "s|:CLOUD_KEY:|$CLOUD_KEY|g" \
    -e "s|:CLOUD_SECRET:|$CLOUD_SECRET|g" \
    -e "s|:SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO:|$SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO|g" \
    ../../ccloud/environment/data.template > ../../ccloud/environment/data

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

ENABLE_DOCKER_COMPOSE_FILE_OVERRIDE=""
DOCKER_COMPOSE_FILE_OVERRIDE=$1
if [ -f "${DOCKER_COMPOSE_FILE_OVERRIDE}" ]
then
  ENABLE_DOCKER_COMPOSE_FILE_OVERRIDE="-f ${DOCKER_COMPOSE_FILE_OVERRIDE}"
fi

docker-compose -f ../../ccloud/environment/docker-compose.yml ${ENABLE_DOCKER_COMPOSE_FILE_OVERRIDE} build
docker-compose -f ../../ccloud/environment/docker-compose.yml ${ENABLE_DOCKER_COMPOSE_FILE_OVERRIDE} down -v --remove-orphans
docker-compose -f ../../ccloud/environment/docker-compose.yml ${ENABLE_DOCKER_COMPOSE_FILE_OVERRIDE} ${profile_control_center_command} up -d
log "📝 To see the actual properties file, use ../../scripts/get-properties.sh <container>"
log "♻️ If you modify a docker-compose file and want to re-create the container(s), use this command:"
log "♻️ source ../../scripts/utils.sh && docker-compose -f ../../ccloud/environment/docker-compose.yml ${ENABLE_DOCKER_COMPOSE_FILE_OVERRIDE} ${profile_control_center_command} up -d"

if [ "$#" -ne 0 ]
then
    shift
fi
../../scripts/wait-for-connect-and-controlcenter.sh $@
