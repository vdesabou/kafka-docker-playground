#!/bin/bash

verify_installed()
{
  local cmd="$1"
  if [[ $(type $cmd 2>&1) =~ "not found" ]]; then
    echo -e "\nERROR: This script requires '$cmd'. Please install '$cmd' and run again.\n"
    exit 1
  fi
}
verify_installed "jq"
verify_installed "docker-compose"

DOCKER_COMPOSE_FILE_OVERRIDE=$1
# Starting kerberos,
# Avoiding starting up all services at the begining to generate the keytab first
if [ -f "${DOCKER_COMPOSE_FILE_OVERRIDE}" ]
then

  docker-compose -f ../../environment/mdc-plaintext/docker-compose.yml -f ../../environment/mdc-kerberos/docker-compose.kerberos.yml -f ${DOCKER_COMPOSE_FILE_OVERRIDE} down -v
  docker-compose -f ../../environment/mdc-plaintext/docker-compose.yml -f ../../environment/mdc-kerberos/docker-compose.kerberos.yml -f ${DOCKER_COMPOSE_FILE_OVERRIDE} build kdc
  # docker-compose -f ../../environment/mdc-plaintext/docker-compose.yml -f ../../environment/mdc-kerberos/docker-compose.kerberos.yml -f ${DOCKER_COMPOSE_FILE_OVERRIDE} build client
  docker-compose -f ../../environment/mdc-plaintext/docker-compose.yml -f ../../environment/mdc-kerberos/docker-compose.kerberos.yml -f ${DOCKER_COMPOSE_FILE_OVERRIDE} up -d kdc
else
  docker-compose -f ../../environment/mdc-plaintext/docker-compose.yml -f ../../environment/mdc-kerberos/docker-compose.kerberos.yml down -v
  docker-compose -f ../../environment/mdc-plaintext/docker-compose.yml -f ../../environment/mdc-kerberos/docker-compose.kerberos.yml build kdc
  # docker-compose -f ../../environment/mdc-plaintext/docker-compose.yml -f ../../environment/mdc-kerberos/docker-compose.kerberos.yml build client
  docker-compose -f ../../environment/mdc-plaintext/docker-compose.yml -f ../../environment/mdc-kerberos/docker-compose.kerberos.yml up -d kdc
fi

### Create the required identities:
# Kafka service principal:
docker exec -ti kdc kadmin.local -w password -q "add_principal -randkey kafka/broker-us.kerberos-demo.local@TEST.CONFLUENT.IO"  > /dev/null
docker exec -ti kdc kadmin.local -w password -q "add_principal -randkey kafka/broker-europe.kerberos-demo.local@TEST.CONFLUENT.IO"  > /dev/null

# Zookeeper service principal:
docker exec -ti kdc kadmin.local -w password -q "add_principal -randkey zookeeper/zookeeper-us.kerberos-demo.local@TEST.CONFLUENT.IO"  > /dev/null
docker exec -ti kdc kadmin.local -w password -q "add_principal -randkey zookeeper/zookeeper-europe.kerberos-demo.local@TEST.CONFLUENT.IO"  > /dev/null

# Create a principal with which to connect to Zookeeper from brokers - NB use the same credential on all brokers!
docker exec -ti kdc kadmin.local -w password -q "add_principal -randkey zkclient@TEST.CONFLUENT.IO"  > /dev/null

# Create client principals to connect in to the cluster:
docker exec -ti kdc kadmin.local -w password -q "add_principal -randkey connect@TEST.CONFLUENT.IO"  > /dev/null

# Create an admin principal for the cluster, which we'll use to setup ACLs.
# Look after this - its also declared a super user in broker config.
docker exec -ti kdc kadmin.local -w password -q "add_principal -randkey admin/for-kafka@TEST.CONFLUENT.IO"  > /dev/null

# Create keytabs to use for Kafka
echo -e "\033[0;33mCreate keytabs\033[0m"
docker exec -ti kdc rm -f /var/lib/secret/broker-us.key 2>&1 > /dev/null
docker exec -ti kdc rm -f /var/lib/secret/broker-europe.key 2>&1 > /dev/null
docker exec -ti kdc rm -f /var/lib/secret/zookeeper-us.key 2>&1 > /dev/null
docker exec -ti kdc rm -f /var/lib/secret/zookeeper-europe.key 2>&1 > /dev/null
docker exec -ti kdc rm -f /var/lib/secret/zookeeper-client.key 2>&1 > /dev/null
docker exec -ti kdc rm -f /var/lib/secret/kafka-client.key 2>&1 > /dev/null
docker exec -ti kdc rm -f /var/lib/secret/kafka-admin.key 2>&1 > /dev/null
docker exec -ti kdc rm -f /var/lib/secret/kafka-connect.key 2>&1 > /dev/null

docker exec -ti kdc kadmin.local -w password -q "ktadd  -k /var/lib/secret/broker-us.key -norandkey kafka/broker-us.kerberos-demo.local@TEST.CONFLUENT.IO " > /dev/null
docker exec -ti kdc kadmin.local -w password -q "ktadd  -k /var/lib/secret/broker-europe.key -norandkey kafka/broker-europe.kerberos-demo.local@TEST.CONFLUENT.IO " > /dev/null
docker exec -ti kdc kadmin.local -w password -q "ktadd  -k /var/lib/secret/zookeeper-us.key -norandkey zookeeper/zookeeper-us.kerberos-demo.local@TEST.CONFLUENT.IO " > /dev/null
docker exec -ti kdc kadmin.local -w password -q "ktadd  -k /var/lib/secret/zookeeper-europe.key -norandkey zookeeper/zookeeper-europe.kerberos-demo.local@TEST.CONFLUENT.IO " > /dev/null
docker exec -ti kdc kadmin.local -w password -q "ktadd  -k /var/lib/secret/zookeeper-client.key -norandkey zkclient@TEST.CONFLUENT.IO " > /dev/null
docker exec -ti kdc kadmin.local -w password -q "ktadd  -k /var/lib/secret/kafka-admin.key -norandkey admin/for-kafka@TEST.CONFLUENT.IO " > /dev/null
docker exec -ti kdc kadmin.local -w password -q "ktadd  -k /var/lib/secret/kafka-connect.key -norandkey connect@TEST.CONFLUENT.IO " > /dev/null

DOCKER_COMPOSE_FILE_OVERRIDE=$1
if [ -f "${DOCKER_COMPOSE_FILE_OVERRIDE}" ]
then
  docker-compose -f ../../environment/mdc-plaintext/docker-compose.yml -f ../../environment/mdc-kerberos/docker-compose.kerberos.yml -f ${DOCKER_COMPOSE_FILE_OVERRIDE} up -d
else
  docker-compose -f ../../environment/mdc-plaintext/docker-compose.yml -f ../../environment/mdc-kerberos/docker-compose.kerberos.yml up -d
fi

shift

../../WaitForConnectAndControlCenter.sh connect-us $@
../../WaitForConnectAndControlCenter.sh connect-europe $@