#!/bin/bash -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"

. /tmp/helper/functions.sh

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

################################### SCHEMA REGISTRY ###################################
echo "Creating ACL topic role bindings for Schema Registry"

for resource in Topic:_schemas_acl Group:schema-registry
do
    confluent iam rolebinding create \
        --principal $SR_PRINCIPAL \
        --role ResourceOwner \
        --resource $resource \
        --kafka-cluster-id $KAFKA_CLUSTER_ID
done

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


