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
KSQLDB=ksql-cluster
C3=c3-cluster

SUPER_USER=superUser
SUPER_USER_PASSWORD=superUser
SUPER_USER_PRINCIPAL="User:$SUPER_USER"
CONNECT_ADMIN="User:connectAdmin"
CONNECTOR_SUBMITTER="User:connectorSubmitter"
CONNECTOR_PRINCIPAL="User:connectorSA"
SR_PRINCIPAL="User:schemaregistryUser"
C3_ADMIN="User:controlcenterAdmin"
KSQLDB_ADMIN="User:ksqlDBAdmin"
KSQLDB_USER="User:ksqlDBUser"
KSQLDB_SERVER="User:controlCenterAndKsqlDBServer"
CLIENT_AVRO_PRINCIPAL="User:clientAvroCli"
LICENSE_RESOURCE="Topic:_confluent-license" # starting from 6.2.3 and 7.0.2, it is replaced by _confluent-command

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
    --ksql-cluster-id $KSQLDB

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

for role in DeveloperRead DeveloperWrite
do
    confluent iam rolebinding create \
        --principal $SR_PRINCIPAL \
        --role $role \
        --resource $LICENSE_RESOURCE \
        --kafka-cluster-id $KAFKA_CLUSTER_ID

    # starting from 6.2.3 and 7.0.2, it is replaced by _confluent-command
    confluent iam rolebinding create \
        --principal $SR_PRINCIPAL \
        --role $role \
        --resource Topic:_confluent-command \
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
    "Topic:_confluent-command"
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

# in case EOS is used https://cwiki.apache.org/confluence/display/KAFKA/KIP-618%3A+Exactly-Once+Support+for+Source+Connectors
confluent iam rolebinding create \
    --principal $CONNECT_ADMIN \
    --role ResourceOwner \
    --resource TransactionalId:connect-cluster-connect-cluster \
    --kafka-cluster-id $KAFKA_CLUSTER_ID

# enable.idempotence=true requires IdempotentWrite
confluent iam rolebinding create \
    --principal $CONNECT_ADMIN \
    --role DeveloperWrite \
    --resource Cluster:kafka-cluster \
    --kafka-cluster-id $KAFKA_CLUSTER_ID

################################### Connectors ###################################
echo "Creating role bindings for any connector"

confluent iam rolebinding create \
    --principal $C3_ADMIN \
    --role ResourceOwner \
    --resource Connector:* \
    --kafka-cluster-id $KAFKA_CLUSTER_ID \
    --connect-cluster-id $CONNECT

confluent iam rolebinding create \
    --principal $CONNECTOR_SUBMITTER \
    --role ResourceOwner \
    --resource Connector:* \
    --kafka-cluster-id $KAFKA_CLUSTER_ID \
    --connect-cluster-id $CONNECT

confluent iam rolebinding create \
    --principal $CONNECTOR_PRINCIPAL \
    --role ResourceOwner \
    --resource Group:* \
    --kafka-cluster-id $KAFKA_CLUSTER_ID \

confluent iam rolebinding create \
    --principal $CONNECTOR_PRINCIPAL \
    --role ResourceOwner \
    --resource Topic:* \
    --kafka-cluster-id $KAFKA_CLUSTER_ID

confluent iam rolebinding create \
    --principal $CONNECTOR_PRINCIPAL \
    --role ResourceOwner \
    --resource Subject:* \
    --kafka-cluster-id $KAFKA_CLUSTER_ID \
    --schema-registry-cluster-id $SR

# in case EOS is used https://cwiki.apache.org/confluence/display/KAFKA/KIP-618%3A+Exactly-Once+Support+for+Source+Connectors
confluent iam rolebinding create \
    --principal $CONNECTOR_PRINCIPAL \
    --role ResourceOwner \
    --resource TransactionalId:* \
    --kafka-cluster-id $KAFKA_CLUSTER_ID

################################### ksqlDB Admin ###################################
echo "Creating role bindings for ksqlDB Admin"

confluent iam rolebinding create \
    --principal $KSQLDB_ADMIN \
    --role ResourceOwner \
    --resource KsqlCluster:$KSQLDB \
    --kafka-cluster-id $KAFKA_CLUSTER_ID \
    --ksql-cluster-id $KSQLDB

