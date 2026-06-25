#!/bin/bash

set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

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
docker build -t local/httpserver-cfk:latest "${DIR}/../../connect/connect-http-sink/httpserver"

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

log "Deploy Confluent Platform and HTTP server"
envsubst '${CP_SERVER_IMAGE} ${CP_SERVER_TAG} ${CP_CONNECT_IMAGE} ${CP_CONNECT_TAG} ${CP_SCHEMA_REGISTRY_IMAGE} ${CP_SCHEMA_REGISTRY_TAG} ${CP_CONTROL_CENTER_IMAGE} ${CP_CONTROL_CENTER_TAG} ${CP_INIT_IMAGE} ${CP_INIT_TAG} ${HTTP_CONNECTOR_VERSION}' < "${DIR}/confluent-platform.yaml" | kubectl apply -f -
kubectl apply -f "${DIR}/httpserver.yaml"

log "⌛ Waiting up to 900 seconds for all pods in namespace confluent to start"
wait-until-pods-ready "900" "10" "confluent"

log "Create topics"
kubectl apply -f "${DIR}/create-kafka-topics.yaml"

CONTROL_CENTER_PF_PID=""
HTTPSERVER_PF_PID=""
cleanup() {
  if [ -n "$CONTROL_CENTER_PF_PID" ]
  then
    kill "$CONTROL_CENTER_PF_PID" >/dev/null 2>&1 || true
  fi
  if [ -n "$HTTPSERVER_PF_PID" ]
  then
    kill "$HTTPSERVER_PF_PID" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

log "Port-forward controlcenter and httpserver"
kubectl -n confluent port-forward service/controlcenter 9021:9021 >/tmp/control-center-port-forward.log 2>&1 &
CONTROL_CENTER_PF_PID=$!
kubectl -n confluent port-forward service/httpserver 9006:9006 >/tmp/httpserver-port-forward.log 2>&1 &
HTTPSERVER_PF_PID=$!
sleep 10

log "Set webserver to reply with 200"
curl -sS -X PUT -H "Content-Type: application/json" --data '{"errorCode": 200}' http://localhost:9006/set-response-error-code >/dev/null
curl -sS -X PUT -H "Content-Type: application/json" --data '{"message":"Hello, World!"}' http://localhost:9006/set-response-body >/dev/null

log "Sending messages to topic http-messages"
kubectl -n confluent exec connect-0 -- bash -c 'for i in $(seq 1 10); do echo "{\"id\":$i,\"name\":\"user-$i\",\"email\":\"user-$i@example.com\"}"; done | kafka-console-producer --bootstrap-server kafka:9071 --topic http-messages' >/dev/null

log "Creating http-sink connector using CFK Connector CR"
kubectl apply -f "${DIR}/http-sink-connector.yaml"

log "Wait for connector http-sink to be RUNNING"
max_wait=180
waited=0
connector_state=""
tasks_ready=""
until [ "$waited" -ge "$max_wait" ]
do
  connector_state=$(kubectl -n confluent get connector http-sink -o jsonpath='{.status.connectorState}' 2>/dev/null || true)
  tasks_ready=$(kubectl -n confluent get connector http-sink -o jsonpath='{.status.tasksReady}' 2>/dev/null || true)
  if [ "$connector_state" = "RUNNING" ] && [ "$tasks_ready" = "1" ]
  then
    break
  fi
  sleep 5
  waited=$((waited + 5))
done

if [ "$connector_state" != "RUNNING" ]
then
  logerror "❌ connector http-sink did not reach RUNNING state in ${max_wait}s"
  kubectl -n confluent describe connector http-sink || true
  exit 1
fi

sleep 20

log "Check success-responses topic"
kubectl -n confluent exec connect-0 -- kafka-console-consumer --bootstrap-server kafka:9071 --topic success-responses --from-beginning --max-messages 10 --timeout-ms 60000

log "Control Center is reachable at http://127.0.0.1:9021"