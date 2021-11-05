#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

CONFIG_FILE=~/.confluent/config

if [ ! -f ${CONFIG_FILE} ]
then
     logerror "ERROR: ${CONFIG_FILE} is not set"
     exit 1
fi

if [ -z "$BOOTSTRAP_SERVERS" ]
then
     ${DIR}/../ccloud-demo/confluent-generate-env-vars.sh ${CONFIG_FILE}

     if [ -f /tmp/delta_configs/env.delta ]
     then
          source /tmp/delta_configs/env.delta
     else
          logerror "ERROR: /tmp/delta_configs/env.delta has not been generated"
          exit 1
     fi
fi

if [ -z "$CI" ] && [ -z "$CLOUDFORMATION" ]
then
     # not running with CI
     verify_installed "confluent"
     check_confluent_version 2.0.0 || exit 1
     verify_confluent_login  "confluent kafka cluster list"
     verify_confluent_details
     check_if_continue
else
     if [ ! -z "$CI" ]
     then
          # running with github actions
          if [ ! -f ../../secrets.properties ]
          then
               logerror "../../secrets.properties is not present!"
               exit 1
          fi
          source ../../secrets.properties > /dev/null 2>&1
     fi
     
     log "Installing confluent CLI"
     curl -L --http1.1 https://cnfl.io/cli | sudo sh -s -- -b /usr/local/bin
     export PATH=$PATH:/usr/local/bin
     log "##################################################"
     log "Log in to Confluent Cloud"
     log "##################################################"
     confluent login --save
     log "Use environment $ENVIRONMENT"
     confluent environment use $ENVIRONMENT
     log "Use cluster $CLUSTER_LKC"
     confluent kafka cluster use $CLUSTER_LKC
     log "Store api key $CLOUD_KEY"
     confluent api-key store $CLOUD_KEY $CLOUD_SECRET --resource $CLUSTER_LKC --force
     log "Use api key $CLOUD_KEY"
     confluent api-key use $CLOUD_KEY --resource $CLUSTER_LKC
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
