#!/bin/bash

set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

verify_docker_and_memory
verify_installed "docker-compose"
check_docker_compose_version

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

ENABLE_DOCKER_COMPOSE_FILE_OVERRIDE=""
DOCKER_COMPOSE_FILE_OVERRIDE=$1
if [ -f "${DOCKER_COMPOSE_FILE_OVERRIDE}" ]
then
  ENABLE_DOCKER_COMPOSE_FILE_OVERRIDE="-f ${DOCKER_COMPOSE_FILE_OVERRIDE}"
  check_arm64_support "${DIR}" "${DOCKER_COMPOSE_FILE_OVERRIDE}"
fi

docker-compose -f ../../environment/plaintext/docker-compose.yml -f ../../environment/sasl-plain/docker-compose.yml -f ../../environment/ldap-authorizer-sasl-plain/docker-compose.yml ${ENABLE_DOCKER_COMPOSE_FILE_OVERRIDE} build
docker-compose -f ../../environment/plaintext/docker-compose.yml -f ../../environment/sasl-plain/docker-compose.yml -f ../../environment/ldap-authorizer-sasl-plain/docker-compose.yml ${ENABLE_DOCKER_COMPOSE_FILE_OVERRIDE} down -v --remove-orphans
docker-compose -f ../../environment/plaintext/docker-compose.yml -f ../../environment/sasl-plain/docker-compose.yml -f ../../environment/ldap-authorizer-sasl-plain/docker-compose.yml ${ENABLE_DOCKER_COMPOSE_FILE_OVERRIDE} ${profile_control_center_command} ${profile_ksqldb_command} ${profile_grafana_command} ${profile_kcat_command} up -d
log "📝 To see the actual properties file, use cli command playground get-properties -c <container>"
command="source ${DIR}/../../scripts/utils.sh && docker-compose -f ${DIR}/../../environment/plaintext/docker-compose.yml -f ${DIR}/../../environment/sasl-plain/docker-compose.yml -f ../../environment/ldap-authorizer-sasl-plain/docker-compose.yml ${ENABLE_DOCKER_COMPOSE_FILE_OVERRIDE} ${profile_control_center_command} ${profile_ksqldb_command} ${profile_grafana_command} ${profile_kcat_command} up -d"
echo "$command" > /tmp/playground-command
log "✨ If you modify a docker-compose file and want to re-create the container(s), run cli command playground container recreate"


if [ "$#" -ne 0 ]
then
    shift
fi
../../scripts/wait-for-connect-and-controlcenter.sh $@

display_jmx_info

# Not required as User:broker is super user
# SET ACLs
# Authorize broker user kafka for cluster operations. Note that the example uses user-principal based ACL for brokers, but brokers may also be configured to use group-based ACLs.
#docker exec broker kafka-acls --bootstrap-server broker:9092 --add --cluster --operation=All --allow-principal=User:broker

# Test LDAP group-based authorization
# https://docs.confluent.io/current/security/ldap-authorizer/quickstart.html#test-ldap-group-based-authorization
log "Create topic testtopic"
docker exec broker kafka-topics --create --topic testtopic --partitions 10 --replication-factor 1 --bootstrap-server broker:9092 --command-config /service/kafka/users/kafka.properties

log "Run console producer without authorizing user alice: SHOULD FAIL"
docker exec -i broker kafka-console-producer --broker-list broker:9092 --topic testtopic --producer.config /service/kafka/users/alice.properties << EOF
message Alice
EOF

log "Authorize group Group:KafkaDevelopers and rerun producer for alice: SHOULD BE SUCCESS"
docker exec broker kafka-acls --bootstrap-server broker:9092 --add --topic=testtopic --producer --allow-principal="Group:KafkaDevelopers" --command-config /service/kafka/users/kafka.properties

sleep 1

docker exec -i broker kafka-console-producer --broker-list broker:9092 --topic testtopic --producer.config /service/kafka/users/alice.properties << EOF
message Alice
EOF

log "Run console consumer without access to consumer group: SHOULD FAIL"
# Consume should fail authorization since neither user alice nor the group KafkaDevelopers that alice belongs to has authorization to consume using the group test-consumer-group
timeout 60 docker exec broker kafka-console-consumer --bootstrap-server broker:9092 --topic testtopic --from-beginning --group test-consumer-group --consumer.config /service/kafka/users/alice.properties --max-messages 1

log "Authorize group and rerun consumer"
docker exec broker kafka-acls --bootstrap-server broker:9092 --add --topic=testtopic --group test-consumer-group --allow-principal="Group:KafkaDevelopers" --command-config /service/kafka/users/kafka.properties
timeout 60 docker exec broker kafka-console-consumer --bootstrap-server broker:9092 --topic testtopic --from-beginning --group test-consumer-group --consumer.config /service/kafka/users/alice.properties --max-messages 1

log "Run console producer with authorized user barnie (barnie is in group): SHOULD BE SUCCESS"
docker exec -i broker kafka-console-producer --broker-list broker:9092 --topic testtopic --producer.config /service/kafka/users/barnie.properties << EOF
message Barnie
EOF

log "Run console producer without authorizing user (charlie is NOT in group): SHOULD FAIL"
docker exec -i broker kafka-console-producer --broker-list broker:9092 --topic testtopic --producer.config /service/kafka/users/charlie.properties << EOF
message Charlie
EOF

log "Listing ACLs"
docker exec broker kafka-acls --bootstrap-server broker:9092 --list --command-config /service/kafka/users/kafka.properties
