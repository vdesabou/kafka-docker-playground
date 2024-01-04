#!/bin/bash

set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

verify_docker_and_memory
verify_installed "kubectl"
verify_installed "minikube"
verify_installed "helm"

bootstrap_ccloud_environment



# https://github.com/confluentinc/cp-helm-charts#appendix-create-a-local-kubernetes-cluster
set +e
log "Stop minikube if required"
minikube delete
set -e
log "Start minikube"
minikube start --cpus=8 --disk-size='50gb' --memory=16384

minikube ssh -- sudo ip link set docker0 promisc on
eval $(minikube docker-env)
kubectl config set-context minikube.internal --cluster=minikube --user=minikube
kubectl config use-context minikube.internal
kubectl config current-context
kubectl cluster-info

if [ -d ${DIR}/cp-helm-charts ]
then
  log "cp-helm-charts repository already exists"
  read -p "Do you want to get the latest version? (y/n)?" choice
  case "$choice" in
  y|Y )
    rm -rf ${DIR}/cp-helm-charts
    log "Getting cp-helm-charts from Github (branch $GIT_BRANCH)"
    cd ${DIR}
    git clone https://github.com/confluentinc/cp-helm-charts.git
    cd ${DIR}/cp-helm-charts
    git checkout "${GIT_BRANCH}"
  ;;
  n|N ) ;;
  * ) logerror "ERROR: invalid response!";exit 1;;
  esac
fi

log "Launch minikube dashboard in background"
set +e
minikube dashboard &
set -e

log "Create the Kubernetes namespace to install cp-helm-charts"
kubectl create namespace cp-helm-charts

SR_USERNAME=$(echo $SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO | cut -d ":" -f 1)
SR_SECRET=$(echo $SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO | cut -d ":" -f 2)

log "Install connect"
helm upgrade --install \
   connect \
    ${DIR}/cp-helm-charts/charts/cp-kafka-connect \
  --values ${DIR}/cp-helm-charts/charts/cp-kafka-connect/values.yaml \
  --namespace cp-helm-charts \
  --set kafka.bootstrapServers="${BOOTSTRAP_SERVERS}" \
  --set imagePullPolicy="IfNotPresent" \
  --set image="${CP_CONNECT_IMAGE}" \
  --set imageTag="${TAG}" \
  --set configurationOverrides."ssl\.endpoint\.identification\.algorithm"=https \
  --set configurationOverrides."security\.protocol"=SASL_SSL \
  --set configurationOverrides."sasl\.mechanism"=PLAIN \
  --set configurationOverrides."sasl\.jaas\.config"="org.apache.kafka.common.security.plain.PlainLoginModule required username=\"${CLOUD_KEY}\" password=\"${CLOUD_SECRET}\";" \
  --set configurationOverrides."request\.timeout\.ms"=20000 \
  --set configurationOverrides."retry\.backoff\.ms"=500 \
  --set configurationOverrides."producer\.bootstrap\.servers"="${BOOTSTRAP_SERVERS}" \
  --set configurationOverrides."producer\.ssl\.endpoint\.identification\.algorithm"=https \
  --set configurationOverrides."producer\.security\.protocol"=SASL_SSL \
  --set configurationOverrides."producer\.sasl\.mechanism"=PLAIN \
  --set configurationOverrides."producer\.sasl\.jaas\.config"="org.apache.kafka.common.security.plain.PlainLoginModule required username=\"${CLOUD_KEY}\" password=\"${CLOUD_SECRET}\";" \
  --set configurationOverrides."producer\.request\.timeout\.ms"=20000 \
  --set configurationOverrides."producer\.retry\.backoff\.ms"=500 \
  --set configurationOverrides."consumer\.bootstrap\.servers"="${BOOTSTRAP_SERVERS}" \
  --set configurationOverrides."consumer\.ssl\.endpoint\.identification\.algorithm"=https \
  --set configurationOverrides."consumer\.security\.protocol"=SASL_SSL \
  --set configurationOverrides."consumer\.sasl\.mechanism"=PLAIN \
  --set configurationOverrides."consumer\.sasl\.jaas\.config"="org.apache.kafka.common.security.plain.PlainLoginModule required username=\"${CLOUD_KEY}\" password=\"${CLOUD_SECRET}\";" \
  --set configurationOverrides."consumer\.request\.timeout\.ms"=20000 \
  --set configurationOverrides."consumer\.retry\.backoff\.ms"=500 \
  --set cp-schema-registry.url="${SCHEMA_REGISTRY_URL}" \
  --set configurationOverrides."key\.converter\.basic\.auth\.credentials\.source"=USER_INFO \
  --set configurationOverrides."key\.converter\.schema\.registry\.basic\.auth\.user\.info"="${SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO}" \
  --set configurationOverrides."key\.converter\.schema\.registry\.url"="${SCHEMA_REGISTRY_URL}" \
  --set configurationOverrides."value\.converter\.basic\.auth\.credentials\.source"=USER_INFO \
  --set configurationOverrides."value\.converter\.schema\.registry\.basic\.auth\.user\.info"="${SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO}" \
  --set configurationOverrides."value\.converter\.schema\.registry\.url"="${SCHEMA_REGISTRY_URL}"

