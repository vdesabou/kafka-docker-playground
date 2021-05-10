#!/bin/bash

set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

USER=${USER:-$1}
EMAIL=${EMAIL:-$2}
APIKEY=${APIKEY:-$3}

if [ -z "$USER" ]
then
     logerror "USER is not set. Export it as environment variable or pass it as argument"
     exit 1
fi

if [ -z "$EMAIL" ]
then
     logerror "EMAIL is not set. Export it as environment variable or pass it as argument"
     exit 1
fi

if [ -z "$APIKEY" ]
then
     logerror "APIKEY is not set. Export it as environment variable or pass it as argument"
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

log "Setup Operator Early Access credentials."
kubectl create secret docker-registry confluent-registry \
  --docker-server=confluent-docker-internal-early-access-operator-2.jfrog.io \
  --docker-username=$USER \
        --docker-password=$APIKEY \
        --docker-email=$EMAIL

set +e
helm repo remove confluentinc_earlyaccess
log "Add repo confluentinc_earlyaccess"
helm repo add confluentinc_earlyaccess \
  https://confluent.jfrog.io/confluent/helm-early-access-operator-2 \
  --username $USER \
  --password $APIKEY
helm repo update
set -e

log "Deploy Confluent Operator"
helm upgrade --install operator confluentinc_earlyaccess/confluent-for-kubernetes \
  --set image.registry=confluent-docker-internal-early-access-operator-2.jfrog.io

log "install cluster"
kubectl apply -f "${DIR}/confluent-platform.yaml"

log "Waiting up to 900 seconds for all pods in namespace confluent to start"
wait-until-pods-ready "900" "10" "confluent"

kubectl get confluent