#!/bin/bash

set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

verify_docker_and_memory

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
  DISABLE_REPLICATOR_MONITORING="-f ../../environment/mdc-plaintext/docker-compose.no-replicator-monitoring.yml"
else
  log "🎱 Installing replicator confluentinc/kafka-connect-replicator:$TAG for Replicator Monitoring"
  docker run -u0 -i --rm -v ${DIR}/../../confluent-hub:/usr/share/confluent-hub-components ${CP_CONNECT_IMAGE}:${CONNECT_TAG} bash -c "confluent-hub install --no-prompt confluentinc/kafka-connect-replicator:$TAG && chown -R $(id -u $USER):$(id -g $USER) /usr/share/confluent-hub-components"
fi

docker compose -f ../../environment/mdc-plaintext/docker-compose.yml -f ../../environment/mdc-kerberos/docker-compose.kerberos.yml ${ENABLE_DOCKER_COMPOSE_FILE_OVERRIDE} ${DISABLE_REPLICATOR_MONITORING} down -v --remove-orphans
docker compose -f ../../environment/mdc-plaintext/docker-compose.yml -f ../../environment/mdc-kerberos/docker-compose.kerberos.yml ${ENABLE_DOCKER_COMPOSE_FILE_OVERRIDE} ${DISABLE_REPLICATOR_MONITORING} build kdc
docker compose -f ../../environment/mdc-plaintext/docker-compose.yml -f ../../environment/mdc-kerberos/docker-compose.kerberos.yml ${ENABLE_DOCKER_COMPOSE_FILE_OVERRIDE} ${DISABLE_REPLICATOR_MONITORING} build client
docker compose -f ../../environment/mdc-plaintext/docker-compose.yml -f ../../environment/mdc-kerberos/docker-compose.kerberos.yml ${ENABLE_DOCKER_COMPOSE_FILE_OVERRIDE} ${DISABLE_REPLICATOR_MONITORING} ${profile_control_center_command} up -d kdc

### Create the required identities:
# Kafka service principal:
docker exec -i kdc kadmin.local -w password -q "add_principal -randkey kafka/broker-us.kerberos-demo.local@TEST.CONFLUENT.IO"  > /dev/null
docker exec -i kdc kadmin.local -w password -q "add_principal -randkey kafka/broker-europe.kerberos-demo.local@TEST.CONFLUENT.IO"  > /dev/null

# Zookeeper service principal:
docker exec -i kdc kadmin.local -w password -q "add_principal -randkey zookeeper/zookeeper-us.kerberos-demo.local@TEST.CONFLUENT.IO"  > /dev/null
docker exec -i kdc kadmin.local -w password -q "add_principal -randkey zookeeper/zookeeper-europe.kerberos-demo.local@TEST.CONFLUENT.IO"  > /dev/null

# Create a principal with which to connect to Zookeeper from brokers - NB use the same credential on all brokers!
docker exec -i kdc kadmin.local -w password -q "add_principal -randkey zkclient@TEST.CONFLUENT.IO"  > /dev/null

# Create client principals to connect in to the cluster:
docker exec -i kdc kadmin.local -w password -q "add_principal -randkey kafka_producer@TEST.CONFLUENT.IO"  > /dev/null
docker exec -i kdc kadmin.local -w password -q "add_principal -randkey kafka_producer/instance_demo@TEST.CONFLUENT.IO"  > /dev/null
docker exec -i kdc kadmin.local -w password -q "add_principal -randkey kafka_consumer@TEST.CONFLUENT.IO"  > /dev/null
docker exec -i kdc kadmin.local -w password -q "add_principal -randkey connect@TEST.CONFLUENT.IO"  > /dev/null
docker exec -i kdc kadmin.local -w password -q "add_principal -randkey controlcenter@TEST.CONFLUENT.IO"  > /dev/null

# Create an admin principal for the cluster, which we'll use to setup ACLs.
# Look after this - its also declared a super user in broker config.
docker exec -i kdc kadmin.local -w password -q "add_principal -randkey admin/for-kafka@TEST.CONFLUENT.IO"  > /dev/null


