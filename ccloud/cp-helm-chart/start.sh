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

log "Launch minikube dashboard in background"
set +e
minikube dashboard &
set -e
#helm repo add stable https://charts.helm.sh/stable
#helm repo update
#helm repo add confluentinc https://confluentinc.github.io/cp-helm-charts/

git clone https://github.com/confluentinc/cp-helm-charts.git

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
  --set image="vdesabou/kafka-docker-playground-connect" \
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
  --set configurationOverrides."value\.converter\.basic\.auth\.credentials\.source"=USER_INFO \
  --set configurationOverrides."value\.converter\.schema\.registry\.basic\.auth\.user\.info"="${SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO}" \
  --set configurationOverrides."value\.converter\.schema\.registry\.url"="${SCHEMA_REGISTRY_URL}"


log "Sleep 60 seconds to let pods being started"
sleep 60

set +e
# Verify Kafka Connect has started within MAX_WAIT seconds
MAX_WAIT=480
CUR_WAIT=0
CONNECT_POD_NAME=$(kubectl get pods -n cp-helm-charts --selector=app=cp-kafka-connect -o jsonpath="{.items[0].metadata.name}")
log "Waiting up to $MAX_WAIT seconds for Kafka Connect $CONNECT_POD_NAME to start"
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

#######
# CONNECTOR TEST: Spool dir
#######

set +e
log "Create topic spooldir-json-topic"
kubectl -c cp-kafka-connect-server cp ${CONFIG_FILE} cp-helm-charts/$CONNECT_POD_NAME:/tmp/config
kubectl -n cp-helm-charts -c cp-kafka-connect-server exec -it $CONNECT_POD_NAME -- kafka-topics --bootstrap-server ${BOOTSTRAP_SERVERS} --command-config /tmp/config --topic spooldir-json-topic --create --replication-factor 3 --partitions 1
set +e

if [ ! -f "${DIR}/json-spooldir-source.json" ]
then
     log "Generating data"
     curl "https://api.mockaroo.com/api/17c84440?count=500&key=25fd9c80" > "${DIR}/json-spooldir-source.json"
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
                "value.converter.schema.registry.url": "'"$SCHEMA_REGISTRY_URL"'",
                "value.converter.basic.auth.user.info": "'"$SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO"'",
                "value.converter.basic.auth.credentials.source": "USER_INFO"
          }' \
     http://localhost:8083/connectors/spool-dir-source/config | jq

sleep 5

log "Verify we have received the data in spooldir-json-topic topic"
kubectl -n cp-helm-charts -c cp-kafka-connect-server exec -it $CONNECT_POD_NAME -- kafka-avro-console-consumer --topic spooldir-json-topic --bootstrap-server $BOOTSTRAP_SERVERS --consumer-property ssl.endpoint.identification.algorithm=https --consumer-property sasl.mechanism=PLAIN --consumer-property security.protocol=SASL_SSL --consumer-property sasl.jaas.config="$SASL_JAAS_CONFIG" --property basic.auth.credentials.source=$BASIC_AUTH_CREDENTIALS_SOURCE --property schema.registry.basic.auth.user.info="$SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO" --property schema.registry.url=$SCHEMA_REGISTRY_URL --from-beginning --max-messages 2


#######
# MONITORING
#######
# https://github.com/confluentinc/cp-helm-charts#monitoring
log "Install Prometheus"
helm install prometheus stable/prometheus
log "Install Grafana"
helm install grafana stable/grafana

sleep 90

log "Open Grafana in your Browser"
export POD_NAME=$(kubectl get pods -l "app.kubernetes.io/name=grafana,app.kubernetes.io/instance=grafana" -o jsonpath="{.items[0].metadata.name}")
kubectl port-forward $POD_NAME 3000 &

password=$(kubectl get secret grafana -o jsonpath="{.data.admin-password}" | base64 --decode)

log "Visit http://localhost:3000 in your browser, and login with admin/$password."
open "http://127.0.0.1:3000" &


log "Add Prometheus data source with url http://prometheus-server.default.svc.cluster.local"
log "Then you can import dashboard with id 1860 for node exporter full, and https://github.com/confluentinc/cp-helm-charts/blob/master/grafana-dashboard/confluent-open-source-grafana-dashboard.json"