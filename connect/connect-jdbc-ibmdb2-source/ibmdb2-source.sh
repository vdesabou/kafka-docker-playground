#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if connect_cp_version_greater_than_8 && [ ! -z "$CONNECTOR_TAG" ] && ! version_gt $CONNECTOR_TAG "10.7.99"
then
     logwarn "minimal supported connector version is 10.8.0 for CP 8.0"
     logwarn "see https://docs.confluent.io/platform/current/connect/supported-connector-version-8.0.html#supported-connector-versions-in-cp-8-0"
     exit 111
fi

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

set_profiles
docker compose -f ../../environment/plaintext/docker-compose.yml ${KRAFT_DOCKER_COMPOSE_FILE_OVERRIDE} -f "${PWD}/docker-compose.plaintext.yml" ${profile_control_center_command} ${profile_ksqldb_command} ${profile_zookeeper_command}  ${profile_grafana_command} ${profile_kcat_command} down -v --remove-orphans
log "Starting up ibmdb2 container to get db2jcc4.jar"
docker compose -f ../../environment/plaintext/docker-compose.yml ${KRAFT_DOCKER_COMPOSE_FILE_OVERRIDE} -f "${PWD}/docker-compose.plaintext.yml" ${profile_control_center_command} ${profile_ksqldb_command} ${profile_zookeeper_command}  ${profile_grafana_command} ${profile_kcat_command} up -d ibmdb2

cd ../../connect/connect-jdbc-ibmdb2-source
rm -f db2jcc4.jar
log "Getting db2jcc4.jar"
docker cp ibmdb2:/opt/ibm/db2/V11.5/java/db2jcc4.jar db2jcc4.jar
cd -


playground container logs --container ibmdb2 --wait-for-log "Setup has completed" --max-wait 600
log "ibmdb2 DB has started!"

set_profiles
docker compose -f ../../environment/plaintext/docker-compose.yml ${KRAFT_DOCKER_COMPOSE_FILE_OVERRIDE} -f "${PWD}/docker-compose.plaintext.yml" ${profile_control_center_command} ${profile_ksqldb_command} ${profile_zookeeper_command}  ${profile_grafana_command} ${profile_kcat_command} up -d --quiet-pull
command="source ${DIR}/../../scripts/utils.sh && docker compose -f ${DIR}/../../environment/plaintext/docker-compose.yml ${KRAFT_DOCKER_COMPOSE_FILE_OVERRIDE} -f "${PWD}/docker-compose.plaintext.yml" ${profile_control_center_command} ${profile_ksqldb_command} ${profile_zookeeper_command}  ${profile_grafana_command} ${profile_kcat_command} up -d"
playground state set run.docker_command "$command"
playground state set run.environment "plaintext"
log "✨ If you modify a docker-compose file and want to re-create the container(s), run cli command 'playground container recreate'"


wait_container_ready

# Keep it for utils.sh
# PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
#playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.yml"

# sample DB is used https://www.ibm.com/docs/en/db2/11.5?topic=samples-sample-database
log "List tables"
docker exec -i ibmdb2 bash << EOF
su - db2inst1
db2 connect to sample user db2inst1 using passw0rd
db2 LIST TABLES
EOF

log "Creating JDBC IBM DB2 source connector"
playground connector create-or-update --connector ibmdb2-source  << EOF
{
  "connector.class": "io.confluent.connect.jdbc.JdbcSourceConnector",
  "tasks.max": "1",
  "connection.url":"jdbc:db2://ibmdb2:25010/sample",
  "connection.user":"db2inst1",
  "connection.password":"passw0rd",
  "mode": "bulk",
  "table.whitelist": "PURCHASEORDER",
  "topic.prefix": "db2-",
  "errors.log.enable": "true",
  "errors.log.include.messages": "true"
}
EOF


sleep 15

log "Verifying topic db2-PURCHASEORDER"
playground topic consume --topic db2-PURCHASEORDER --min-expected-messages 2 --timeout 60


