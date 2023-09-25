#!/bin/bash

set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

verify_docker_and_memory
verify_installed "docker-compose"
check_docker_compose_version
check_bash_version

# https://docs.docker.com/compose/profiles/
profile_control_center_command=""
if [ -z "$ENABLE_CONTROL_CENTER" ]
then
  log "🛑 control-center is disabled"
else
  log "💠 control-center is enabled"
  log "Use http://localhost:9021 to login"
  profile_control_center_command="--profile control-center"
fi

profile_ksqldb_command=""
if [ -z "$ENABLE_KSQLDB" ]
then
  log "🛑 ksqldb is disabled"
else
  log "🚀 ksqldb is enabled"
  log "🔧 You can use ksqlDB with CLI using:"
  log "docker exec -i ksqldb-cli ksql http://ksqldb-server:8088"
  profile_ksqldb_command="--profile ksqldb"
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
profile_kcat_command=""
if [ -z "$ENABLE_KCAT" ]
then
  log "🛑 kcat is disabled"
else
  log "🧰 kcat is enabled"
  profile_kcat_command="--profile kcat"
fi
profile_conduktor_command=""
if [ -z "$ENABLE_CONDUKTOR" ]
then
  log "🛑 conduktor is disabled"
else
  log "🐺 conduktor is enabled"
  log "Use http://localhost:8080/console (admin/admin) to login"
  profile_conduktor_command="--profile conduktor"
fi
profile_sql_datagen_command=""
if [ ! -z "$SQL_DATAGEN" ]
then
  profile_sql_datagen_command="--profile sql_datagen"
fi

#define kafka_nodes variable and when profile is included/excluded
profile_kafka_nodes_command=""
if [ -z "$ENABLE_KAFKA_NODES" ]
then
  profile_kafka_nodes_command=""
else
  log "3️⃣  Multi broker nodes enabled"
  profile_kafka_nodes_command="--profile kafka_nodes"
fi

ENABLE_DOCKER_COMPOSE_FILE_OVERRIDE=""
DOCKER_COMPOSE_FILE_OVERRIDE=$1
nb_connect_services=0
if [ -f "${DOCKER_COMPOSE_FILE_OVERRIDE}" ]
then
  ENABLE_DOCKER_COMPOSE_FILE_OVERRIDE="-f ${DOCKER_COMPOSE_FILE_OVERRIDE}"
  set +e
  nb_connect_services=$(egrep -c "connect[0-9]+:" ${DOCKER_COMPOSE_FILE_OVERRIDE})
  set -e
  check_arm64_support "${DIR}" "${DOCKER_COMPOSE_FILE_OVERRIDE}"
fi

# Adding Schema Registry plugin profile
profile_schema_registry_command=""
if [ -z "$ENABLE_SR_MAVEN_PLUGIN_NODE" ]
then
  profile_schema_registry_command=""
else
  log " Starting Schema Registry plugin profile"
  profile_schema_registry_command="--profile sr_plugin_app"
fi

# defined 3 Connect variable and when profile is included/excluded
profile_connect_nodes_command=""
if [ -z "$ENABLE_CONNECT_NODES" ]
then
  :
elif [ ${nb_connect_services} -gt 1 ]
then 
  log "🥉 Multiple Connect nodes mode is enabled, connect2 and connect 3 containers will be started"
  profile_connect_nodes_command="--profile connect_nodes"
  export CONNECT_NODES_PROFILES="connect_nodes"
else
  if [ ! -f "${DOCKER_COMPOSE_FILE_OVERRIDE}" ]
  then
    log "🥉 Multiple connect nodes mode is enabled, connect2 and connect 3 containers will be started"
    profile_connect_nodes_command="--profile connect_nodes"
    export CONNECT_NODES_PROFILES="connect_nodes"
  else
    logerror "🛑 Could not find connect2 and connect3 in ${DOCKER_COMPOSE_FILE_OVERRIDE}. Update the yaml files to contain the connect2 && connect3 in ${DOCKER_COMPOSE_FILE_OVERRIDE}"
    exit 1
  fi
fi

docker compose -f ../../environment/plaintext/docker-compose.yml ${ENABLE_DOCKER_COMPOSE_FILE_OVERRIDE} build
docker compose -f ../../environment/plaintext/docker-compose.yml ${ENABLE_DOCKER_COMPOSE_FILE_OVERRIDE} down -v --remove-orphans
docker compose -f ../../environment/plaintext/docker-compose.yml ${ENABLE_DOCKER_COMPOSE_FILE_OVERRIDE} ${profile_control_center_command} ${profile_ksqldb_command} ${profile_grafana_command} ${profile_kcat_command} ${profile_conduktor_command} ${profile_sql_datagen_command} ${profile_connect_nodes_command} ${profile_kafka_nodes_command} ${profile_schema_registry_command} up -d
log "📝 To see the actual properties file, use cli command playground get-properties -c <container>"
command="source ${DIR}/../../scripts/utils.sh && docker compose -f ${DIR}/../../environment/plaintext/docker-compose.yml ${ENABLE_DOCKER_COMPOSE_FILE_OVERRIDE} ${profile_control_center_command} ${profile_ksqldb_command} ${profile_grafana_command} ${profile_kcat_command} ${profile_conduktor_command} ${profile_sql_datagen_command} ${profile_connect_nodes_command} ${profile_kafka_nodes_command} ${profile_schema_registry_command} up -d"
echo "$command" > /tmp/playground-command
log "✨ If you modify a docker-compose file and want to re-create the container(s), run cli command playground container recreate"


if [ "$#" -ne 0 ]
then
    shift
fi
../../scripts/wait-for-connect-and-controlcenter.sh $@

display_jmx_info