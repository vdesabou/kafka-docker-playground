#!/bin/bash

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"

source ${DIR}/../../../../scripts/utils.sh

################################## GET KAFKA CLUSTER ID ########################
KAFKA_CLUSTER_ID=$(host_check_kafka_cluster_registered)
echo "KAFKA_CLUSTER_ID: $KAFKA_CLUSTER_ID"

################################## SETUP VARIABLES #############################
MDS_URL=http://broker:8091
CONNECT=connect-cluster
SR=schema-registry
C3=c3-cluster

SUPER_USER=superUser
SUPER_USER_PASSWORD=superUser
SUPER_USER_PRINCIPAL="User:$SUPER_USER"
CONNECT_ADMIN="User:connectAdmin"
CONNECTOR_SUBMITTER="User:connectorSubmitter"
CONNECTOR_PRINCIPAL="User:connectorSA"
SR_PRINCIPAL="User:schemaregistryUser"
C3_ADMIN="User:controlcenterAdmin"
CLIENT_AVRO_PRINCIPAL="User:clientAvroCli"

################################## Run through permutations #############################

for p in $SUPER_USER_PRINCIPAL $CONNECT_ADMIN $CONNECTOR_SUBMITTER $CONNECTOR_PRINCIPAL $SR_PRINCIPAL $C3_ADMIN $CLIENT_AVRO_PRINCIPAL; do
  for c in " " " --schema-registry-cluster-id $SR" " --connect-cluster-id $CONNECT"; do
    echo
    echo "Showing bindings for principal $p and --kafka-cluster-id $KAFKA_CLUSTER_ID $c"
    docker-compose -f ${DIR}/../../../../environment/plaintext/docker-compose.yml -f ${DIR}/../../../../environment/rbac-sasl-plain/docker-compose.yml exec tools confluent iam rolebinding list --principal $p --kafka-cluster-id $KAFKA_CLUSTER_ID $c
    echo
  done
done
