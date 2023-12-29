#!/bin/bash

set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

bootstrap_ccloud_environment

if [ -f ${DIR}/../../.ccloud/env.delta ]
then
     source ${DIR}/../../.ccloud/env.delta
else
     logerror "ERROR: ${DIR}/../../.ccloud/env.delta has not been generated"
     exit 1
fi

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

log "Create the Kubernetes namespaces to install Operator and cluster"
kubectl create namespace confluent
kubectl config set-context --current --namespace=confluent

set +e
helm repo remove confluentinc
log "Add the Confluent for Kubernetes Helm repository"
helm repo add confluentinc https://packages.confluent.io/helm
helm repo update
set -e

log "Install Confluent for Kubernetes"
helm upgrade --install confluent-operator confluentinc/confluent-for-kubernetes

log "Generate a CA pair"
docker run -u0 --rm -v $PWD:/tmp ${CP_CONNECT_IMAGE}:${CONNECT_TAG} bash -c "openssl genrsa -out /tmp/ca-key.pem 2048 && chown -R $(id -u $USER):$(id -g $USER) /tmp/"
docker run -u0 --rm -v $PWD:/tmp ${CP_CONNECT_IMAGE}:${CONNECT_TAG} bash -c "openssl req -new -key /tmp/ca-key.pem -x509 -days 1000 -out /tmp/ca.pem -subj '/C=US/ST=CA/L=MountainView/O=Confluent/OU=Operator/CN=TestCA' && chown -R $(id -u $USER):$(id -g $USER) /tmp/"

log "Create a Kuebernetes secret for inter-component TLS"
kubectl create secret tls ca-pair-sslcerts \
  --cert=${DIR}/ca.pem \
  --key=${DIR}/ca-key.pem

log "Provide authentication credentials"

# generate creds-client-kafka-sasl-user.txt config
sed -e "s|:CLOUD_KEY:|$CLOUD_KEY|g" \
    -e "s|:CLOUD_SECRET:|$CLOUD_SECRET|g" \
    ${DIR}/creds-client-kafka-sasl-user-template.txt > ${DIR}/creds-client-kafka-sasl-user.txt
SR_USERNAME=$(echo $SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO | cut -d ":" -f 1)
SR_SECRET=$(echo $SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO | cut -d ":" -f 2)
# generate creds-schemaRegistry-user.txt config
sed -e "s|:SR_USERNAME:|$SR_USERNAME|g" \
    -e "s|:SR_SECRET:|$SR_SECRET|g" \
    ${DIR}/creds-schemaRegistry-user-template.txt > ${DIR}/creds-schemaRegistry-user.txt

kubectl create secret generic cloud-plain \
--from-file=plain.txt=${PWD}/creds-client-kafka-sasl-user.txt
kubectl create secret generic cloud-sr-access \
--from-file=basic.txt=${PWD}/creds-schemaRegistry-user.txt
kubectl create secret generic control-center-user \
--from-file=basic.txt=${PWD}/creds-control-center-users.txt

# generate confluent-platform-template.yaml config
sed -e "s|BOOTSTRAP_SERVERS|$BOOTSTRAP_SERVERS|g" \
    -e "s|SCHEMA_REGISTRY_URL|$SCHEMA_REGISTRY_URL|g" \
    ${DIR}/confluent-platform-template.yaml > ${DIR}/confluent-platform.yaml

log "install cluster"
kubectl apply -f "${DIR}/confluent-platform.yaml"

log "⌛ Waiting up to 900 seconds for all pods in namespace confluent to start"
wait-until-pods-ready "900" "10" "confluent"

kubectl get confluent

log "Control Center is reachable at http://127.0.0.1:9021"
kubectl -n confluent port-forward controlcenter-0 9021:9021 &