# Create keytabs to use for Kafka
log "Create keytabs"
docker exec -i kdc rm -f /var/lib/secret/broker-us.key 2>&1 > /dev/null
docker exec -i kdc rm -f /var/lib/secret/broker-europe.key 2>&1 > /dev/null
docker exec -i kdc rm -f /var/lib/secret/zookeeper-us.key 2>&1 > /dev/null
docker exec -i kdc rm -f /var/lib/secret/zookeeper-europe.key 2>&1 > /dev/null
docker exec -i kdc rm -f /var/lib/secret/zookeeper-client.key 2>&1 > /dev/null
docker exec -i kdc rm -f /var/lib/secret/kafka-client.key 2>&1 > /dev/null
docker exec -i kdc rm -f /var/lib/secret/kafka-admin.key 2>&1 > /dev/null
docker exec -i kdc rm -f /var/lib/secret/kafka-connect.key 2>&1 > /dev/null
docker exec -i kdc rm -f /var/lib/secret/kafka-controlcenter.key 2>&1 > /dev/null

docker exec -i kdc kadmin.local -w password -q "ktadd  -k /var/lib/secret/broker-us.key -norandkey kafka/broker-us.kerberos-demo.local@TEST.CONFLUENT.IO " > /dev/null
docker exec -i kdc kadmin.local -w password -q "ktadd  -k /var/lib/secret/broker-europe.key -norandkey kafka/broker-europe.kerberos-demo.local@TEST.CONFLUENT.IO " > /dev/null
docker exec -i kdc kadmin.local -w password -q "ktadd  -k /var/lib/secret/zookeeper-us.key -norandkey zookeeper/zookeeper-us.kerberos-demo.local@TEST.CONFLUENT.IO " > /dev/null
docker exec -i kdc kadmin.local -w password -q "ktadd  -k /var/lib/secret/zookeeper-europe.key -norandkey zookeeper/zookeeper-europe.kerberos-demo.local@TEST.CONFLUENT.IO " > /dev/null
docker exec -i kdc kadmin.local -w password -q "ktadd  -k /var/lib/secret/zookeeper-client.key -norandkey zkclient@TEST.CONFLUENT.IO " > /dev/null
docker exec -i kdc kadmin.local -w password -q "ktadd  -k /var/lib/secret/kafka-client.key -norandkey kafka_producer@TEST.CONFLUENT.IO " > /dev/null
docker exec -i kdc kadmin.local -w password -q "ktadd  -k /var/lib/secret/kafka-client.key -norandkey kafka_producer/instance_demo@TEST.CONFLUENT.IO " > /dev/null
docker exec -i kdc kadmin.local -w password -q "ktadd  -k /var/lib/secret/kafka-client.key -norandkey kafka_consumer@TEST.CONFLUENT.IO " > /dev/null
docker exec -i kdc kadmin.local -w password -q "ktadd  -k /var/lib/secret/kafka-admin.key -norandkey admin/for-kafka@TEST.CONFLUENT.IO " > /dev/null
docker exec -i kdc kadmin.local -w password -q "ktadd  -k /var/lib/secret/kafka-connect.key -norandkey connect@TEST.CONFLUENT.IO " > /dev/null
docker exec -i kdc kadmin.local -w password -q "ktadd  -k /var/lib/secret/kafka-controlcenter.key -norandkey controlcenter@TEST.CONFLUENT.IO " > /dev/null

if [[ "$TAG" == *ubi8 ]]  || version_gt $TAG_BASE "5.9.0"
then
  # https://github.com/vdesabou/kafka-docker-playground/issues/10
  # keytabs are created on kdc with root user
  # ubi8 images are using appuser user
  docker exec -i kdc chmod a+r /var/lib/secret/broker-us.key
  docker exec -i kdc chmod a+r /var/lib/secret/broker-europe.key
  docker exec -i kdc chmod a+r /var/lib/secret/zookeeper-us.key
  docker exec -i kdc chmod a+r /var/lib/secret/zookeeper-europe.key
  docker exec -i kdc chmod a+r /var/lib/secret/zookeeper-client.key
  docker exec -i kdc chmod a+r /var/lib/secret/kafka-client.key
  docker exec -i kdc chmod a+r /var/lib/secret/kafka-admin.key
  docker exec -i kdc chmod a+r /var/lib/secret/kafka-connect.key
  docker exec -i kdc chmod a+r /var/lib/secret/kafka-controlcenter.key
fi

