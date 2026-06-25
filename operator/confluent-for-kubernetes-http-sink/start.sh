#!/bin/bash

set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"cfk"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}"

eval $(minikube docker-env)
docker build -t local/httpserver-cfk:latest "${DIR}/../../connect/connect-http-sink/httpserver"
kubectl apply -f "${DIR}/httpserver.yaml"

log "⌛ Waiting up to 900 seconds for all pods in namespace confluent to start"
wait-until-pods-ready "900" "10" "confluent"

log "Create topics"
kubectl apply -f "${DIR}/create-kafka-topics.yaml"

HTTPSERVER_PF_PID=""
cleanup() {
  if [ -n "$HTTPSERVER_PF_PID" ]
  then
    kill "$HTTPSERVER_PF_PID" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

log "Port-forward httpserver"
kubectl -n confluent port-forward service/httpserver 9006:9006 >/tmp/httpserver-port-forward.log 2>&1 &
HTTPSERVER_PF_PID=$!
sleep 10

log "Set webserver to reply with 200"
curl -sS -X PUT -H "Content-Type: application/json" --data '{"errorCode": 200}' http://localhost:9006/set-response-error-code >/dev/null
curl -sS -X PUT -H "Content-Type: application/json" --data '{"message":"Hello, World!"}' http://localhost:9006/set-response-body >/dev/null

log "Sending messages to topic http-messages"
playground topic produce -t http-messages --nb-messages 10 << 'EOF'
{
  "id": "iteration.index",
  "name": "user-%g",
  "email": "user-%g@example.com"
}
EOF

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