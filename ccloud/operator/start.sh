#!/bin/bash

set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

verify_memory
verify_installed "kubectl"
verify_installed "minikube"
verify_installed "helm"

CONFIG_FILE=~/.ccloud/config

if [ ! -f ${CONFIG_FILE} ]
then
     logerror "ERROR: ${CONFIG_FILE} is not set"
     exit 1
fi

${DIR}/../ccloud-demo/ccloud-generate-env-vars.sh ${CONFIG_FILE}

if [ -f /tmp/delta_configs/env.delta ]
then
     source /tmp/delta_configs/env.delta
else
     logerror "ERROR: /tmp/delta_configs/env.delta has not been generated"
     exit 1
fi

VALUES_FILE="${DIR}/my-value.yaml"

set +e
log "Stop minikube if required"
minikube delete
set -e
log "Start minikube"
minikube start --cpus=8 --disk-size='50gb' --memory=16384
log "Launch minikube dashboard in background"
minikube dashboard &

log "Download Confluent Operator in ${DIR}/confluent-operator"

rm -rf ${DIR}/confluent-operator
mkdir ${DIR}/confluent-operator
cd ${DIR}/confluent-operator
wget https://platform-ops-bin.s3-us-west-1.amazonaws.com/operator/confluent-operator-1.6.1-for-confluent-platform-6.0.0.tar.gz
tar xvfz confluent-operator-1.6.1-for-confluent-platform-6.0.0.tar.gz
cd -


log "Extend Kubernetes with first class CP primitives"
kubectl apply --filename ${DIR}/confluent-operator/resources/crds/

log "Create the Kubernetes namespace to install Operator"
kubectl create namespace operator

log "installing operator"
helm upgrade --install \
  operator \
  ${DIR}/confluent-operator/helm/confluent-operator/ \
  --values $VALUES_FILE \
  --namespace operator \
  --set operator.enabled=true \
  --set global.sasl.plain.username="${CLOUD_KEY}" \
  --set global.sasl.plain.password="${CLOUD_SECRET}"

SR_USERNAME=$(echo $SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO | cut -d ":" -f 1)
SR_SECRET=$(echo $SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO | cut -d ":" -f 2)

log "install connect"
helm upgrade --install \
  connectors \
    ${DIR}/confluent-operator/helm/confluent-operator/ \
  --values $VALUES_FILE \
  --namespace operator \
  --set connect.enabled=true \
  --set global.sasl.plain.username="${CLOUD_KEY}" \
  --set global.sasl.plain.password="${CLOUD_SECRET}" \
  --set connect.image.tag=${TAG} \
  --set connect.dependencies.kafka.bootstrapEndpoint="${BOOTSTRAP_SERVERS}" \
  --set connect.dependencies.schemaRegistry.url="${SCHEMA_REGISTRY_URL}" \
  --set connect.dependencies.schemaRegistry.authentication.username="${SR_USERNAME}" \
  --set connect.dependencies.schemaRegistry.authentication.password="${SR_SECRET}"

log "install control-center"
helm upgrade --install \
  controlcenter \
    ${DIR}/confluent-operator/helm/confluent-operator/ \
  --values $VALUES_FILE \
  --namespace operator \
  --set controlcenter.enabled=true \
  --set global.sasl.plain.username="${CLOUD_KEY}" \
  --set global.sasl.plain.password="${CLOUD_SECRET}" \
  --set controlcenter.dependencies.c3KafkaCluster.bootstrapEndpoint="${BOOTSTRAP_SERVERS}" \
  --set controlcenter.dependencies.schemaRegistry.url="${SCHEMA_REGISTRY_URL}" \
  --set controlcenter.dependencies.schemaRegistry.authentication.username="${SR_USERNAME}" \
  --set controlcenter.dependencies.schemaRegistry.authentication.password="${SR_SECRET}"

# kubectl -n kafka-dest exec -it connect-0 -- bash


log "Sleep 60 seconds to let pods being started"
sleep 60

