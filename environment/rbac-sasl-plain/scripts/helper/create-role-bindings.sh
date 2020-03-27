#!/bin/bash -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"

. ${DIR}/functions.sh

################################## GET KAFKA CLUSTER ID ########################
KAFKA_CLUSTER_ID=$(get_kafka_cluster_id_from_container)
#echo "KAFKA_CLUSTER_ID: $KAFKA_CLUSTER_ID"

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
KSQL_SERVER="User:ksqlserver"
C3_ADMIN="User:controlcenterAdmin"
CLIENT_PRINCIPAL="User:appSA"
LISTEN_PRINCIPAL="User:clientListen"

mds_login $MDS_URL ${SUPER_USER} ${SUPER_USER_PASSWORD} || exit 1

################################### SUPERUSER ###################################
echo "Creating role bindings for Super User"

confluent iam rolebinding create \
    --principal $SUPER_USER_PRINCIPAL  \
    --role SystemAdmin \
    --kafka-cluster-id $KAFKA_CLUSTER_ID

confluent iam rolebinding create \
    --principal $SUPER_USER_PRINCIPAL \
    --role SystemAdmin \
    --kafka-cluster-id $KAFKA_CLUSTER_ID \
    --schema-registry-cluster-id $SR

confluent iam rolebinding create \
    --principal $SUPER_USER_PRINCIPAL \
    --role SystemAdmin \
    --kafka-cluster-id $KAFKA_CLUSTER_ID \
    --connect-cluster-id $CONNECT

confluent iam rolebinding create \
    --principal $SUPER_USER_PRINCIPAL \
    --role SystemAdmin \
    --kafka-cluster-id $KAFKA_CLUSTER_ID \
    --ksql-cluster-id $KSQL

################################### SCHEMA REGISTRY ###################################
echo "Creating role bindings for Schema Registry"

# SecurityAdmin on SR cluster itself
confluent iam rolebinding create \
    --principal $SR_PRINCIPAL \
    --role SecurityAdmin \
    --kafka-cluster-id $KAFKA_CLUSTER_ID \
    --schema-registry-cluster-id $SR

# ResourceOwner for groups and topics on broker
for resource in Topic:_schemas Group:schema-registry
do
    confluent iam rolebinding create \
        --principal $SR_PRINCIPAL \
        --role ResourceOwner \
        --resource $resource \
        --kafka-cluster-id $KAFKA_CLUSTER_ID
done

################################### CONNECT Admin ###################################
echo "Creating role bindings for Connect Admin"

# SecurityAdmin on the connect cluster itself
confluent iam rolebinding create \
    --principal $CONNECT_ADMIN \
    --role SecurityAdmin \
    --kafka-cluster-id $KAFKA_CLUSTER_ID \
    --connect-cluster-id $CONNECT

# ResourceOwner for groups and topics on broker
declare -a ConnectResources=(
    "Topic:connect-configs"
    "Topic:connect-offsets"
    "Topic:connect-status"
    "Group:connect-cluster"
    "Topic:_confluent-monitoring"
    "Topic:_confluent-secrets"
    "Group:secret-registry"
)
for resource in ${ConnectResources[@]}
do
    confluent iam rolebinding create \
        --principal $CONNECT_ADMIN \
        --role ResourceOwner \
        --resource $resource \
        --kafka-cluster-id $KAFKA_CLUSTER_ID
done

################################### Connectors ###################################
echo "Creating role bindings for wikipedia-irc connector"

confluent iam rolebinding create \
    --principal $CONNECTOR_SUBMITTER \
    --role ResourceOwner \
    --resource Connector:wikipedia-irc \
    --kafka-cluster-id $KAFKA_CLUSTER_ID \
    --connect-cluster-id $CONNECT

confluent iam rolebinding create \
    --principal $CONNECTOR_PRINCIPAL \
    --role ResourceOwner \
    --resource Topic:wikipedia \
    --prefix \
    --kafka-cluster-id $KAFKA_CLUSTER_ID

confluent iam rolebinding create \
    --principal $CONNECTOR_PRINCIPAL \
    --role ResourceOwner \
    --resource Subject:wikipedia \
    --prefix \
    --kafka-cluster-id $KAFKA_CLUSTER_ID \
    --schema-registry-cluster-id $SR

echo "Creating role bindings for replicate-topic connector"

