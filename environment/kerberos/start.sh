#!/bin/bash

set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

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
  KRAFT_KERBEROS_DOCKER_COMPOSE_FILE_OVERRIDE="-f ${DIR}/../../environment/kerberos/docker-compose-kraft.yml"
else
  # Zookeeper mode
  KRAFT_KERBEROS_DOCKER_COMPOSE_FILE_OVERRIDE=""
fi
# Starting kerberos,
# Avoiding starting up all services at the begining to generate the keytab first

docker compose -f ../../environment/plaintext/docker-compose.yml ${KRAFT_DOCKER_COMPOSE_FILE_OVERRIDE} -f ../../environment/kerberos/docker-compose.yml ${KRAFT_KERBEROS_DOCKER_COMPOSE_FILE_OVERRIDE} ${ENABLE_DOCKER_COMPOSE_FILE_OVERRIDE}  ${profile_control_center_command} ${profile_ksqldb_command} ${profile_zookeeper_command}  ${profile_grafana_command} ${profile_conduktor_command} ${profile_kafka_nodes_command} ${profile_connect_nodes_command} down -v --remove-orphans
docker compose -f ../../environment/plaintext/docker-compose.yml ${KRAFT_DOCKER_COMPOSE_FILE_OVERRIDE} -f ../../environment/kerberos/docker-compose.yml ${KRAFT_KERBEROS_DOCKER_COMPOSE_FILE_OVERRIDE} ${ENABLE_DOCKER_COMPOSE_FILE_OVERRIDE}  ${profile_control_center_command} ${profile_ksqldb_command} ${profile_zookeeper_command}  ${profile_grafana_command} ${profile_conduktor_command} ${profile_kafka_nodes_command} ${profile_connect_nodes_command} build kdc
docker compose -f ../../environment/plaintext/docker-compose.yml ${KRAFT_DOCKER_COMPOSE_FILE_OVERRIDE} -f ../../environment/kerberos/docker-compose.yml ${KRAFT_KERBEROS_DOCKER_COMPOSE_FILE_OVERRIDE} ${ENABLE_DOCKER_COMPOSE_FILE_OVERRIDE}  ${profile_control_center_command} ${profile_ksqldb_command} ${profile_zookeeper_command}  ${profile_grafana_command} ${profile_conduktor_command} ${profile_kafka_nodes_command} ${profile_connect_nodes_command} build client
docker compose -f ../../environment/plaintext/docker-compose.yml ${KRAFT_DOCKER_COMPOSE_FILE_OVERRIDE} -f ../../environment/kerberos/docker-compose.yml ${KRAFT_KERBEROS_DOCKER_COMPOSE_FILE_OVERRIDE} ${ENABLE_DOCKER_COMPOSE_FILE_OVERRIDE} up -d --quiet-pull kdc


docker exec -i kdc kadmin.local -w password -q "modprinc -maxrenewlife 11days +allow_renewable krbtgt/TEST.CONFLUENT.IO"  > /dev/null
### Create the required identities:
# Kafka service principal:
docker exec -i kdc kadmin.local -w password -q "add_principal -randkey kafka/broker.kerberos-demo.local@TEST.CONFLUENT.IO"  > /dev/null
docker exec -i kdc kadmin.local -w password -q "modprinc -maxlife 11days -maxrenewlife 11days +allow_renewable kafka/broker.kerberos-demo.local@TEST.CONFLUENT.IO"  > /dev/null
docker exec -i kdc kadmin.local -w password -q "add_principal -randkey kafka/broker2.kerberos-demo.local@TEST.CONFLUENT.IO"  > /dev/null
docker exec -i kdc kadmin.local -w password -q "modprinc -maxlife 11days -maxrenewlife 11days +allow_renewable kafka/broker2.kerberos-demo.local@TEST.CONFLUENT.IO"  > /dev/null
docker exec -i kdc kadmin.local -w password -q "add_principal -randkey kafka/broker3.kerberos-demo.local@TEST.CONFLUENT.IO"  > /dev/null
docker exec -i kdc kadmin.local -w password -q "modprinc -maxlife 11days -maxrenewlife 11days +allow_renewable kafka/broker3.kerberos-demo.local@TEST.CONFLUENT.IO"  > /dev/null