set +e
# Verify Kafka Connect has started within MAX_WAIT seconds
MAX_WAIT=480
CUR_WAIT=0
log "Waiting up to $MAX_WAIT seconds for Kafka Connect connect-0 to start"
kubectl logs -n kafka-dest connect-0 > /tmp/out.txt 2>&1
while [[ ! $(cat /tmp/out.txt) =~ "Finished starting connectors and tasks" ]]; do
  sleep 10
  kubectl logs -n kafka-dest connect-0 > /tmp/out.txt 2>&1
  CUR_WAIT=$(( CUR_WAIT+10 ))
  if [[ "$CUR_WAIT" -gt "$MAX_WAIT" ]]; then
    echo -e "\nERROR: The logs in connect-0 container do not show 'Finished starting connectors and tasks' after $MAX_WAIT seconds. Please troubleshoot'.\n"
    exit 1
  fi
done
log "Connect connect-0 has started!"
set -e

exit 0

log "create a topic example on kafka-src cluster"
kubectl -n kafka-src exec -i kafka-0 -- bash -c 'kafka-topics --create --topic example --partitions 1 --replication-factor 1 --bootstrap-server kafka:9071'

log "create replicator"
kubectl -n kafka-dest exec -i replicator-0 -- curl -k -X PUT \
     -H "Content-Type: application/json" \
     --data '{
            "connector.class": "io.confluent.connect.replicator.ReplicatorSourceConnector",
            "tasks.max": "1",
            "topic.whitelist": "example",
            "key.converter": "io.confluent.connect.replicator.util.ByteArrayConverter",
            "value.converter": "io.confluent.connect.replicator.util.ByteArrayConverter",
            "src.kafka.bootstrap.servers": "kafka-0.kafka.kafka-src.svc.cluster.local:9092",
            "src.kafka.security.protocol": "SSL",
            "src.kafka.ssl.truststore.location": "/tmp/truststore.jks",
            "src.kafka.ssl.truststore.password": "mystorepassword",
            "dest.kafka.bootstrap.servers": "kafka-0.kafka.kafka-dest.svc.cluster.local:9092",
            "dest.kafka.security.protocol": "SSL",
            "dest.kafka.ssl.truststore.location": "/tmp/truststore.jks",
            "dest.kafka.ssl.truststore.password": "mystorepassword",
            "confluent.license": "",
            "confluent.topic.replication.factor": "1",
            "confluent.topic.bootstrap.servers": "kafka-0.kafka.kafka-dest.svc.cluster.local:9092",
            "confluent.topic.security.protocol": "SSL",
            "confluent.topic.ssl.truststore.location": "/tmp/truststore.jks",
            "confluent.topic.ssl.truststore.password": "mystorepassword"
          }' \
     https://localhost:8083/connectors/test-replicator/config

log "produce data on topic example on kafka-src cluster"
kubectl -n kafka-src exec -i kafka-0 -- bash -c 'seq 10 | kafka-console-producer --broker-list kafka:9071 --topic example'

sleep 5

log "check data on topic example on kafka-dest cluster"
kubectl -n kafka-dest exec -i kafka-0 -- bash -c 'kafka-console-consumer -bootstrap-server kafka:9071 --topic example --from-beginning --max-messages 10'

# log "In order to access C3, execute this (sudo password will be required)"
# log "minikube tunnel"

# log "/etc/hosts"

# echo $(kubectl get service controlcenter-bootstrap-lb \
#       --output=jsonpath={'.status.loadBalancer.ingress[0].ip'} \
#       --namespace=kafka-dest) \
#   controlcenter.confluent.platform.playground.demo | sudo tee -a /etc/hosts


# log "Open Control Center"

# ```bash
# $ open http://controlcenter.confluent.platform.playground.demo (`admin`/`Developer1`)
# ```


# ### Clean up

# Un-hack /etc/hosts

# ```bash
# $ minikube delete
# ```
