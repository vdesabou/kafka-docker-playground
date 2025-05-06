#!/bin/bash

set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if [[ $CP_CONNECT_IMAGE == *"cp-kafka-"* ]] || [[ $CP_KAFKA_IMAGE == *"cp-kafka" ]]
then
  logwarn "LDAP Authorizer is not available with community image"
  exit 111
fi

verify_docker_and_memory

check_docker_compose_version
check_bash_version
check_and_update_playground_version
nb_connect_services=0
ENABLE_DOCKER_COMPOSE_FILE_OVERRIDE=""
DOCKER_COMPOSE_FILE_OVERRIDE=$1
if [ -f "${DOCKER_COMPOSE_FILE_OVERRIDE}" ]
then
  ENABLE_DOCKER_COMPOSE_FILE_OVERRIDE="-f ${DOCKER_COMPOSE_FILE_OVERRIDE}"
  set +e
  nb_connect_services=$(egrep -c "connect[0-9]+:" ${DOCKER_COMPOSE_FILE_OVERRIDE})
  set -e
  check_arm64_support "${DIR}" "${DOCKER_COMPOSE_FILE_OVERRIDE}"
fi
set_profiles

if [ ! -z $ENABLE_KRAFT ]
then
  # KRAFT mode
  KRAFT_LDAP_AUTHORIZER_DOCKER_COMPOSE_FILE_OVERRIDE="-f ${DIR}/../../environment/ldap-authorizer-sasl-plain/docker-compose-kraft.yml"
else
  # Zookeeper mode
  KRAFT_LDAP_AUTHORIZER_DOCKER_COMPOSE_FILE_OVERRIDE=""
fi

docker compose -f ../../environment/plaintext/docker-compose.yml ${KRAFT_DOCKER_COMPOSE_FILE_OVERRIDE} -f ../../environment/sasl-plain/docker-compose.yml -f ../../environment/ldap-authorizer-sasl-plain/docker-compose.yml ${KRAFT_LDAP_AUTHORIZER_DOCKER_COMPOSE_FILE_OVERRIDE} ${ENABLE_DOCKER_COMPOSE_FILE_OVERRIDE}  ${profile_control_center_command} ${profile_ksqldb_command} ${profile_zookeeper_command}  ${profile_grafana_command} ${profile_conduktor_command} ${profile_kafka_nodes_command} ${profile_connect_nodes_command} build
docker compose -f ../../environment/plaintext/docker-compose.yml ${KRAFT_DOCKER_COMPOSE_FILE_OVERRIDE} -f ../../environment/sasl-plain/docker-compose.yml -f ../../environment/ldap-authorizer-sasl-plain/docker-compose.yml ${KRAFT_LDAP_AUTHORIZER_DOCKER_COMPOSE_FILE_OVERRIDE} ${ENABLE_DOCKER_COMPOSE_FILE_OVERRIDE}  ${profile_control_center_command} ${profile_ksqldb_command} ${profile_zookeeper_command}  ${profile_grafana_command} ${profile_conduktor_command} ${profile_kafka_nodes_command} ${profile_connect_nodes_command} down -v --remove-orphans
docker compose -f ../../environment/plaintext/docker-compose.yml ${KRAFT_DOCKER_COMPOSE_FILE_OVERRIDE} -f ../../environment/sasl-plain/docker-compose.yml -f ../../environment/ldap-authorizer-sasl-plain/docker-compose.yml ${KRAFT_LDAP_AUTHORIZER_DOCKER_COMPOSE_FILE_OVERRIDE} ${ENABLE_DOCKER_COMPOSE_FILE_OVERRIDE} ${profile_control_center_command} ${profile_ksqldb_command} ${profile_zookeeper_command}  ${profile_grafana_command} ${profile_kcat_command} ${profile_kafka_nodes_command} ${profile_connect_nodes_command} up -d --quiet-pull
log "📝 To see the actual properties file, use cli command 'playground container get-properties -c <container>'"
command="source ${DIR}/../../scripts/utils.sh && docker compose -f ${DIR}/../../environment/plaintext/docker-compose.yml ${KRAFT_DOCKER_COMPOSE_FILE_OVERRIDE} -f ${DIR}/../../environment/sasl-plain/docker-compose.yml -f ../../environment/ldap-authorizer-sasl-plain/docker-compose.yml ${KRAFT_LDAP_AUTHORIZER_DOCKER_COMPOSE_FILE_OVERRIDE} ${ENABLE_DOCKER_COMPOSE_FILE_OVERRIDE} ${profile_control_center_command} ${profile_ksqldb_command} ${profile_zookeeper_command}  ${profile_grafana_command} ${profile_kcat_command} ${profile_kafka_nodes_command} ${profile_connect_nodes_command} up -d --quiet-pull"
playground state set run.docker_command "$command"
playground state set run.environment "ldap-authorizer-sasl-plain"
log "✨ If you modify a docker-compose file and want to re-create the container(s), run cli command 'playground container recreate'"