confluent iam rolebinding create \
    --principal $CONNECTOR_SUBMITTER \
    --role ResourceOwner \
    --resource Connector:replicate-topic \
    --kafka-cluster-id $KAFKA_CLUSTER_ID \
    --connect-cluster-id $CONNECT

confluent iam rolebinding create \
    --principal $CONNECTOR_PRINCIPAL \
    --role ResourceOwner \
    --resource Topic:_confluent \
    --prefix \
    --kafka-cluster-id $KAFKA_CLUSTER_ID

confluent iam rolebinding create \
    --principal $CONNECTOR_PRINCIPAL \
    --role ResourceOwner \
    --resource Group:connect-replicator \
    --kafka-cluster-id $KAFKA_CLUSTER_ID \

echo "Creating role bindings for elasticsearch-ksql connector"

confluent iam rolebinding create \
    --principal $CONNECTOR_SUBMITTER \
    --role ResourceOwner \
    --resource Connector:elasticsearch-ksql \
    --kafka-cluster-id $KAFKA_CLUSTER_ID \
    --connect-cluster-id $CONNECT

confluent iam rolebinding create \
    --principal $CONNECTOR_PRINCIPAL \
    --role ResourceOwner \
    --resource Group:connect-elasticsearch-ksql \
    --kafka-cluster-id $KAFKA_CLUSTER_ID \

confluent iam rolebinding create \
    --principal $CONNECTOR_PRINCIPAL \
    --role ResourceOwner \
    --resource Topic:WIKIPEDIA \
    --prefix \
    --kafka-cluster-id $KAFKA_CLUSTER_ID

confluent iam rolebinding create \
    --principal $CONNECTOR_PRINCIPAL \
    --role ResourceOwner \
    --resource Subject:WIKIPEDIA \
    --prefix \
    --kafka-cluster-id $KAFKA_CLUSTER_ID \
    --schema-registry-cluster-id $SR

################################### KSQL Admin ###################################
echo "Creating role bindings for KSQL Admin"

confluent iam rolebinding create \
    --principal $KSQL_ADMIN \
    --role ResourceOwner \
    --resource KsqlCluster:$KSQL \
    --kafka-cluster-id $KAFKA_CLUSTER_ID \
    --ksql-cluster-id $KSQL

confluent iam rolebinding create \
    --principal $KSQL_ADMIN \
    --role DeveloperRead \
    --resource Group:_confluent-ksql-${KSQL} \
    --prefix \
    --kafka-cluster-id $KAFKA_CLUSTER_ID

confluent iam rolebinding create \
    --principal $KSQL_ADMIN \
    --role ResourceOwner \
    --resource Topic:_confluent-ksql-${KSQL} \
    --prefix \
    --kafka-cluster-id $KAFKA_CLUSTER_ID

confluent iam rolebinding create \
    --principal $KSQL_ADMIN \
    --role ResourceOwner \
    --resource Subject:_confluent-ksql-${KSQL} \
    --prefix \
    --kafka-cluster-id $KAFKA_CLUSTER_ID \
    --schema-registry-cluster-id $SR

confluent iam rolebinding create \
    --principal $KSQL_ADMIN \
    --role ResourceOwner \
    --resource Topic:_confluent-monitoring \
    --kafka-cluster-id $KAFKA_CLUSTER_ID

confluent iam rolebinding create \
    --principal $KSQL_ADMIN \
    --role ResourceOwner \
    --resource Topic:${KSQL}ksql_processing_log \
    --kafka-cluster-id $KAFKA_CLUSTER_ID

confluent iam rolebinding create \
    --principal $KSQL_ADMIN \
    --role DeveloperRead \
    --resource Topic:wikipedia.parsed \
    --kafka-cluster-id $KAFKA_CLUSTER_ID

confluent iam rolebinding create \
    --principal $KSQL_ADMIN \
    --role ResourceOwner \
    --resource Topic:WIKIPEDIA \
    --prefix \
    --kafka-cluster-id $KAFKA_CLUSTER_ID

confluent iam rolebinding create \
    --principal $KSQL_ADMIN \
    --role ResourceOwner \
    --resource Topic:EN_WIKIPEDIA \
    --prefix \
    --kafka-cluster-id $KAFKA_CLUSTER_ID

