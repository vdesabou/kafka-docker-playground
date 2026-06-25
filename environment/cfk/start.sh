#!/bin/bash

set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

check_bash_version
check_and_update_playground_version

verify_docker_and_memory
verify_installed "kubectl"
verify_installed "minikube"
verify_installed "helm"
verify_installed "envsubst"

: "${CP_SERVER_IMAGE:=confluentinc/cp-server}"
: "${CP_SERVER_TAG:=8.3.0}"
: "${CP_CONNECT_IMAGE:=confluentinc/cp-server-connect}"
: "${CP_CONNECT_TAG:=8.3.0}"
: "${CP_SCHEMA_REGISTRY_IMAGE:=confluentinc/cp-schema-registry}"
: "${CP_SCHEMA_REGISTRY_TAG:=8.3.0}"
: "${CP_CONTROL_CENTER_IMAGE:=confluentinc/cp-enterprise-control-center-next-gen}"
: "${CP_CONTROL_CENTER_TAG:=latest}"
: "${CP_INIT_IMAGE:=confluentinc/confluent-init-container}"
: "${CP_INIT_TAG:=3.0.0}"
: "${HTTP_CONNECTOR_VERSION:=latest}"

export CP_SERVER_IMAGE CP_SERVER_TAG
export CP_CONNECT_IMAGE CP_CONNECT_TAG
export CP_SCHEMA_REGISTRY_IMAGE CP_SCHEMA_REGISTRY_TAG
export CP_CONTROL_CENTER_IMAGE CP_CONTROL_CENTER_TAG
export CP_INIT_IMAGE CP_INIT_TAG
export HTTP_CONNECTOR_VERSION

set +e
log "Stop minikube if required"
minikube delete
set -e

log "Start minikube"
minikube start --cpus=8 --disk-size='50gb' --memory=16384

log "Build images in minikube docker daemon"
eval $(minikube docker-env)

# Build/patch CP images in minikube daemon so CFK pods can use them.
maybe_create_image

log "Create namespace"
kubectl create namespace confluent || true
kubectl config set-context --current --namespace=confluent

set +e
helm repo remove confluentinc
set -e

log "Add the Confluent for Kubernetes Helm repository"
helm repo add confluentinc https://packages.confluent.io/helm
helm repo update

log "Install Confluent for Kubernetes"
helm upgrade --install confluent-operator confluentinc/confluent-for-kubernetes

log "Deploy Confluent Platform"
envsubst '${CP_SERVER_IMAGE} ${CP_SERVER_TAG} ${CP_CONNECT_IMAGE} ${CP_CONNECT_TAG} ${CP_SCHEMA_REGISTRY_IMAGE} ${CP_SCHEMA_REGISTRY_TAG} ${CP_CONTROL_CENTER_IMAGE} ${CP_CONTROL_CENTER_TAG} ${CP_INIT_IMAGE} ${CP_INIT_TAG} ${HTTP_CONNECTOR_VERSION}' < "${DIR}/confluent-platform.yaml" | kubectl apply -f -

log "⌛ Waiting up to 900 seconds for all pods in namespace confluent to start"
wait-until-pods-ready "900" "10" "confluent"


CONTROL_CENTER_PF_PID=""
SCHEMA_REGISTRY_PF_PID=""
cleanup() {
  if [ -n "$CONTROL_CENTER_PF_PID" ]
  then
    kill "$CONTROL_CENTER_PF_PID" >/dev/null 2>&1 || true
  fi
  if [ -n "$SCHEMA_REGISTRY_PF_PID" ]
  then
    kill "$SCHEMA_REGISTRY_PF_PID" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

log "Port-forward controlcenter and schema-registry"
kubectl -n confluent port-forward service/controlcenter 9021:9021 >/tmp/control-center-port-forward.log 2>&1 &
CONTROL_CENTER_PF_PID=$!
kubectl -n confluent port-forward service/schemaregistry 8081:8081 >/tmp/schema-registry-port-forward.log 2>&1 &
SCHEMA_REGISTRY_PF_PID=$!


log "Control Center is reachable at http://127.0.0.1:9021"

playground state set run.environment "cfk"