confluent iam rolebinding create \
    --principal $KSQLDB_ADMIN \
    --role DeveloperRead \
    --resource Group:_confluent-ksql-${KSQLDB} \
    --prefix \
    --kafka-cluster-id $KAFKA_CLUSTER_ID

confluent iam rolebinding create \
    --principal $KSQLDB_ADMIN \
    --role ResourceOwner \
    --resource Topic:_confluent-ksql-${KSQLDB} \
    --prefix \
    --kafka-cluster-id $KAFKA_CLUSTER_ID

confluent iam rolebinding create \
    --principal $KSQLDB_ADMIN \
    --role ResourceOwner \
    --resource Subject:_confluent-ksql-${KSQLDB} \
    --prefix \
    --kafka-cluster-id $KAFKA_CLUSTER_ID \
    --schema-registry-cluster-id $SR

confluent iam rolebinding create \
    --principal $KSQLDB_ADMIN \
    --role ResourceOwner \
    --resource Topic:_confluent-monitoring \
    --kafka-cluster-id $KAFKA_CLUSTER_ID

confluent iam rolebinding create \
    --principal $KSQLDB_ADMIN \
    --role ResourceOwner \
    --resource Topic:${KSQLDB}ksql_processing_log \
    --kafka-cluster-id $KAFKA_CLUSTER_ID

confluent iam rolebinding create \
    --principal $KSQLDB_ADMIN \
    --role DeveloperRead \
    --resource Topic:wikipedia.parsed \
    --kafka-cluster-id $KAFKA_CLUSTER_ID

confluent iam rolebinding create \
    --principal $KSQLDB_ADMIN \
    --role ResourceOwner \
    --resource Topic:WIKIPEDIA \
    --prefix \
    --kafka-cluster-id $KAFKA_CLUSTER_ID

confluent iam rolebinding create \
    --principal $KSQLDB_ADMIN \
    --role ResourceOwner \
    --resource TransactionalId:${KSQLDB} \
    --kafka-cluster-id $KAFKA_CLUSTER_ID

confluent iam rolebinding create \
    --principal $KSQLDB_ADMIN \
    --role ResourceOwner \
    --resource Subject:wikipedia \
    --prefix \
    --kafka-cluster-id $KAFKA_CLUSTER_ID \
    --schema-registry-cluster-id $SR

confluent iam rolebinding create \
    --principal $KSQLDB_ADMIN \
    --role ResourceOwner \
    --resource Subject:WIKIPEDIA \
    --prefix \
    --kafka-cluster-id $KAFKA_CLUSTER_ID \
    --schema-registry-cluster-id $SR

confluent iam rolebinding create \
    --principal $KSQLDB_ADMIN \
    --role ResourceOwner \
    --resource Subject:WIKIPEDIA \
    --prefix \
    --kafka-cluster-id $KAFKA_CLUSTER_ID \
    --schema-registry-cluster-id $SR

# enable.idempotence=true requires IdempotentWrite
confluent iam rolebinding create \
    --principal $KSQLDB_ADMIN \
    --role DeveloperWrite \
    --resource Cluster:kafka-cluster \
    --kafka-cluster-id $KAFKA_CLUSTER_ID

################################### ksqlDB User ###################################
echo "Creating role bindings for ksqlDB User"

confluent iam rolebinding create \
    --principal $KSQLDB_USER \
    --role DeveloperWrite \
    --resource KsqlCluster:$KSQLDB \
    --kafka-cluster-id $KAFKA_CLUSTER_ID \
    --ksql-cluster-id $KSQLDB

confluent iam rolebinding create \
    --principal $KSQLDB_USER \
    --role DeveloperRead \
    --resource Group:_confluent-ksql-${KSQLDB} \
    --prefix \
    --kafka-cluster-id $KAFKA_CLUSTER_ID

confluent iam rolebinding create \
    --principal $KSQLDB_USER \
    --role ResourceOwner \
    --resource Topic:_confluent-ksql-${KSQLDB} \
    --prefix \
    --kafka-cluster-id $KAFKA_CLUSTER_ID

