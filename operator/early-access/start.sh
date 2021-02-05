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

verify_memory
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

log "Setup Operator Early Access credentials."
kubectl create secret docker-registry confluent-registry \
  --docker-server=confluent-docker-internal-early-access-operator-2.jfrog.io \
  --docker-username=$USER \
        --docker-password=$APIKEY \
        --docker-email=$EMAIL

set +e
helm repo remove confluentinc_earlyaccess
helm repo add confluentinc_earlyaccess \
  https://confluent.jfrog.io/confluent/helm-early-access-operator-2 \
  --username $USER \
  --password $APIKEY
set -e

helm repo update

log "Create the Kubernetes namespaces to install Operator and cluster"
kubectl create namespace confluent
kubectl config set-context --current --namespace=confluent

log "installing operator"
helm upgrade --install operator confluentinc_earlyaccess/confluent-operator \
  --set image.registry=confluent-docker-internal-early-access-operator-2.jfrog.io

log "install cluster"
kubectl apply -f "${DIR}/confluent-platform.yaml"

kubectl get confluent