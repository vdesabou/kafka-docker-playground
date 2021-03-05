#!/bin/bash

set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

# read configuration files
#
if [ -r ${DIR}/test.properties ]
then
    . ${DIR}/test.properties
else
    logerror "Cannot read configuration file ${DIR}/test.properties"
    exit 1
fi

mds_login_with_ca_cert()
{
  MDS_URL=$1
  SUPER_USER=$2
  SUPER_USER_PASSWORD=$3
  CA_CERT=$4

  # Log into MDS
  if [[ $(type expect 2>&1) =~ "not found" ]]; then
    echo "'expect' is not found. Install 'expect' and try again"
    exit 1
  fi
  echo -e "\n# Login"
  OUTPUT=$(
  expect <<END
    log_user 1
    spawn confluent login --url $MDS_URL --ca-cert-path $CA_CERT
    expect "Username: "
    send "${SUPER_USER}\r";
    expect "Password: "
    send "${SUPER_USER_PASSWORD}\r";
    expect "Logged in as "
    set result $expect_out(buffer)
END
  )
  echo "$OUTPUT"
  if [[ ! "$OUTPUT" =~ "Logged in as" ]]; then
    echo "Failed to log into MDS.  Please check all parameters and run again"
    exit 1
  fi
}

verify_installed "kubectl"
verify_installed "helm"
verify_installed "aws"
verify_installed "eksctl"
verify_installed "kafka-broker-api-versions"
verify_installed "kafka-topics"
verify_installed "confluent"

VALUES_FILE=${DIR}/providers/aws.yaml

log "Kafka Sanity Testing"
kafka-broker-api-versions --command-config kafka.properties --bootstrap-server "$USER.$domain:9092"

log "Kafka create topic"
set +e
kafka-topics --create --bootstrap-server $USER.$domain:9092 --replication-factor 3 --partitions 1 --topic example --command-config kafka.properties
set -e

log "Make sure we can produce/consume"
seq 10 | kafka-console-producer --topic example --broker-list  $USER.$domain:9092 --producer.config kafka.properties

kafka-console-consumer --from-beginning --topic example --bootstrap-server $USER.$domain:9092 -consumer.config kafka.properties --max-messages 10

log "Login to MDS"
#confluent login --url https://$USER.$domain:443 --ca-cert-path ./certs/ca.pem
mds_login_with_ca_cert https://$USER.$domain:443 kafka kafka-secret "$PWD/certs/ca.pem " || exit 1

#curl -u 'kafka:kafka-secret' -ik https://$USER.$domain/security/1.0/activenodes/https

#confluent cluster describe --url https://$USER.$domain
log "Get Kafka Cluster ID"
KAFKA_ID=$(curl -ks https://$USER.$domain/v1/metadata/id | jq -r .id)
log "KAFKA_ID=$KAFKA_ID"


log "Schema Registry Role binding"
# FIXTHIS: adding some retries because it fails if processed by broker other than kafka-0
MAX_WAIT=120
retrycmd $MAX_WAIT 5 confluent iam rolebinding create --kafka-cluster-id $KAFKA_ID --principal User:sr --role ResourceOwner  --resource Topic:_confluent-license

retrycmd $MAX_WAIT 5 confluent iam rolebinding create --kafka-cluster-id $KAFKA_ID --principal User:sr --role SecurityAdmin --schema-registry-cluster-id id_schemaregistry_operator

retrycmd $MAX_WAIT 5 confluent iam rolebinding create --kafka-cluster-id $KAFKA_ID --principal User:sr --role ResourceOwner --resource Group:id_schemaregistry_operator

retrycmd $MAX_WAIT 5 confluent iam rolebinding create --kafka-cluster-id $KAFKA_ID --principal User:sr --role ResourceOwner --resource Topic:_schemas_schemaregistry_operator


log "Deploy Schema Registry"
helm upgrade --install sr -f $VALUES_FILE ${DIR}/confluent-operator/helm/confluent-operator/ \
    --namespace operator \
    --set schemaregistry.enabled=true \
    --set-file schemaregistry.tls.fullchain=${PWD}/certs/component-certs/schemaregistry/schemaregistry.pem  \
    --set-file schemaregistry.tls.privkey=${PWD}/certs/component-certs/schemaregistry/schemaregistry-key.pem \
    --set-file schemaregistry.tls.cacerts=${PWD}/certs/ca.pem \
    --set global.sasl.plain.username=kafka \
    --set global.sasl.plain.password=kafka-secret \
    --wait

log "Connect Role binding"
# FIXTHIS: adding some retries because it fails if processed by broker other than kafka-0
MAX_WAIT=120
retrycmd $MAX_WAIT 5 confluent iam rolebinding create --kafka-cluster-id $KAFKA_ID --principal User:connect --role ResourceOwner --resource Group:operator.connectors

retrycmd $MAX_WAIT 5 confluent iam rolebinding create --kafka-cluster-id $KAFKA_ID --principal User:connect --role DeveloperWrite --resource Topic:_confluent-monitoring --prefix

retrycmd $MAX_WAIT 5 confluent iam rolebinding create --kafka-cluster-id $KAFKA_ID --principal User:connect --role ResourceOwner --resource Topic:operator.connectors- --prefix

log "Deploy Connect"
helm upgrade --install connect -f $VALUES_FILE ${DIR}/confluent-operator/helm/confluent-operator/ \
    --namespace operator \
    --set connect.enabled=true \
    --set-file connect.tls.fullchain=${PWD}/certs/component-certs/connectors/connectors.pem  \
    --set-file connect.tls.privkey=${PWD}/certs/component-certs/connectors/connectors-key.pem \
    --set-file connect.tls.cacerts=${PWD}/certs/ca.pem \
    --set global.sasl.plain.username=kafka \
    --set global.sasl.plain.password=kafka-secret \
    --wait


# kubectl exec -it connectors-0 -- bash

# set +e
# # Verify Kafka Connect has started within MAX_WAIT seconds
# MAX_WAIT=480
# CUR_WAIT=0
# log "Waiting up to $MAX_WAIT seconds for Kafka Connect connectors-0 to start"
# kubectl logs connectors-0 > /tmp/out.txt 2>&1
# while [[ ! $(cat /tmp/out.txt) =~ "Finished starting connectors and tasks" ]]; do
#   sleep 10
#   kubectl logs connectors-0 > /tmp/out.txt 2>&1
#   CUR_WAIT=$(( CUR_WAIT+10 ))
#   if [[ "$CUR_WAIT" -gt "$MAX_WAIT" ]]; then
#     echo -e "\nERROR: The logs in connectors-0 container do not show 'Finished starting connectors and tasks' after $MAX_WAIT seconds. Please troubleshoot'.\n"
#     tail -300 /tmp/out.txt
#     exit 1
#   fi
# done
# log "Connect connectors-0 has started!"
# set -e