log "Install control-center"
helm upgrade --install \
  controlcenter \
    ${DIR}/cp-helm-charts/charts/cp-control-center \
  --values ${DIR}/cp-helm-charts/charts/cp-control-center/values.yaml \
  --namespace cp-helm-charts \
  --set kafka.bootstrapServers="${BOOTSTRAP_SERVERS}" \
  --set cp-kafka-connect.url="http://connect-cp-kafka-connect.cp-helm-charts.svc.cluster.local:8083" \
  --set configurationOverrides."bootstrap.\servers"="${BOOTSTRAP_SERVERS}" \
  --set configurationOverrides."streams\.ssl\.endpoint\.identification\.algorithm"=https \
  --set configurationOverrides."streams\.security\.protocol"=SASL_SSL \
  --set configurationOverrides."streams\.sasl\.mechanism"=PLAIN \
  --set configurationOverrides."streams\.sasl\.jaas\.config"="org.apache.kafka.common.security.plain.PlainLoginModule required username=\"${CLOUD_KEY}\" password=\"${CLOUD_SECRET}\";" \
  --set configurationOverrides."confluent\.metrics\.topic\.max\.message\.bytes"=8388608 \
  --set configurationOverrides."schema\.registry\.basic\.auth\.credentials\.source"=USER_INFO \
  --set configurationOverrides."schema\.registry\.basic\.auth\.user\.info"="${SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO}" \
  --set configurationOverrides."schema\.registry\.url"="${SCHEMA_REGISTRY_URL}" \
  --set configurationOverrides."replication\.factor"=3 \
  --set configurationOverrides."internal\.topics\.replication"=3 \
  --set configurationOverrides."internal\.topics\.partitions"=1 \
  --set configurationOverrides."command\.topic\.replication"=3 \
  --set configurationOverrides."metrics\.topic\.replication"=3

log "Sleep 60 seconds to let pods being started"
sleep 60

set +e
# Verify Kafka Connect has started within MAX_WAIT seconds
MAX_WAIT=480
CUR_WAIT=0
CONNECT_POD_NAME=$(kubectl get pods -n cp-helm-charts --selector=app=cp-kafka-connect -o jsonpath="{.items[0].metadata.name}")
log "⌛ Waiting up to $MAX_WAIT seconds for Kafka Connect $CONNECT_POD_NAME to start"
kubectl logs -n cp-helm-charts $CONNECT_POD_NAME -c cp-kafka-connect-server > /tmp/out.txt 2>&1
while [[ ! $(cat /tmp/out.txt) =~ "Finished starting connectors and tasks" ]]; do
  sleep 10
  kubectl logs -n cp-helm-charts $CONNECT_POD_NAME -c cp-kafka-connect-server > /tmp/out.txt 2>&1
  CUR_WAIT=$(( CUR_WAIT+10 ))
  if [[ "$CUR_WAIT" -gt "$MAX_WAIT" ]]; then
    echo -e "\nERROR: The logs in $CONNECT_POD_NAME container do not show 'Finished starting connectors and tasks' after $MAX_WAIT seconds. Please troubleshoot'.\n"
    exit 1
  fi
done
log "Connect $CONNECT_POD_NAME has started!"
set -e

log "⌛ Waiting up to 900 seconds for all pods in namespace cp-helm-charts to start"
wait-until-pods-ready "900" "10" "cp-helm-charts"

C3_POD_NAME=$(kubectl get pods -n cp-helm-charts --selector=app=cp-control-center -o jsonpath="{.items[0].metadata.name}")
log "Control Center is reachable at http://127.0.0.1:9021 (admin/Developer1)"
kubectl -n cp-helm-charts port-forward ${C3_POD_NAME} 9021:9021 &