# Zookeeper service principal:
docker exec -i kdc kadmin.local -w password -q "add_principal -randkey zookeeper/zookeeper.kerberos-demo.local@TEST.CONFLUENT.IO"  > /dev/null
docker exec -i kdc kadmin.local -w password -q "modprinc -maxlife 11days -maxrenewlife 11days +allow_renewable zookeeper/zookeeper.kerberos-demo.local@TEST.CONFLUENT.IO"  > /dev/null

# Create a principal with which to connect to Zookeeper from brokers - NB use the same credential on all brokers!
docker exec -i kdc kadmin.local -w password -q "add_principal -randkey zkclient@TEST.CONFLUENT.IO"  > /dev/null
docker exec -i kdc kadmin.local -w password -q "modprinc -maxlife 11days -maxrenewlife 11days +allow_renewable zkclient@TEST.CONFLUENT.IO"  > /dev/null

# Create client principals to connect in to the cluster:
docker exec -i kdc kadmin.local -w password -q "add_principal -randkey kafka_producer@TEST.CONFLUENT.IO"  > /dev/null
docker exec -i kdc kadmin.local -w password -q "modprinc -maxlife 11days -maxrenewlife 11days +allow_renewable kafka_producer@TEST.CONFLUENT.IO"  > /dev/null
docker exec -i kdc kadmin.local -w password -q "add_principal -randkey kafka_producer/instance_demo@TEST.CONFLUENT.IO"  > /dev/null
docker exec -i kdc kadmin.local -w password -q "modprinc -maxlife 11days -maxrenewlife 11days +allow_renewable kafka_producer/instance_demo@TEST.CONFLUENT.IO"  > /dev/null
docker exec -i kdc kadmin.local -w password -q "add_principal -randkey kafka_consumer@TEST.CONFLUENT.IO"  > /dev/null
docker exec -i kdc kadmin.local -w password -q "modprinc -maxlife 11days -maxrenewlife 11days +allow_renewable kafka_consumer@TEST.CONFLUENT.IO"  > /dev/null
docker exec -i kdc kadmin.local -w password -q "add_principal -randkey connect@TEST.CONFLUENT.IO"  > /dev/null
docker exec -i kdc kadmin.local -w password -q "modprinc -maxlife 11days -maxrenewlife 11days +allow_renewable connect@TEST.CONFLUENT.IO"  > /dev/null
docker exec -i kdc kadmin.local -w password -q "add_principal -randkey schemaregistry@TEST.CONFLUENT.IO"  > /dev/null
docker exec -i kdc kadmin.local -w password -q "modprinc -maxlife 11days -maxrenewlife 11days +allow_renewable schemaregistry@TEST.CONFLUENT.IO"  > /dev/null
docker exec -i kdc kadmin.local -w password -q "add_principal -randkey ksqldb@TEST.CONFLUENT.IO"  > /dev/null
docker exec -i kdc kadmin.local -w password -q "modprinc -maxlife 11days -maxrenewlife 11days +allow_renewable ksqldb@TEST.CONFLUENT.IO"  > /dev/null
docker exec -i kdc kadmin.local -w password -q "add_principal -randkey controlcenter@TEST.CONFLUENT.IO"  > /dev/null
docker exec -i kdc kadmin.local -w password -q "modprinc -maxlife 11days -maxrenewlife 11days +allow_renewable controlcenter@TEST.CONFLUENT.IO"  > /dev/null
docker exec -i kdc kadmin.local -w password -q "add_principal -randkey conduktor@TEST.CONFLUENT.IO"  > /dev/null
docker exec -i kdc kadmin.local -w password -q "modprinc -maxlife 11days -maxrenewlife 11days +allow_renewable conduktor@TEST.CONFLUENT.IO"  > /dev/null

# Create an admin principal for the cluster, which we'll use to setup ACLs.
# Look after this - its also declared a super user in broker config.
docker exec -i kdc kadmin.local -w password -q "add_principal -randkey admin/for-kafka@TEST.CONFLUENT.IO"  > /dev/null
docker exec -i kdc kadmin.local -w password -q "modprinc -maxlife 11days -maxrenewlife 11days +allow_renewable admin/for-kafka@TEST.CONFLUENT.IO"  > /dev/null

