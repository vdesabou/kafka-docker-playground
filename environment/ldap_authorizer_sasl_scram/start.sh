#!/bin/bash

set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh
verify_installed "docker-compose"

DOCKER_COMPOSE_FILE_OVERRIDE=$1
# Starting broker first
if [ -f "${DOCKER_COMPOSE_FILE_OVERRIDE}" ]
then

  docker-compose -f ../../environment/plaintext/docker-compose.yml -f ../../environment/ldap_authorizer_sasl_scram/docker-compose.yml -f ${DOCKER_COMPOSE_FILE_OVERRIDE} down -v
  docker-compose -f ../../environment/plaintext/docker-compose.yml -f ../../environment/ldap_authorizer_sasl_scram/docker-compose.yml -f ${DOCKER_COMPOSE_FILE_OVERRIDE} up -d --build broker
else
  docker-compose -f ../../environment/plaintext/docker-compose.yml -f ../../environment/ldap_authorizer_sasl_scram/docker-compose.yml down -v
  docker-compose -f ../../environment/plaintext/docker-compose.yml -f ../../environment/ldap_authorizer_sasl_scram/docker-compose.yml up -d --build broker
fi

# Creating the users
# broker is configured as a super user
docker exec broker kafka-configs --zookeeper zookeeper:2181 --alter --add-config 'SCRAM-SHA-256=[password=broker],SCRAM-SHA-512=[password=broker]' --entity-type users --entity-name broker
docker exec broker kafka-configs --zookeeper zookeeper:2181 --alter --add-config 'SCRAM-SHA-256=[password=alice-secret],SCRAM-SHA-512=[password=alice-secret]' --entity-type users --entity-name alice
docker exec broker kafka-configs --zookeeper zookeeper:2181 --alter --add-config 'SCRAM-SHA-256=[password=barnie-secret],SCRAM-SHA-512=[password=barnie-secret]' --entity-type users --entity-name barnie
docker exec broker kafka-configs --zookeeper zookeeper:2181 --alter --add-config 'SCRAM-SHA-256=[password=charlie-secret],SCRAM-SHA-512=[password=charlie-secret]' --entity-type users --entity-name charlie

if [ -f "${DOCKER_COMPOSE_FILE_OVERRIDE}" ]
then
  docker-compose -f ../../environment/plaintext/docker-compose.yml -f ../../environment/ldap_authorizer_sasl_scram/docker-compose.yml -f ${DOCKER_COMPOSE_FILE_OVERRIDE} up -d
else
  docker-compose -f ../../environment/plaintext/docker-compose.yml -f ../../environment/ldap_authorizer_sasl_scram/docker-compose.yml up -d
fi

if [ "$#" -ne 0 ]
then
    shift
fi
../../scripts/wait-for-connect-and-controlcenter.sh $@

# SET ACLs
# Authorize broker user kafka for cluster operations. Note that the example uses user-principal based ACL for brokers, but brokers may also be configured to use group-based ACLs.
docker exec broker kafka-acls --authorizer-properties zookeeper.connect=zookeeper:2181 --add --cluster --operation=All --allow-principal=User:broker

# Test LDAP group-based authorization
# https://docs.confluent.io/current/security/ldap-authorizer/quickstart.html#test-ldap-group-based-authorization
log "Create topic testtopic"
docker exec broker kafka-topics --create --topic testtopic --partitions 10 --replication-factor 1 --zookeeper zookeeper:2181

log "Run console producer without authorizing user alice: SHOULD FAIL"
docker exec -i broker kafka-console-producer --broker-list broker:9092 --topic testtopic --producer.config /service/kafka/users/alice.properties << EOF
message Alice
EOF

log "Authorize group Group:Kafka Developers and rerun producer for alice: SHOULD BE SUCCESS"
docker exec broker kafka-acls --authorizer-properties zookeeper.connect=zookeeper:2181 --add --topic=testtopic --producer --allow-principal="Group:Kafka Developers"

sleep 1

docker exec -i broker kafka-console-producer --broker-list broker:9092 --topic testtopic --producer.config /service/kafka/users/alice.properties << EOF
message Alice
EOF

log "Run console consumer without access to consumer group: SHOULD FAIL"
# Consume should fail authorization since neither user alice nor the group Kafka Developers that alice belongs to has authorization to consume using the group test-consumer-group
docker exec broker kafka-console-consumer --bootstrap-server broker:9092 --topic testtopic --from-beginning --group test-consumer-group --consumer.config /service/kafka/users/alice.properties --max-messages 1

log "Authorize group and rerun consumer"
docker exec broker kafka-acls --authorizer-properties zookeeper.connect=zookeeper:2181 --add --topic=testtopic --group test-consumer-group --allow-principal="Group:Kafka Developers"
docker exec broker kafka-console-consumer --bootstrap-server broker:9092 --topic testtopic --from-beginning --group test-consumer-group --consumer.config /service/kafka/users/alice.properties --max-messages 1

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
