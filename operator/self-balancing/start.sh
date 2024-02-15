#!/bin/bash

set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

verify_docker_and_memory
verify_installed "kubectl"
verify_installed "minikube"
verify_installed "helm"

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
wget -q https://platform-ops-bin.s3-us-west-1.amazonaws.com/operator/confluent-operator-1.7.0.tar.gz
tar xvfz confluent-operator-1.7.0.tar.gz
cd -


log "Extend Kubernetes with first class CP primitives"
kubectl apply --filename ${DIR}/confluent-operator/resources/crds/

log "Create the Kubernetes namespaces to install Operator and clusters"

kubectl create namespace confluent

# Use most basic values file and override it with --set
VALUES_FILE="${DIR}/../../operator/private.yaml"

log "installing operator"
helm upgrade --install \
  operator \
  ${DIR}/confluent-operator/helm/confluent-operator/ \
  --values $VALUES_FILE \
  --namespace confluent \
  --set operator.enabled=true

log "install operator cluster"
helm upgrade --install \
  zookeeper \
  ${DIR}/confluent-operator/helm/confluent-operator/ \
  --values $VALUES_FILE \
  --namespace confluent \
  --set zookeeper.enabled=true

helm upgrade --install \
  kafka \
  ${DIR}/confluent-operator/helm/confluent-operator/ \
  --values $VALUES_FILE \
  --namespace confluent \
  --set kafka.enabled=true \
  --set kafka.replicas=3 \
  --set kafka.metricReporter.enabled=true \
  --set kafka.metricReporter.bootstrapEndpoint="kafka:9071" \
  --set kafka.oneReplicaPerNode=false


  # --set 'kafka.configOverrides.server[0]=confluent.license.topic.replication.factor=1' \
  # --set 'kafka.configOverrides.server[1]=confluent.balancer.enable=true' \
  # --set 'kafka.configOverrides.server[2]=confluent.balancer.heal.uneven.load.trigger=ANY_UNEVEN_LOAD'


helm upgrade --install \
  replicator \
    ${DIR}/confluent-operator/helm/confluent-operator/ \
  --values $VALUES_FILE \
  --namespace confluent \
  --set replicator.enabled=true \
  --set replicator.dependencies.kafka.brokerCount=3

helm upgrade --install \
  controlcenter \
    ${DIR}/confluent-operator/helm/confluent-operator/ \
  --values $VALUES_FILE \
  --namespace confluent \
  --set controlcenter.enabled=true


# kubectl -n confluent exec -it replicator-0 -- bash


log "Sleep 60 seconds to let pods being started"
sleep 60

set +e
# Verify Kafka Connect has started within MAX_WAIT seconds
MAX_WAIT=480
CUR_WAIT=0
log "⌛ Waiting up to $MAX_WAIT seconds for Kafka Connect replicator-0 to start"
kubectl logs -n confluent replicator-0 > /tmp/out.txt 2>&1
while [[ ! $(cat /tmp/out.txt) =~ "Finished starting connectors and tasks" ]]; do
  sleep 10
  kubectl logs -n confluent replicator-0 > /tmp/out.txt 2>&1
  CUR_WAIT=$(( CUR_WAIT+10 ))
  if [[ "$CUR_WAIT" -gt "$MAX_WAIT" ]]; then
    echo -e "\nERROR: The logs in replicator-0 container do not show 'Finished starting connectors and tasks' after $MAX_WAIT seconds. Please troubleshoot'.\n"
    exit 1
  fi
done
log "Connect replicator-0 has started!"
set -e

log "⌛ Waiting up to 900 seconds for all pods in namespace confluent to start"
wait-until-pods-ready "900" "10" "confluent"

log "Control Center is reachable at http://127.0.0.1:9021 (admin/Developer1)"
kubectl -n confluent port-forward controlcenter-0 9021:9021 &

# https://github.com/confluentinc/demo-scene/tree/master/self-balancing
log "Create a topic sbk, We are forcing the topic to not create replicas in broker 2 to create an uneven load"
kubectl cp ${DIR}/kafka.properties confluent/kafka-0:/tmp/config
kubectl -n confluent exec -i kafka-0 -- bash -c 'kafka-topics --create --topic sbk --bootstrap-server kafka:9071 --command-config /tmp/config --replica-assignment 0:1,0:1,0:1,0:1,0:1,0:1,0:1,0:1,0:1,0:1,0:1,0:1,0:1,0:1,0:1,0:1,0:1,0:1,0:1,0:1,0:1,0:1,0:1,0:1,0:1,0:1,0:1,0:1,0:1,0:1,0:1,0:1,0:1,0:1,0:1,0:1,0:1,0:1,0:1,0:1,0:1,0:1,0:1,0:1,0:1,0:1,0:1,0:1,0:1,0:1,0:1,0:1,0:1,0:1,0:1,0:1,0:1,0:1,0:1,0:1,0:1,0:1,0:1,0:1,0:1,0:1,0:1,0:1,0:1,0:1,0:1,0:1,0:1,0:1,0:1,0:1,0:1,0:1,0:1,0:1,0:1,0:1,0:1,0:1,0:1,0:1,0:1,0:1,0:1,0:1,0:1,0:1,0:1,0:1,0:1,0:1,0:1,0:1,0:1,0:1'

log "Produce Data"
kubectl -n confluent exec -i kafka-0 -- bash -c 'kafka-producer-perf-test --producer-props bootstrap.servers=kafka:9071 --producer.config /tmp/config --topic sbk --record-size 1000 --throughput 100000 --num-records 3600000'

log "enable self balancing"
helm upgrade --install \
  kafka \
  ${DIR}/confluent-operator/helm/confluent-operator/ \
  --values $VALUES_FILE \
  --namespace confluent \
  --set kafka.enabled=true \
  --set kafka.replicas=3 \
  --set kafka.metricReporter.enabled=true \
  --set kafka.metricReporter.bootstrapEndpoint="kafka:9071" \
  --set kafka.oneReplicaPerNode=false \
  --set 'kafka.configOverrides.server[0]=confluent.license.topic.replication.factor=1' \
  --set 'kafka.configOverrides.server[1]=confluent.balancer.enable=true' \
  --set 'kafka.configOverrides.server[2]=confluent.balancer.heal.uneven.load.trigger=ANY_UNEVEN_LOAD'