confluent iam rolebinding create \
    --principal $KSQLDB_USER \
    --role ResourceOwner \
    --resource Subject:_confluent-ksql-${KSQLDB} \
    --prefix \
    --kafka-cluster-id $KAFKA_CLUSTER_ID \
    --schema-registry-cluster-id $SR

confluent iam rolebinding create \
    --principal $KSQLDB_USER \
    --role DeveloperRead \
    --resource Topic:${KSQLDB}ksql_processing_log \
    --kafka-cluster-id $KAFKA_CLUSTER_ID

confluent iam rolebinding create \
    --principal $KSQLDB_USER \
    --role DeveloperRead \
    --resource Topic:wikipedia.parsed \
    --kafka-cluster-id $KAFKA_CLUSTER_ID

confluent iam rolebinding create \
    --principal $KSQLDB_USER \
    --role ResourceOwner \
    --resource Subject:wikipedia \
    --prefix \
    --kafka-cluster-id $KAFKA_CLUSTER_ID \
    --schema-registry-cluster-id $SR

confluent iam rolebinding create \
    --principal $KSQLDB_USER \
    --role ResourceOwner \
    --resource Topic:WIKIPEDIA \
    --prefix \
    --kafka-cluster-id $KAFKA_CLUSTER_ID

confluent iam rolebinding create \
    --principal $KSQLDB_USER \
    --role ResourceOwner \
    --resource Subject:WIKIPEDIA \
    --prefix \
    --kafka-cluster-id $KAFKA_CLUSTER_ID \
    --schema-registry-cluster-id $SR

# enable.idempotence=true requires IdempotentWrite
confluent iam rolebinding create \
    --principal $KSQLDB_USER \
    --role DeveloperWrite \
    --resource Cluster:kafka-cluster \
    --kafka-cluster-id $KAFKA_CLUSTER_ID

################################### KSQLDB Server #############################
echo "Creating role bindings for ksqlDB Server (used for ksqlDB Processing Log)"
confluent iam rolebinding create \
    --principal $KSQLDB_SERVER \
    --role ResourceOwner \
    --resource Topic:${KSQLDB}ksql_processing_log \
    --kafka-cluster-id $KAFKA_CLUSTER_ID

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
    --resource Topic:* \
    --kafka-cluster-id $KAFKA_CLUSTER_ID

confluent iam rolebinding create \
    --principal $CLIENT_AVRO_PRINCIPAL \
    --role ResourceOwner \
    --resource Topic:_confluent-monitoring \
    --kafka-cluster-id $KAFKA_CLUSTER_ID

confluent iam rolebinding create \
    --principal $CLIENT_AVRO_PRINCIPAL \
    --role ResourceOwner \
    --resource Subject:* \
    --kafka-cluster-id $KAFKA_CLUSTER_ID \
    --schema-registry-cluster-id $SR

######################### Print #########################

echo "Cluster IDs:"
echo "    kafka cluster id: $KAFKA_CLUSTER_ID"
echo "    connect cluster id: $CONNECT"
echo "    schema registry cluster id: $SR"
echo "    ksql cluster id: $KSQLDB"
echo
echo "Cluster IDs as environment variables:"
echo "    export KAFKA_ID=$KAFKA_CLUSTER_ID ; export CONNECT_ID=$CONNECT ; export SR_ID=$SR ; export KSQLDB_ID=$KSQLDB"
echo
echo "Principals:"
echo "    super user account: $SUPER_USER_PRINCIPAL"
echo "    Schema Registry user: $SR_PRINCIPAL"
echo "    Connect Admin: $CONNECT_ADMIN"
echo "    Connector Submitter: $CONNECTOR_SUBMITTER"
echo "    Connector Principal: $CONNECTOR_PRINCIPAL"
echo "    ksqlDB Admin: $KSQLDB_ADMIN"
echo "    ksqlDB User: $KSQLDB_USER"
echo "    ksqlDB Server: $KSQLDB_SERVER"
echo "    C3 Admin: $C3_ADMIN"
echo "    Client Avro CLI Principal: $CLIENT_AVRO_PRINCIPAL"
echo


