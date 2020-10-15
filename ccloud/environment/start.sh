#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

verify_installed "docker-compose"

if [ -z "$TRAVIS" ]
then
     # not running with TRAVIS
     verify_installed "ccloud"
     check_ccloud_version 1.7.0 || exit 1
     verify_ccloud_login  "ccloud kafka cluster list"
     verify_ccloud_details
     check_if_continue
fi

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

if [ ! -z "$TRAVIS" ]
then
     # running with travis
     log "Installing ccloud CLI"
     curl -L https://cnfl.io/ccloud-cli | sudo sh -s -- -b /usr/local/bin
     log "##################################################"
     log "Log in to Confluent Cloud"
     log "##################################################"

OUTPUT=$(
expect <<END
log_user 1
spawn ccloud login
expect "Email: "
send "$CCLOUD_USER\r";
expect "Password: "
send "$CCLOUD_PASSWORD\r";
expect "Logged in as "
set result $expect_out(buffer)
END
)
     if [[ ! "$OUTPUT" =~ "Logged in as" ]]; then
          logerror "Failed to log into your cluster.  Please check all parameters and run again"
          exit 1
     fi

     log "Using travis cluster"
     ccloud kafka cluster use lkc-6kv2j
fi

set +e
log "Cleanup connect worker topics"
delete_topic connect-status
delete_topic connect-offsets
delete_topic connect-configs
set -e

DOCKER_COMPOSE_FILE_OVERRIDE=$1
if [ -f "${DOCKER_COMPOSE_FILE_OVERRIDE}" ]
then
  docker-compose -f ../../ccloud/environment/docker-compose.yml -f ${DOCKER_COMPOSE_FILE_OVERRIDE} build
  docker-compose -f ../../ccloud/environment/docker-compose.yml -f ${DOCKER_COMPOSE_FILE_OVERRIDE} down -v
  docker-compose -f ../../ccloud/environment/docker-compose.yml -f ${DOCKER_COMPOSE_FILE_OVERRIDE} up -d
else
  docker-compose -f ../../ccloud/environment/docker-compose.yml build
  docker-compose -f ../../ccloud/environment/docker-compose.yml down -v
  docker-compose -f ../../ccloud/environment/docker-compose.yml up -d
fi

if [ "$#" -ne 0 ]
then
    shift
fi
../../scripts/wait-for-connect-and-controlcenter.sh $@


if [ ! -z "$TRAVIS" ]
then
     # running with travis
     log "##################################################"
     log "Stopping everything"
     log "##################################################"
     bash ${DIR}/stop.sh
fi