# Create keytabs to use for Kafka
log "Create keytabs"
docker exec -i kdc rm -f /var/lib/secret/broker.key 2>&1 > /dev/null
docker exec -i kdc rm -f /var/lib/secret/broker2.key 2>&1 > /dev/null
docker exec -i kdc rm -f /var/lib/secret/broker3.key 2>&1 > /dev/null
docker exec -i kdc rm -f /var/lib/secret/zookeeper.key 2>&1 > /dev/null
docker exec -i kdc rm -f /var/lib/secret/zookeeper-client.key 2>&1 > /dev/null
docker exec -i kdc rm -f /var/lib/secret/kafka-client.key 2>&1 > /dev/null
docker exec -i kdc rm -f /var/lib/secret/kafka-admin.key 2>&1 > /dev/null
docker exec -i kdc rm -f /var/lib/secret/kafka-connect.key 2>&1 > /dev/null
docker exec -i kdc rm -f /var/lib/secret/kafka-schemaregistry.key 2>&1 > /dev/null
docker exec -i kdc rm -f /var/lib/secret/kafka-ksqldb.key 2>&1 > /dev/null
docker exec -i kdc rm -f /var/lib/secret/kafka-controlcenter.key 2>&1 > /dev/null
docker exec -i kdc rm -f /var/lib/secret/kafka-conduktor.key 2>&1 > /dev/null

docker exec -i kdc kadmin.local -w password -q "ktadd  -k /var/lib/secret/broker.key -norandkey kafka/broker.kerberos-demo.local@TEST.CONFLUENT.IO " > /dev/null
docker exec -i kdc kadmin.local -w password -q "ktadd  -k /var/lib/secret/broker2.key -norandkey kafka/broker2.kerberos-demo.local@TEST.CONFLUENT.IO " > /dev/null
docker exec -i kdc kadmin.local -w password -q "ktadd  -k /var/lib/secret/broker3.key -norandkey kafka/broker3.kerberos-demo.local@TEST.CONFLUENT.IO " > /dev/null
docker exec -i kdc kadmin.local -w password -q "ktadd  -k /var/lib/secret/zookeeper.key -norandkey zookeeper/zookeeper.kerberos-demo.local@TEST.CONFLUENT.IO " > /dev/null
docker exec -i kdc kadmin.local -w password -q "ktadd  -k /var/lib/secret/zookeeper-client.key -norandkey zkclient@TEST.CONFLUENT.IO " > /dev/null
docker exec -i kdc kadmin.local -w password -q "ktadd  -k /var/lib/secret/kafka-client.key -norandkey kafka_producer@TEST.CONFLUENT.IO " > /dev/null
docker exec -i kdc kadmin.local -w password -q "ktadd  -k /var/lib/secret/kafka-client.key -norandkey kafka_producer/instance_demo@TEST.CONFLUENT.IO " > /dev/null
docker exec -i kdc kadmin.local -w password -q "ktadd  -k /var/lib/secret/kafka-client.key -norandkey kafka_consumer@TEST.CONFLUENT.IO " > /dev/null
docker exec -i kdc kadmin.local -w password -q "ktadd  -k /var/lib/secret/kafka-admin.key -norandkey admin/for-kafka@TEST.CONFLUENT.IO " > /dev/null
docker exec -i kdc kadmin.local -w password -q "ktadd  -k /var/lib/secret/kafka-connect.key -norandkey connect@TEST.CONFLUENT.IO " > /dev/null
docker exec -i kdc kadmin.local -w password -q "ktadd  -k /var/lib/secret/kafka-schemaregistry.key -norandkey schemaregistry@TEST.CONFLUENT.IO " > /dev/null
docker exec -i kdc kadmin.local -w password -q "ktadd  -k /var/lib/secret/kafka-ksqldb.key -norandkey ksqldb@TEST.CONFLUENT.IO " > /dev/null
docker exec -i kdc kadmin.local -w password -q "ktadd  -k /var/lib/secret/kafka-controlcenter.key -norandkey controlcenter@TEST.CONFLUENT.IO " > /dev/null
docker exec -i kdc kadmin.local -w password -q "ktadd  -k /var/lib/secret/kafka-conduktor.key -norandkey conduktor@TEST.CONFLUENT.IO " > /dev/null