confluent iam rolebinding create \
    --principal $KSQL_ADMIN \
    --role ResourceOwner \
    --resource Subject:wikipedia \
    --prefix \
    --kafka-cluster-id $KAFKA_CLUSTER_ID \
    --schema-registry-cluster-id $SR

confluent iam rolebinding create \
    --principal $KSQL_ADMIN \
    --role ResourceOwner \
    --resource Subject:WIKIPEDIA \
    --prefix \
    --kafka-cluster-id $KAFKA_CLUSTER_ID \
    --schema-registry-cluster-id $SR

confluent iam rolebinding create \
    --principal $KSQL_ADMIN \
    --role ResourceOwner \
    --resource Subject:EN_WIKIPEDIA \
    --prefix \
    --kafka-cluster-id $KAFKA_CLUSTER_ID \
    --schema-registry-cluster-id $SR

confluent iam rolebinding create \
    --principal $KSQL_ADMIN \
    --role ResourceOwner \
    --resource Subject:WIKIPEDIA \
    --prefix \
    --kafka-cluster-id $KAFKA_CLUSTER_ID \
    --schema-registry-cluster-id $SR

confluent iam rolebinding create \
    --principal $KSQL_ADMIN \
    --role ResourceOwner \
    --resource Subject:EN_WIKIPEDIA \
    --prefix \
    --kafka-cluster-id $KAFKA_CLUSTER_ID \
    --schema-registry-cluster-id $SR

################################### KSQL User ###################################
echo "Creating role bindings for KSQL User"

confluent iam rolebinding create \
    --principal $KSQL_USER \
    --role DeveloperWrite \
    --resource KsqlCluster:$KSQL \
    --kafka-cluster-id $KAFKA_CLUSTER_ID \
    --ksql-cluster-id $KSQL

confluent iam rolebinding create \
    --principal $KSQL_USER \
    --role DeveloperRead \
    --resource Group:_confluent-ksql-${KSQL} \
    --prefix \
    --kafka-cluster-id $KAFKA_CLUSTER_ID

confluent iam rolebinding create \
    --principal $KSQL_USER \
    --role DeveloperRead \
    --resource Topic:${KSQL}ksql_processing_log \
    --kafka-cluster-id $KAFKA_CLUSTER_ID

confluent iam rolebinding create \
    --principal $KSQL_USER \
    --role DeveloperRead \
    --resource Topic:wikipedia.parsed \
    --kafka-cluster-id $KAFKA_CLUSTER_ID

confluent iam rolebinding create \
    --principal $KSQL_USER \
    --role ResourceOwner \
    --resource Topic:WIKIPEDIA \
    --prefix \
    --kafka-cluster-id $KAFKA_CLUSTER_ID

confluent iam rolebinding create \
    --principal $KSQL_USER \
    --role ResourceOwner \
    --resource Topic:EN_WIKIPEDIA \
    --prefix \
    --kafka-cluster-id $KAFKA_CLUSTER_ID

confluent iam rolebinding create \
    --principal $KSQL_USER \
    --role ResourceOwner \
    --resource Subject:WIKIPEDIA \
    --prefix \
    --kafka-cluster-id $KAFKA_CLUSTER_ID \
    --schema-registry-cluster-id $SR

confluent iam rolebinding create \
    --principal $KSQL_USER \
    --role ResourceOwner \
    --resource Subject:EN_WIKIPEDIA \
    --prefix \
    --kafka-cluster-id $KAFKA_CLUSTER_ID \
    --schema-registry-cluster-id $SR

################################### KSQL Server #############################
echo "Creating role bindings for KSQL Server (used for KSQL Processing Log)"
confluent iam rolebinding create \
    --principal $KSQL_SERVER \
    --role ResourceOwner \
    --resource Topic:${KSQL}ksql_processing_log \
    --kafka-cluster-id $KAFKA_CLUSTER_ID

############################## Control Center ###############################
echo "Creating role bindings for Control Center"

# C3 only needs SystemAdmin on the kafka cluster itself
confluent iam rolebinding create \
    --principal $C3_ADMIN \
    --role SystemAdmin \
    --kafka-cluster-id $KAFKA_CLUSTER_ID

################################### Client ###################################
echo "Creating role bindings for the streams-demo application"

