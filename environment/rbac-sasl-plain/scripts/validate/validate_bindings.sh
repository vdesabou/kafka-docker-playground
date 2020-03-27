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
KSQL=ksql-cluster
C3=c3-cluster

SUPER_USER=superUser
SUPER_USER_PASSWORD=superUser
SUPER_USER_PRINCIPAL="User:$SUPER_USER"
CONNECT_ADMIN="User:connectAdmin"
CONNECTOR_SUBMITTER="User:connectorSubmitter"
CONNECTOR_PRINCIPAL="User:connectorSA"
SR_PRINCIPAL="User:schemaregistryUser"
KSQL_ADMIN="User:ksqlAdmin"
KSQL_USER="User:ksqlUser"
C3_ADMIN="User:controlcenterAdmin"
CLIENT_PRINCIPAL="User:appSA"
BADAPP="User:badapp"
LISTEN_PRINCIPAL="User:clientListen"

################################## Run through permutations #############################

for p in $SUPER_USER_PRINCIPAL $CONNECT_ADMIN $CONNECTOR_SUBMITTER $CONNECTOR_PRINCIPAL $SR_PRINCIPAL $KSQL_ADMIN $KSQL_USER $C3_ADMIN $CLIENT_PRINCIPAL $BADAPP $LISTEN_PRINCIPAL; do
  for c in " " " --schema-registry-cluster-id $SR" " --connect-cluster-id $CONNECT" " --ksql-cluster-id $KSQL"; do
    echo
    echo "Showing bindings for principal $p and --kafka-cluster-id $KAFKA_CLUSTER_ID $c"
    docker-compose -f ${DIR}/../../../../environment/plaintext/docker-compose.yml -f ${DIR}/../../../../environment/rbac-sasl-plain/docker-compose.yml exec tools confluent iam rolebinding list --principal $p --kafka-cluster-id $KAFKA_CLUSTER_ID $c
    echo
  done
done