if [[ "$TAG" == *ubi8 ]] || version_gt $TAG_BASE "5.9.0"
then
  # https://github.com/vdesabou/kafka-docker-playground/issues/10
  # keytabs are created on kdc with root user
  # ubi8 images are using appuser user
  # starting from 6.0, all images are ubi8
  docker exec -i kdc chmod a+r /var/lib/secret/broker.key
  docker exec -i kdc chmod a+r /var/lib/secret/broker2.key
  docker exec -i kdc chmod a+r /var/lib/secret/broker3.key
  docker exec -i kdc chmod a+r /var/lib/secret/zookeeper.key
  docker exec -i kdc chmod a+r /var/lib/secret/zookeeper-client.key
  docker exec -i kdc chmod a+r /var/lib/secret/kafka-client.key
  docker exec -i kdc chmod a+r /var/lib/secret/kafka-admin.key
  docker exec -i kdc chmod a+r /var/lib/secret/kafka-connect.key
  docker exec -i kdc chmod a+r /var/lib/secret/kafka-schemaregistry.key
  docker exec -i kdc chmod a+r /var/lib/secret/kafka-ksqldb.key
  docker exec -i kdc chmod a+r /var/lib/secret/kafka-controlcenter.key
  docker exec -i kdc chmod a+r /var/lib/secret/kafka-conduktor.key
fi

# Starting zookeeper and kafka now that the keytab has been created with the required credentials and services
docker compose -f ../../environment/plaintext/docker-compose.yml ${KRAFT_DOCKER_COMPOSE_FILE_OVERRIDE} -f ../../environment/kerberos/docker-compose.yml ${KRAFT_KERBEROS_DOCKER_COMPOSE_FILE_OVERRIDE} ${ENABLE_DOCKER_COMPOSE_FILE_OVERRIDE}  ${profile_control_center_command} ${profile_ksqldb_command} ${profile_zookeeper_command}  ${profile_grafana_command} ${profile_conduktor_command} ${profile_kafka_nodes_command} ${profile_connect_nodes_command} build
docker compose -f ../../environment/plaintext/docker-compose.yml ${KRAFT_DOCKER_COMPOSE_FILE_OVERRIDE} -f ../../environment/kerberos/docker-compose.yml ${KRAFT_KERBEROS_DOCKER_COMPOSE_FILE_OVERRIDE} ${ENABLE_DOCKER_COMPOSE_FILE_OVERRIDE} ${profile_control_center_command} ${profile_ksqldb_command} ${profile_zookeeper_command}  ${profile_grafana_command} ${profile_kcat_command} ${profile_conduktor_command} ${profile_kafka_nodes_command} ${profile_connect_nodes_command} up -d --quiet-pull
log "📝 To see the actual properties file, use cli command 'playground container get-properties -c <container>'"
command="source ${DIR}/../../scripts/utils.sh && docker compose -f ${DIR}/../../environment/plaintext/docker-compose.yml  ${KRAFT_DOCKER_COMPOSE_FILE_OVERRIDE} -f ../../environment/kerberos/docker-compose.yml ${KRAFT_KERBEROS_DOCKER_COMPOSE_FILE_OVERRIDE} ${ENABLE_DOCKER_COMPOSE_FILE_OVERRIDE} ${profile_control_center_command} ${profile_ksqldb_command} ${profile_zookeeper_command}  ${profile_grafana_command} ${profile_kcat_command} ${profile_conduktor_command} ${profile_kafka_nodes_command}${profile_connect_nodes_command} up -d --quiet-pull"
playground state set run.docker_command "$command"
playground state set run.environment "kerberos"
log "✨ If you modify a docker-compose file and want to re-create the container(s), run cli command 'playground container recreate'"

wait_container_ready

display_jmx_info

# Adding ACLs for consumer and producer user:
docker exec client bash -c "kinit -k -t /var/lib/secret/kafka-admin.key admin/for-kafka && kafka-acls --bootstrap-server broker:9092 --command-config /etc/kafka/command.properties --add --allow-principal User:kafka_producer --producer --topic=*"
docker exec client bash -c "kinit -k -t /var/lib/secret/kafka-admin.key admin/for-kafka && kafka-acls --bootstrap-server broker:9092 --command-config /etc/kafka/command.properties --add --allow-principal User:kafka_consumer --consumer --topic=* --group=*"
# Adding ACLs for connect user:
docker exec client bash -c "kinit -k -t /var/lib/secret/kafka-admin.key admin/for-kafka && kafka-acls --bootstrap-server broker:9092 --command-config /etc/kafka/command.properties --add --allow-principal User:connect --consumer --topic=* --group=*"
docker exec client bash -c "kinit -k -t /var/lib/secret/kafka-admin.key admin/for-kafka && kafka-acls --bootstrap-server broker:9092 --command-config /etc/kafka/command.properties --add --allow-principal User:connect --producer --topic=*"
# schemaregistry and controlcenter is super user
