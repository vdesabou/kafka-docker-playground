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
echo "Creating role bindings for GCP GCS sink connector"

confluent iam rolebinding create \
    --principal $CONNECTOR_SUBMITTER \
    --role ResourceOwner \
    --resource Connector:gcs-rbac-sink \
    --kafka-cluster-id $KAFKA_CLUSTER_ID \
    --connect-cluster-id $CONNECT

confluent iam rolebinding create \
    --principal $CONNECTOR_PRINCIPAL \
    --role ResourceOwner \
    --resource Group:connect-gcs-rbac-sink \
    --kafka-cluster-id $KAFKA_CLUSTER_ID \

confluent iam rolebinding create \
    --principal $CONNECTOR_PRINCIPAL \
    --role ResourceOwner \
    --resource Topic:rbac \
    --prefix \
    --kafka-cluster-id $KAFKA_CLUSTER_ID

confluent iam rolebinding create \
    --principal $CONNECTOR_PRINCIPAL \
    --role ResourceOwner \
    --resource Subject:rbac \
    --prefix \
    --kafka-cluster-id $KAFKA_CLUSTER_ID \
    --schema-registry-cluster-id $SR


############################## Control Center ###############################
echo "Creating role bindings for Control Center"

# C3 only needs SystemAdmin on the kafka cluster itself
confluent iam rolebinding create \
    --principal $C3_ADMIN \
    --role SystemAdmin \
    --kafka-cluster-id $KAFKA_CLUSTER_ID


################################### Client Avro CLI ###################################
echo "Creating role bindings for the Avro CLI"

confluent iam rolebinding create \
    --principal $CLIENT_AVRO_PRINCIPAL \
    --role ResourceOwner \
    --resource Group:clientAvro \
    --prefix \
    --kafka-cluster-id $KAFKA_CLUSTER_ID

confluent iam rolebinding create \
    --principal $CLIENT_AVRO_PRINCIPAL \
    --role ResourceOwner \
    --resource Topic:rbac \
    --prefix \
    --kafka-cluster-id $KAFKA_CLUSTER_ID

confluent iam rolebinding create \
    --principal $CLIENT_AVRO_PRINCIPAL \
    --role ResourceOwner \
    --resource Topic:_confluent-monitoring \
    --kafka-cluster-id $KAFKA_CLUSTER_ID

confluent iam rolebinding create \
    --principal $CLIENT_AVRO_PRINCIPAL \
    --role ResourceOwner \
    --resource Subject:rbac \
    --prefix \
    --kafka-cluster-id $KAFKA_CLUSTER_ID \
    --schema-registry-cluster-id $SR

######################### Print #########################

echo "Cluster IDs:"
echo "    kafka cluster id: $KAFKA_CLUSTER_ID"
echo "    connect cluster id: $CONNECT"
echo "    schema registry cluster id: $SR"
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
echo "    C3 Admin: $C3_ADMIN"
echo "    Client Avro CLI Principal: $CLIENT_AVRO_PRINCIPAL"
echo


