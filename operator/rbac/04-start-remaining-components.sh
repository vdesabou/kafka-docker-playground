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

playground topic consume --topic example --min-expected-messages 10

log "Login to MDS"
#confluent login --url https://$USER.$domain:443 --ca-cert-path ./certs/ca.pem
mds_login_with_ca_cert https://$USER.$domain:443 kafka kafka-secret "$PWD/certs/ca.pem" || exit 1

#curl -u 'kafka:kafka-secret' -ik https://$USER.$domain/security/1.0/activenodes/https

#confluent cluster describe --url https://$USER.$domain
log "Get Kafka Cluster ID"
KAFKA_ID=$(curl -ks https://$USER.$domain/v1/metadata/id | jq -r .id)
log "KAFKA_ID=$KAFKA_ID"


log "Schema Registry Role binding"
confluent iam rolebinding create \
  --kafka-cluster-id $KAFKA_ID \
  --principal User:sr \
  --role ResourceOwner  \
  --resource Topic:_confluent-license

confluent iam rolebinding create \
  --kafka-cluster-id $KAFKA_ID \
  --principal User:sr \
  --role SecurityAdmin \
  --schema-registry-cluster-id id_schemaregistry_confluent

confluent iam rolebinding create \
  --kafka-cluster-id $KAFKA_ID \
  --principal User:sr \
  --role ResourceOwner \
  --resource Group:id_schemaregistry_confluent

confluent iam rolebinding create \
  --kafka-cluster-id $KAFKA_ID \
  --principal User:sr \
  --role ResourceOwner \
  --resource Topic:_schemas_schemaregistry_confluent


log "Deploy Schema Registry"
helm upgrade --install sr -f $VALUES_FILE ${DIR}/confluent-operator/helm/confluent-operator/ \
    --namespace confluent \
    --set schemaregistry.enabled=true \
    --set-file schemaregistry.tls.fullchain=${PWD}/certs/component-certs/schemaregistry/schemaregistry.pem  \
    --set-file schemaregistry.tls.privkey=${PWD}/certs/component-certs/schemaregistry/schemaregistry-key.pem \
    --set-file schemaregistry.tls.cacerts=${PWD}/certs/ca.pem \
    --set global.sasl.plain.username=kafka \
    --set global.sasl.plain.password=kafka-secret \
    --wait

log "Connect Role binding"
confluent iam rolebinding create \
  --kafka-cluster-id $KAFKA_ID \
  --principal User:connect \
  --role SecurityAdmin \
  --connect-cluster-id id_connect_confluent

confluent iam rolebinding create \
  --kafka-cluster-id $KAFKA_ID \
  --principal User:connect \
  --role ResourceOwner \
  --resource Group:confluent.connectors

confluent iam rolebinding create \
  --kafka-cluster-id $KAFKA_ID \
  --principal User:connect \
  --role DeveloperWrite \
  --resource Topic:_confluent-monitoring \
  --prefix

confluent iam rolebinding create \
  --kafka-cluster-id $KAFKA_ID \
  --principal User:connect \
  --role ResourceOwner \
  --resource Topic:confluent.connectors- \
  --prefix

log "Deploy Connect"
helm upgrade --install connect -f $VALUES_FILE ${DIR}/confluent-operator/helm/confluent-operator/ \
    --namespace confluent \
    --set connect.enabled=true \
    --set-file connect.tls.fullchain=${PWD}/certs/component-certs/connectors/connectors.pem  \
    --set-file connect.tls.privkey=${PWD}/certs/component-certs/connectors/connectors-key.pem \
    --set-file connect.tls.cacerts=${PWD}/certs/ca.pem \
    --set global.sasl.plain.username=kafka \
    --set global.sasl.plain.password=kafka-secret \
    --wait

log "⌛ Waiting up to 1800 seconds for all pods in namespace confluent to start"
wait-until-pods-ready "1800" "10" "confluent"

# kubectl exec -it connectors-0 -- bash

set +e
# Verify Kafka Connect has started within MAX_WAIT seconds
MAX_WAIT=480
CUR_WAIT=0
log "⌛ Waiting up to $MAX_WAIT seconds for Kafka Connect connectors-0 to start"
kubectl logs connectors-0 > /tmp/out.txt 2>&1
while [[ ! $(cat /tmp/out.txt) =~ "Finished starting connectors and tasks" ]]; do
  sleep 10
  kubectl logs connectors-0 > /tmp/out.txt 2>&1
  CUR_WAIT=$(( CUR_WAIT+10 ))
  if [[ "$CUR_WAIT" -gt "$MAX_WAIT" ]]; then
    echo -e "\nERROR: The logs in connectors-0 container do not show 'Finished starting connectors and tasks' after $MAX_WAIT seconds. Please troubleshoot'.\n"
    tail -300 /tmp/out.txt
    exit 1
  fi
done
log "Connect connectors-0 has started!"
set -e

log "KSQL Role binding"
confluent iam rolebinding create \
  --kafka-cluster-id $KAFKA_ID \
  --principal User:ksql \
  --role ResourceOwner \
  --ksql-cluster-id confluent.ksql_ \
  --resource KsqlCluster:ksql-cluster

confluent iam rolebinding create \
  --kafka-cluster-id $KAFKA_ID \
  --principal User:ksql \
  --role ResourceOwner \
  --resource Topic:_confluent-ksql-confluent.ksql_ \
  --prefix

confluent iam rolebinding create \
    --principal User:ksql \
    --role ResourceOwner \
    --resource Topic:confluent.ksql_ksql_processing_log \
    --kafka-cluster-id $KAFKA_ID

confluent iam rolebinding create \
  --principal User:ksql \
  --role DeveloperWrite \
  --resource TransactionalId:confluent.ksql_ \
  --kafka-cluster-id $KAFKA_ID

# ksql-user
# KSQLDB_USER=ksql-user
# confluent iam rolebinding create \
#     --principal User:$KSQLDB_USER \
#     --role DeveloperWrite \
#     --resource KsqlCluster:ksql-cluster \
#     --kafka-cluster-id $KAFKA_ID \
#     --ksql-cluster-id confluent.ksql_

# confluent iam rolebinding create \
#     --principal User:$KSQLDB_USER \
#     --role DeveloperRead \
#     --resource Group:_confluent-ksql \
#     --prefix \
#     --kafka-cluster-id $KAFKA_ID

# confluent iam rolebinding create \
#     --principal User:$KSQLDB_USER \
#     --role DeveloperRead \
#     --resource Topic:confluent.ksql_ksql_processing_log \
#     --kafka-cluster-id $KAFKA_ID


# confluent iam rolebinding create \
#     --principal User:ksql \
#     --role DeveloperRead \
#     --resource Topic:SENSORS \
#     --prefix \
#     --kafka-cluster-id $KAFKA_ID

# confluent iam rolebinding create \
#     --principal User:ksql \
#     --role DeveloperWrite \
#     --resource Topic:SENSORS \
#     --prefix \
#     --kafka-cluster-id $KAFKA_ID

# confluent iam rolebinding create \
#     --principal User:$KSQLDB_USER \
#     --role DeveloperRead \
#     --resource Topic:SENSORS \
#     --prefix \
#     --kafka-cluster-id $KAFKA_ID

# confluent iam rolebinding create \
#     --principal User:$ksql \
#     --role ResourceOwner \
#     --resource Topic:SENSORS \
#     --prefix \
#     --kafka-cluster-id $KAFKA_ID

# confluent iam rolebinding create \
#     --principal User:$KSQLDB_USER \
#     --role ResourceOwner \
#     --resource Topic:_confluent-ksql-confluent.ksql_transient_ \
#     --prefix \
#     --kafka-cluster-id $KAFKA_ID


confluent iam rolebinding create \
  --principal User:ksql \
  --role DeveloperWrite \
  --resource TransactionalId:confluent.ksql_ \
  --kafka-cluster-id $KAFKA_ID

# confluent iam rolebinding create \
#     --principal User:$KSQLDB_USER \
#     --role ResourceOwner \
#     --resource Topic:_confluent-ksql-confluent.ksql__command_topic \
#     --kafka-cluster-id $KAFKA_ID

# confluent iam rolebinding create \
#     --principal User:$KSQLDB_USER \
#     --role ResourceOwner \
#     --resource Subject:example \
#     --prefix \
#     --kafka-cluster-id $KAFKA_ID \
#     --schema-registry-cluster-id id_schemaregistry_confluent

# confluent iam rolebinding create \
#     --principal User:$KSQLDB_USER \
#     --role ResourceOwner \
#     --resource Subject:_confluent-ksql-confluent.ksql_transient_ \
#     --prefix \
#     --kafka-cluster-id $KAFKA_ID \
#     --schema-registry-cluster-id id_schemaregistry_confluent

# confluent iam rolebinding create \
#     --principal $CLIENT_PRINCIPAL \
#     --role ResourceOwner \
#     --resource Group:wikipedia \
#     --prefix \
#     --kafka-cluster-id $KAFKA_CLUSTER_ID
if [[ "$OSTYPE" == "darwin"* ]]
then
    # workaround for issue on linux, see https://github.com/vdesabou/kafka-docker-playground/issues/851#issuecomment-821151962
    chmod -R a+rw .
else
    # workaround for issue on linux, see https://github.com/vdesabou/kafka-docker-playground/issues/851#issuecomment-821151962
    sudo chmod -R a+rw .
fi

# For operator 1.6.1 manually edit c3 psc to disable auto-update.  This might need to be tweaked as we upgrade versions
C3_PSC_FILE="${DIR}/confluent-operator/helm/confluent-operator/charts/controlcenter/templates/controlcenter-psc.yaml"
set +e
grep "confluent.controlcenter.ui.autoupdate.enable" $C3_PSC_FILE > /dev/null
if [[ $? -eq 1 ]]; then
  log "updating c3 yaml..."
  # use linux to run sed
  docker run --rm -v $PWD:/tmp ${CP_CONNECT_IMAGE}:${CONNECT_TAG} sed -i '/confluent.controlcenter.data.dir/a \          confluent.controlcenter.ui.autoupdate.enable=false' /tmp/confluent-operator/helm/confluent-operator/charts/controlcenter/templates/controlcenter-psc.yaml
  # docker run --rm -v $PWD:/tmp ${CP_CONNECT_IMAGE}:${CONNECT_TAG} sed -i '/confluent.controlcenter.data.dir/a \          confluent.controlcenter.service.healthcheck.interval.sec=600' /tmp/confluent-operator/helm/confluent-operator/charts/controlcenter/templates/controlcenter-psc.yaml
fi
# For operator 1.6.1 manually edit ksql psc to allow CORS.  This might need to be tweaked as we upgrade versions
KSQL_PSC_FILE="${DIR}/confluent-operator/helm/confluent-operator/charts/ksql/templates/ksql-psc.yaml"
grep "access.control.allow.origin" $KSQL_PSC_FILE > /dev/null
if [[ $? -eq 1 ]]; then
  log "updating ksql yaml..."
  # use linux to run sed
  docker run --rm -v $PWD:/tmp ${CP_CONNECT_IMAGE}:${CONNECT_TAG} sed -i '/authentication.skip.paths/a \          access.control.allow.origin=*' /tmp/confluent-operator/helm/confluent-operator/charts/ksql/templates/ksql-psc.yaml
  docker run --rm -v $PWD:/tmp ${CP_CONNECT_IMAGE}:${CONNECT_TAG} sed -i '/authentication.skip.paths/a \          access.control.allow.methods=GET,POST,HEAD' /tmp/confluent-operator/helm/confluent-operator/charts/ksql/templates/ksql-psc.yaml
  docker run --rm -v $PWD:/tmp ${CP_CONNECT_IMAGE}:${CONNECT_TAG} sed -i '/authentication.skip.paths/a \          access.control.allow.headers=X-Requested-With,Content-Type,Accept,Origin,Authorization' /tmp/confluent-operator/helm/confluent-operator/charts/ksql/templates/ksql-psc.yaml

  docker run --rm -v $PWD:/tmp ${CP_CONNECT_IMAGE}:${CONNECT_TAG} sed -i '/log4j.rootLogger=INFO, stdout/a \          log4j.logger.processing=ERROR, kafka_appender' /tmp/confluent-operator/helm/confluent-operator/charts/ksql/templates/ksql-psc.yaml
  docker run --rm -v $PWD:/tmp ${CP_CONNECT_IMAGE}:${CONNECT_TAG} sed -i '/log4j.rootLogger=INFO, stdout/a \          log4j.appender.kafka_appender=org.apache.kafka.log4jappender.KafkaLog4jAppender' /tmp/confluent-operator/helm/confluent-operator/charts/ksql/templates/ksql-psc.yaml
  docker run --rm -v $PWD:/tmp ${CP_CONNECT_IMAGE}:${CONNECT_TAG} sed -i '/log4j.rootLogger=INFO, stdout/a \          log4j.appender.kafka_appender.layout=io.confluent.common.logging.log4j.StructuredJsonLayout' /tmp/confluent-operator/helm/confluent-operator/charts/ksql/templates/ksql-psc.yaml
  docker run --rm -v $PWD:/tmp ${CP_CONNECT_IMAGE}:${CONNECT_TAG} sed -i '/log4j.rootLogger=INFO, stdout/a \          log4j.appender.kafka_appender.BrokerList=kafka:9071' /tmp/confluent-operator/helm/confluent-operator/charts/ksql/templates/ksql-psc.yaml
  docker run --rm -v $PWD:/tmp ${CP_CONNECT_IMAGE}:${CONNECT_TAG} sed -i '/log4j.rootLogger=INFO, stdout/a \          log4j.appender.kafka_appender.Topic={{ .Release.Namespace }}.{{ $.Values.name }}_ksql_processing_log' /tmp/confluent-operator/helm/confluent-operator/charts/ksql/templates/ksql-psc.yaml
  docker run --rm -v $PWD:/tmp ${CP_CONNECT_IMAGE}:${CONNECT_TAG} sed -i '/log4j.rootLogger=INFO, stdout/a \          log4j.appender.kafka_appender.SyncSend=false' /tmp/confluent-operator/helm/confluent-operator/charts/ksql/templates/ksql-psc.yaml
  docker run --rm -v $PWD:/tmp ${CP_CONNECT_IMAGE}:${CONNECT_TAG} sed -i '/log4j.rootLogger=INFO, stdout/a \          log4j.appender.kafka_appender.SecurityProtocol=SASL_SSL' /tmp/confluent-operator/helm/confluent-operator/charts/ksql/templates/ksql-psc.yaml
  docker run --rm -v $PWD:/tmp ${CP_CONNECT_IMAGE}:${CONNECT_TAG} sed -i '/log4j.rootLogger=INFO, stdout/a \          log4j.appender.kafka_appender.SaslMechanism=PLAIN' /tmp/confluent-operator/helm/confluent-operator/charts/ksql/templates/ksql-psc.yaml
  docker run --rm -v $PWD:/tmp ${CP_CONNECT_IMAGE}:${CONNECT_TAG} sed -i '/log4j.rootLogger=INFO, stdout/a \          log4j.appender.kafka_appender.ClientJaasConf=org.apache.kafka.common.security.plain.PlainLoginModule required username="kafka" password="kafka-secret";' /tmp/confluent-operator/helm/confluent-operator/charts/ksql/templates/ksql-psc.yaml
  docker run --rm -v $PWD:/tmp ${CP_CONNECT_IMAGE}:${CONNECT_TAG} sed -i '/log4j.rootLogger=INFO, stdout/a \          log4j.appender.kafka_appender.SslKeystoreType=JKS' /tmp/confluent-operator/helm/confluent-operator/charts/ksql/templates/ksql-psc.yaml
  docker run --rm -v $PWD:/tmp ${CP_CONNECT_IMAGE}:${CONNECT_TAG} sed -i '/log4j.rootLogger=INFO, stdout/a \          log4j.appender.kafka_appender.SslTruststoreLocation=/tmp/truststore.jks' /tmp/confluent-operator/helm/confluent-operator/charts/ksql/templates/ksql-psc.yaml
  docker run --rm -v $PWD:/tmp ${CP_CONNECT_IMAGE}:${CONNECT_TAG} sed -i '/log4j.rootLogger=INFO, stdout/a \          log4j.appender.kafka_appender.SslTruststorePassword=mystorepassword' /tmp/confluent-operator/helm/confluent-operator/charts/ksql/templates/ksql-psc.yaml

  docker run --rm -v $PWD:/tmp ${CP_CONNECT_IMAGE}:${CONNECT_TAG} sed -i '/## ksql configuration/a \          ksql.logging.processing.rows.include=true' /tmp/confluent-operator/helm/confluent-operator/charts/ksql/templates/ksql-psc.yaml
  docker run --rm -v $PWD:/tmp ${CP_CONNECT_IMAGE}:${CONNECT_TAG} sed -i '/## ksql configuration/a \          ksql.logging.processing.stream.auto.create=true' /tmp/confluent-operator/helm/confluent-operator/charts/ksql/templates/ksql-psc.yaml
  docker run --rm -v $PWD:/tmp ${CP_CONNECT_IMAGE}:${CONNECT_TAG} sed -i '/## ksql configuration/a \          ksql.logging.processing.topic.auto.create=true' /tmp/confluent-operator/helm/confluent-operator/charts/ksql/templates/ksql-psc.yaml
  docker run --rm -v $PWD:/tmp ${CP_CONNECT_IMAGE}:${CONNECT_TAG} sed -i '/## ksql configuration/a \          ksql.logging.processing.topic.name={{ .Release.Namespace }}.{{ $.Values.name }}_ksql_processing_log' /tmp/confluent-operator/helm/confluent-operator/charts/ksql/templates/ksql-psc.yaml
fi

log "Deploy KSQL"
helm upgrade --install ksql -f $VALUES_FILE ${DIR}/confluent-operator/helm/confluent-operator/ \
    --namespace confluent \
    --set ksql.enabled=true \
    --set-file ksql.tls.fullchain=${PWD}/certs/component-certs/ksql/ksql.pem  \
    --set-file ksql.tls.privkey=${PWD}/certs/component-certs/ksql/ksql-key.pem \
    --set-file ksql.tls.cacerts=${PWD}/certs/ca.pem \
    --set global.sasl.plain.username=kafka \
    --set global.sasl.plain.password=kafka-secret \
    --wait

log "Control Center Role binding"

confluent iam rolebinding create \
  --principal User:c3 \
  --role SystemAdmin \
  --kafka-cluster-id $KAFKA_ID

confluent iam rolebinding create \
  --kafka-cluster-id $KAFKA_ID \
  --role ClusterAdmin \
  --principal User:testadmin

confluent iam rolebinding create \
  --kafka-cluster-id $KAFKA_ID \
  --schema-registry-cluster-id id_schemaregistry_confluent \
  --principal User:testadmin \
  --role SystemAdmin

confluent iam rolebinding create \
  --kafka-cluster-id $KAFKA_ID \
  --connect-cluster-id confluent.connectors \
  --principal User:testadmin \
  --role SystemAdmin

confluent iam rolebinding create \
  --kafka-cluster-id $KAFKA_ID \
  --connect-cluster-id confluent.replicator \
  --principal User:testadmin \
  --role SystemAdmin

confluent iam rolebinding create \
  --kafka-cluster-id $KAFKA_ID \
  --ksql-cluster-id confluent.ksql_ \
  --resource KsqlCluster:ksql-cluster \
  --principal User:testadmin \
  --role ResourceOwner

log "Deploy Control Center"
helm upgrade --install controlcenter -f $VALUES_FILE ${DIR}/confluent-operator/helm/confluent-operator/ \
    --namespace confluent \
    --set controlcenter.enabled=true \
    --set-file controlcenter.tls.fullchain=${PWD}/certs/component-certs/controlcenter/controlcenter.pem  \
    --set-file controlcenter.tls.privkey=${PWD}/certs/component-certs/controlcenter/controlcenter-key.pem \
    --set-file controlcenter.tls.cacerts=${PWD}/certs/ca.pem \
    --set global.sasl.plain.username=kafka \
    --set global.sasl.plain.password=kafka-secret \
    --wait

log "⌛ Waiting up to 1800 seconds for all pods in namespace confluent to start"
wait-until-pods-ready "1800" "10" "confluent"

log "Control Center is reachable at https://127.0.0.1:9021 (testadmin/testadmin)"
kubectl port-forward controlcenter-0 9021:9021 &