docker compose -f ../../environment/mdc-plaintext/docker-compose.yml -f ../../environment/mdc-kerberos/docker-compose.kerberos.yml ${ENABLE_DOCKER_COMPOSE_FILE_OVERRIDE} ${DISABLE_REPLICATOR_MONITORING} build
docker compose -f ../../environment/mdc-plaintext/docker-compose.yml -f ../../environment/mdc-kerberos/docker-compose.kerberos.yml ${ENABLE_DOCKER_COMPOSE_FILE_OVERRIDE} ${DISABLE_REPLICATOR_MONITORING} ${profile_control_center_command} up -d
log "📝 To see the actual properties file, use cli command playground get-properties -c <container>"
command="source ${DIR}/../../scripts/utils.sh && docker compose -f ${DIR}/../../environment/mdc-plaintext/docker-compose.yml -f ${DIR}/../../environment/mdc-kerberos/docker-compose.kerberos.yml ${ENABLE_DOCKER_COMPOSE_FILE_OVERRIDE} ${DISABLE_REPLICATOR_MONITORING} ${profile_control_center_command} up -d"
playground state set run.docker_command "$command"
playground state set run.environment "mdc-kerberos"
log "✨ If you modify a docker-compose file and want to re-create the container(s), run cli command playground container recreate"


if [ "$#" -ne 0 ]
then
    shift
fi
../../scripts/wait-for-connect-and-controlcenter.sh connect-us $@
../../scripts/wait-for-connect-and-controlcenter.sh connect-europe $@


# Adding ACLs for consumer and producer user:
docker exec client bash -c "kinit -k -t /var/lib/secret/kafka-admin.key admin/for-kafka && kafka-acls --bootstrap-server broker-us:9092 --command-config /etc/kafka/command-us.properties --add --allow-principal User:kafka_producer --producer --topic=*"
docker exec client bash -c "kinit -k -t /var/lib/secret/kafka-admin.key admin/for-kafka && kafka-acls --bootstrap-server broker-us:9092 --command-config /etc/kafka/command-us.properties --add --allow-principal User:kafka_consumer --consumer --topic=* --group=*"
# Adding ACLs for connect user:
docker exec client bash -c "kinit -k -t /var/lib/secret/kafka-admin.key admin/for-kafka && kafka-acls --bootstrap-server broker-us:9092 --command-config /etc/kafka/command-us.properties --add --allow-principal User:connect --consumer --topic=* --group=*"
docker exec client bash -c "kinit -k -t /var/lib/secret/kafka-admin.key admin/for-kafka && kafka-acls --bootstrap-server broker-us:9092 --command-config /etc/kafka/command-us.properties --add --allow-principal User:connect --producer --topic=*"
# Adding ACLs for consumer and producer user:
docker exec client bash -c "kinit -k -t /var/lib/secret/kafka-admin.key admin/for-kafka && kafka-acls --bootstrap-server broker-europe:9092 --command-config /etc/kafka/command-europe.properties --add --allow-principal User:kafka_producer --producer --topic=*"
docker exec client bash -c "kinit -k -t /var/lib/secret/kafka-admin.key admin/for-kafka && kafka-acls --bootstrap-server broker-europe:9092 --command-config /etc/kafka/command-europe.properties --add --allow-principal User:kafka_consumer --consumer --topic=* --group=*"
# Adding ACLs for connect user:
docker exec client bash -c "kinit -k -t /var/lib/secret/kafka-admin.key admin/for-kafka && kafka-acls --bootstrap-server broker-europe:9092 --command-config /etc/kafka/command-europe.properties --add --allow-principal User:connect --consumer --topic=* --group=*"
docker exec client bash -c "kinit -k -t /var/lib/secret/kafka-admin.key admin/for-kafka && kafka-acls --bootstrap-server broker-europe:9092 --command-config /etc/kafka/command-europe.properties --add --allow-principal User:connect --producer --topic=*"
# controlcenter is super user

# Output example usage:
log "-----------------------------------------"
log "Example configuration to access kafka on US cluster:"
log "-----------------------------------------"
log "-> docker exec -i client bash -c 'kinit -k -t /var/lib/secret/kafka-client.key kafka_producer && kafka-console-producer --broker-list broker-us:9092 --topic test --producer.config /etc/kafka/producer-us.properties'"
log "-> docker exec -i client bash -c 'kinit -k -t /var/lib/secret/kafka-client.key kafka_consumer && kafka-console-consumer --bootstrap-server broker-us:9092 --topic test --consumer.config /etc/kafka/consumer-us.properties --from-beginning'"

log "-----------------------------------------"
log "Example configuration to access kafka on EUROPE cluster:"
log "-----------------------------------------"
log "-> docker exec -i client bash -c 'kinit -k -t /var/lib/secret/kafka-client.key kafka_producer && kafka-console-producer --broker-list broker-europe:9092 --topic test --producer.config /etc/kafka/producer-europe.properties'"
log "-> docker exec -i client bash -c 'kinit -k -t /var/lib/secret/kafka-client.key kafka_consumer && kafka-console-consumer --bootstrap-server broker-europe:9092 --topic test --consumer.config /etc/kafka/consumer-europe.properties --from-beginning'"