#######
# CONNECTOR TEST: Spool dir
#######

set +e
log "Delete and re-create topic spooldir-json-topic"
kubectl -c cp-kafka-connect-server cp ${CONFIG_FILE} cp-helm-charts/$CONNECT_POD_NAME:/tmp/config
kubectl -n cp-helm-charts -c cp-kafka-connect-server exec -i $CONNECT_POD_NAME -- bash -c "KAFKA_HEAP_OPTS=\"\" kafka-topics --bootstrap-server ${BOOTSTRAP_SERVERS} --command-config /tmp/config --topic spooldir-json-topic --delete"
kubectl -n cp-helm-charts -c cp-kafka-connect-server exec -i $CONNECT_POD_NAME -- bash -c "KAFKA_HEAP_OPTS=\"\" kafka-topics --bootstrap-server ${BOOTSTRAP_SERVERS} --command-config /tmp/config --topic spooldir-json-topic --create --replication-factor 3 --partitions 1"
set +e

if [ ! -f "${DIR}/json-spooldir-source.json" ]
then
     log "Generating data"
     curl -k "https://api.mockaroo.com/api/17c84440?count=500&key=25fd9c80" > "${DIR}/json-spooldir-source.json"
fi

kubectl -n cp-helm-charts -c cp-kafka-connect-server exec -it $CONNECT_POD_NAME -- mkdir -p /tmp/data/input
kubectl -n cp-helm-charts -c cp-kafka-connect-server exec -it $CONNECT_POD_NAME -- mkdir -p /tmp/data/error
kubectl -n cp-helm-charts -c cp-kafka-connect-server exec -it $CONNECT_POD_NAME -- mkdir -p /tmp/data/finished

kubectl cp -c cp-kafka-connect-server json-spooldir-source.json cp-helm-charts/$CONNECT_POD_NAME:/tmp/data/input/

log "Creating JSON Spool Dir Source connector"
kubectl -n cp-helm-charts -c cp-kafka-connect-server exec -i $CONNECT_POD_NAME -- curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "tasks.max": "1",
                "connector.class": "com.github.jcustenborder.kafka.connect.spooldir.SpoolDirJsonSourceConnector",
                "input.path": "/tmp/data/input",
                "input.file.pattern": "json-spooldir-source.json",
                "error.path": "/tmp/data/error",
                "finished.path": "/tmp/data/finished",
                "halt.on.error": "false",
                "topic": "spooldir-json-topic",
                "schema.generation.enabled": "true",
                "value.converter" : "io.confluent.connect.avro.AvroConverter",
                "value.converter.schema.registry.url": "$SCHEMA_REGISTRY_URL",
                "value.converter.basic.auth.user.info": "$SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO",
                "value.converter.basic.auth.credentials.source": "USER_INFO"
          }' \
     http://localhost:8083/connectors/spool-dir-source$RANDOM/config | jq

sleep 5

log "Verify we have received the data in spooldir-json-topic topic"
playground topic consume --topic spooldir-json-topic --min-expected-messages 2 --timeout 60


#######
# MONITORING
#######
# https://github.com/confluentinc/cp-helm-charts#monitoring
log "Install Prometheus"
helm install prometheus stable/prometheus --namespace cp-helm-charts
log "Install Grafana"
helm install grafana stable/grafana --namespace cp-helm-charts

sleep 90

log "Open Grafana in your Browser"
POD_NAME=$(kubectl get pods -n cp-helm-charts -l "app.kubernetes.io/name=grafana,app.kubernetes.io/instance=grafana" -o jsonpath="{.items[0].metadata.name}")
kubectl port-forward -n cp-helm-charts $POD_NAME 3000 &

password=$(kubectl get secret -n cp-helm-charts grafana -o jsonpath="{.data.admin-password}" | base64 --decode)

log "Visit http://localhost:3000 in your browser, and login with admin/$password."
open "http://127.0.0.1:3000" &


log "Add Prometheus data source with url http://prometheus-server.cp-helm-charts.svc.cluster.local"
log "Then you can import dashboard with id 1860 for node exporter full, and https://github.com/confluentinc/cp-helm-charts/blob/master/grafana-dashboard/confluent-open-source-grafana-dashboard.json"