wait_container_ready

display_jmx_info

# Not required as User:broker is super user
# SET ACLs
# Authorize broker user kafka for cluster operations. Note that the example uses user-principal based ACL for brokers, but brokers may also be configured to use group-based ACLs.
#docker exec broker kafka-acls --bootstrap-server broker:9092 --add --cluster --operation=All --allow-principal=User:broker

# Test LDAP group-based authorization
# https://docs.confluent.io/current/security/ldap-authorizer/quickstart.html#test-ldap-group-based-authorization
log "Create topic testtopic"
docker exec broker kafka-topics --create --topic testtopic --partitions 10 --replication-factor 1 --bootstrap-server broker:9092 --command-config /service/kafka/users/kafka.properties

log "Run console producer without authorizing user client: SHOULD FAIL"
docker exec -i broker kafka-console-producer --bootstrap-server broker:9092 --topic testtopic --producer.config /service/kafka/users/client.properties << EOF
message client
EOF

log "Authorize group Group:KafkaDevelopers and rerun producer for client: SHOULD BE SUCCESS"
docker exec broker kafka-acls --bootstrap-server broker:9092 --add --topic=testtopic --producer --allow-principal="Group:KafkaDevelopers" --command-config /service/kafka/users/kafka.properties

sleep 1

docker exec -i broker kafka-console-producer --bootstrap-server broker:9092 --topic testtopic --producer.config /service/kafka/users/client.properties << EOF
message client
EOF

log "Run console consumer without access to consumer group: SHOULD FAIL"
# Consume should fail authorization since neither user client nor the group KafkaDevelopers that client belongs to has authorization to consume using the group test-consumer-group
timeout 60 docker exec broker kafka-console-consumer --bootstrap-server broker:9092 --topic testtopic --from-beginning --group test-consumer-group --consumer.config /service/kafka/users/client.properties --max-messages 1

log "Authorize group and rerun consumer"
docker exec broker kafka-acls --bootstrap-server broker:9092 --add --topic=testtopic --group test-consumer-group --allow-principal="Group:KafkaDevelopers" --command-config /service/kafka/users/kafka.properties
timeout 60 docker exec broker kafka-console-consumer --bootstrap-server broker:9092 --topic testtopic --from-beginning --group test-consumer-group --consumer.config /service/kafka/users/client.properties --max-messages 1

log "Run console producer with authorized user barnie (barnie is in group): SHOULD BE SUCCESS"
docker exec -i broker kafka-console-producer --bootstrap-server broker:9092 --topic testtopic --producer.config /service/kafka/users/barnie.properties << EOF
message Barnie
EOF

log "Run console producer without authorizing user (charlie is NOT in group): SHOULD FAIL"
docker exec -i broker kafka-console-producer --bootstrap-server broker:9092 --topic testtopic --producer.config /service/kafka/users/charlie.properties << EOF
message Charlie
EOF

log "Listing ACLs"
docker exec broker kafka-acls --bootstrap-server broker:9092 --list --command-config /service/kafka/users/kafka.properties
