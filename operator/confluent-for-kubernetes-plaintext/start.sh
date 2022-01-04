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

log "Install cluster"
kubectl apply -f "${DIR}/confluent-platform.yaml"

log "⌛ Waiting up to 900 seconds for all pods in namespace confluent to start"
wait-until-pods-ready "900" "10" "confluent"

kubectl get confluent

log "Control Center is reachable at http://127.0.0.1:9021"
kubectl -n confluent port-forward controlcenter-0 9021:9021 &


# helm pull confluentinc_earlyaccess/confluent-for-kubernetes --untar --untardir=.

log "Create a topic"
kubectl apply -f create-kafka-topic.yaml