confluent iam rolebinding create \
    --principal $CLIENT_PRINCIPAL \
    --role ResourceOwner \
    --resource Group:wikipedia \
    --prefix \
    --kafka-cluster-id $KAFKA_CLUSTER_ID

confluent iam rolebinding create \
    --principal $CLIENT_PRINCIPAL \
    --role ResourceOwner \
    --resource Group:app \
    --prefix \
    --kafka-cluster-id $KAFKA_CLUSTER_ID

confluent iam rolebinding create \
    --principal $CLIENT_PRINCIPAL \
    --role ResourceOwner \
    --resource Topic:wikipedia \
    --prefix \
    --kafka-cluster-id $KAFKA_CLUSTER_ID

confluent iam rolebinding create \
    --principal $CLIENT_PRINCIPAL \
    --role ResourceOwner \
    --resource Topic:_confluent-monitoring \
    --kafka-cluster-id $KAFKA_CLUSTER_ID

confluent iam rolebinding create \
    --principal $CLIENT_PRINCIPAL \
    --role ResourceOwner \
    --resource Subject:wikipedia \
    --prefix \
    --kafka-cluster-id $KAFKA_CLUSTER_ID \
    --schema-registry-cluster-id $SR

################################### Listen Client ###################################
echo "Creating role bindings for the listen client application"

confluent iam rolebinding create \
    --principal $LISTEN_PRINCIPAL \
    --role ResourceOwner \
    --resource Group:listen-consumer \
    --prefix \
    --kafka-cluster-id $KAFKA_CLUSTER_ID

confluent iam rolebinding create \
    --principal $LISTEN_PRINCIPAL \
    --role ResourceOwner \
    --resource Topic:wikipedia \
    --prefix \
    --kafka-cluster-id $KAFKA_CLUSTER_ID

confluent iam rolebinding create \
    --principal $LISTEN_PRINCIPAL \
    --role ResourceOwner \
    --resource Topic:WIKIPEDIA \
    --prefix \
    --kafka-cluster-id $KAFKA_CLUSTER_ID

confluent iam rolebinding create \
    --principal $LISTEN_PRINCIPAL \
    --role ResourceOwner \
    --resource Topic:EN_WIKIPEDIA \
    --kafka-cluster-id $KAFKA_CLUSTER_ID

confluent iam rolebinding create \
    --principal $LISTEN_PRINCIPAL \
    --role ResourceOwner \
    --resource Subject:wikipedia \
    --prefix \
    --kafka-cluster-id $KAFKA_CLUSTER_ID \
    --schema-registry-cluster-id $SR

confluent iam rolebinding create \
    --principal $LISTEN_PRINCIPAL \
    --role ResourceOwner \
    --resource Subject:WIKIPEDIA \
    --prefix \
    --kafka-cluster-id $KAFKA_CLUSTER_ID \
    --schema-registry-cluster-id $SR

confluent iam rolebinding create \
    --principal $LISTEN_PRINCIPAL \
    --role ResourceOwner \
    --resource Subject:EN_WIKIPEDIA \
    --prefix \
    --kafka-cluster-id $KAFKA_CLUSTER_ID \
    --schema-registry-cluster-id $SR

######################### Print #########################

echo "Cluster IDs:"
echo "    kafka cluster id: $KAFKA_CLUSTER_ID"
echo "    connect cluster id: $CONNECT"
echo "    schema registry cluster id: $SR"
echo "    ksql cluster id: $KSQL"
echo
echo "Cluster IDs as environment variables:"
echo "    export KAFKA_ID=$KAFKA_CLUSTER_ID ; export CONNECT_ID=$CONNECT ; export SR_ID=$SR ; export KSQL_ID=$KSQL"
echo
echo "Principals:"
echo "    super user account: $SUPER_USER_PRINCIPAL"
echo "    Schema Registry user: $SR_PRINCIPAL"
echo "    Connect Admin: $CONNECT_ADMIN"
echo "    Connector Submitter: $CONNECTOR_SUBMITTER"
echo "    Connector Principal: $CONNECTOR_PRINCIPAL"
echo "    KSQL Admin: $KSQL_ADMIN"
echo "    KSQL User: $KSQL_USER"
echo "    C3 Admin: $C3_ADMIN"
echo "    Client service account: $CLIENT_PRINCIPAL"
echo "    Listen Client service account: $LISTEN_PRINCIPAL"
echo


