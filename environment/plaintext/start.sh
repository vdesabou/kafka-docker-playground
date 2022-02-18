#!/bin/bash

set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

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

# defined 3 Connect variable and when profile is included/excluded
profile_connect_nodes_command=""
if [ -z "$ENABLE_CONNECT_NODES" ]
then
  log " Single connect node is being deployed"
elif [ $(readlink -f "*.yml" | xargs -I {} -- sh -c "grep -hE  "connect.:" {} | wc -l") -gt 1 ] # Using grep and wc as simple grep with logical AND does not appear to work properly on yaml files. 
then 
  log " Found connect2 and connect3 in one or more of the following yaml files: $(readlink -f "*.yml" | xargs -I {} -- sh -c "grep -E  "connect.:" {} "). Multi node deployment will start shortly however it may still fail if services have missing configurations."
  profile_connect_nodes_command="--profile connect_nodes"
  export CONNECT_NODES_PROFILES="connect_nodes"
else
  log "🛑 Could not find connect2 and connect3 in any docker-compose*.yml override files. Update the yaml files to contain the connect2 && connect3 in $(readlink -f "*.yml") "
  export CONNECT_NODES_PROFILES=""
fi

ENABLE_DOCKER_COMPOSE_FILE_OVERRIDE=""
DOCKER_COMPOSE_FILE_OVERRIDE=$1
if [ -f "${DOCKER_COMPOSE_FILE_OVERRIDE}" ]
then
  ENABLE_DOCKER_COMPOSE_FILE_OVERRIDE="-f ${DOCKER_COMPOSE_FILE_OVERRIDE}"
fi

docker-compose -f ../../environment/plaintext/docker-compose.yml ${ENABLE_DOCKER_COMPOSE_FILE_OVERRIDE} build
docker-compose -f ../../environment/plaintext/docker-compose.yml ${ENABLE_DOCKER_COMPOSE_FILE_OVERRIDE} down -v --remove-orphans
docker-compose -f ../../environment/plaintext/docker-compose.yml ${ENABLE_DOCKER_COMPOSE_FILE_OVERRIDE} ${profile_control_center_command} ${profile_ksqldb_command} ${profile_grafana_command} ${profile_connect_nodes_command} up -d
log "📝 To see the actual properties file, use ../../scripts/get-properties.sh <container>"
command="source ../../scripts/utils.sh && docker-compose -f ../../environment/plaintext/docker-compose.yml ${ENABLE_DOCKER_COMPOSE_FILE_OVERRIDE} ${profile_control_center_command} ${profile_ksqldb_command} ${profile_grafana_command} ${profile_connect_nodes_command} up -d"
echo "$command" > /tmp/playground-command
log "✨ If you modify a docker-compose file and want to re-create the container(s), run ../../scripts/recreate-containers.sh or use this command:"
log "✨ $command"

if [ "$#" -ne 0 ]
then
    shift
fi
../../scripts/wait-for-connect-and-controlcenter.sh $@

display_jmx_info