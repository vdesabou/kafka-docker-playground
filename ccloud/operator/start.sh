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

# Use most basic values file and override it with --set
VALUES_FILE="${DIR}/../../operator/private.yaml"

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
wget https://platform-ops-bin.s3-us-west-1.amazonaws.com/operator/confluent-operator-1.6.1-for-confluent-platform-6.0.0.tar.gz
tar xvfz confluent-operator-1.6.1-for-confluent-platform-6.0.0.tar.gz
cd -

# FIXTHIS: we need to do custom modifications in order to be able to connect KSQM to Confluent CLoud:
#
sed -i.bak 's/^\(.*ksql.sink.replicas=.*\)//g' ${DIR}/confluent-operator/helm/confluent-operator/charts/ksql/templates/ksql-psc.yaml
sed -i.bak 's/^\(.*ksql.streams.replication.factor=.*\)//g' ${DIR}/confluent-operator/helm/confluent-operator/charts/ksql/templates/ksql-psc.yaml
sed -i.bak 's/^\(.*          retry.backoff.ms=500\)/\1\n          ksql.internal.topic.replicas=3\n          ksql.internal.topic.replicas=3\n          ksql.sink.replicas=3\n          ksql.streams.replication.factor=3/g' ${DIR}/confluent-operator/helm/confluent-operator/charts/ksql/templates/ksql-psc.yaml



log "Extend Kubernetes with first class CP primitives"
kubectl apply --filename ${DIR}/confluent-operator/resources/crds/

log "Create the Kubernetes namespace to install Operator"
kubectl create namespace operator

log "installing operator"
helm upgrade --install \
  operator \
  ${DIR}/confluent-operator/helm/confluent-operator/ \
  --values $VALUES_FILE \
  --namespace operator \
  --set operator.enabled=true \
  --set global.sasl.plain.username="${CLOUD_KEY}" \
  --set global.sasl.plain.password="${CLOUD_SECRET}"

SR_USERNAME=$(echo $SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO | cut -d ":" -f 1)
SR_SECRET=$(echo $SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO | cut -d ":" -f 2)

log "Install connect"
helm upgrade --install \
  connectors \
    ${DIR}/confluent-operator/helm/confluent-operator/ \
  --values $VALUES_FILE \
  --namespace operator \
  --set connect.enabled=true \
  --set global.sasl.plain.username="${CLOUD_KEY}" \
  --set global.sasl.plain.password="${CLOUD_SECRET}" \
  --set connect.imagePullPolicy="IfNotPresent" \
  --set connect.image.repository="vdesabou/kafka-docker-playground-connect-operator" \
  --set connect.image.tag="${TAG}" \
  --set connect.dependencies.kafka.tls.enabled=true \
  --set connect.dependencies.kafka.tls.internal=true \
  --set connect.dependencies.kafka.tls.authentication.type="plain" \
  --set connect.dependencies.kafka.bootstrapEndpoint="${BOOTSTRAP_SERVERS}" \
  --set connect.dependencies.kafka.brokerCount=3 \
  --set connect.dependencies.schemaRegistry.url="${SCHEMA_REGISTRY_URL}" \
  --set connect.dependencies.schemaRegistry.authentication.type="basic" \
  --set connect.dependencies.schemaRegistry.authentication.source="USER_INFO" \
  --set connect.dependencies.schemaRegistry.authentication.username="${SR_USERNAME}" \
  --set connect.dependencies.schemaRegistry.authentication.password="${SR_SECRET}"

log "Install ksql"
helm upgrade --install \
  ksql \
    ${DIR}/confluent-operator/helm/confluent-operator/ \
  --values $VALUES_FILE \
  --namespace operator \
  --set ksql.enabled=true \
  --set global.sasl.plain.username="${CLOUD_KEY}" \
  --set global.sasl.plain.password="${CLOUD_SECRET}" \
  --set ksql.dependencies.kafka.tls.enabled=true \
  --set ksql.dependencies.kafka.tls.internal=true \
  --set ksql.dependencies.kafka.tls.authentication.type="plain" \
  --set ksql.dependencies.kafka.bootstrapEndpoint="${BOOTSTRAP_SERVERS}" \
  --set ksql.dependencies.kafka.brokerEndpoints="${BOOTSTRAP_SERVERS}" \
  --set ksql.dependencies.kafka.brokerCount=3 \
  --set ksql.dependencies.schemaRegistry.url="${SCHEMA_REGISTRY_URL}" \
  --set ksql.dependencies.schemaRegistry.authentication.type="basic" \
  --set ksql.dependencies.schemaRegistry.authentication.source="USER_INFO" \
  --set ksql.dependencies.schemaRegistry.authentication.username="${SR_USERNAME}" \
  --set ksql.dependencies.schemaRegistry.authentication.password="${SR_SECRET}"

log "Install control-center"
helm upgrade --install \
  controlcenter \
    ${DIR}/confluent-operator/helm/confluent-operator/ \
  --values $VALUES_FILE \
  --namespace operator \
  --set controlcenter.enabled=true \
  --set global.sasl.plain.username="${CLOUD_KEY}" \
  --set global.sasl.plain.password="${CLOUD_SECRET}" \
  --set controlcenter.dependencies.c3KafkaCluster.bootstrapEndpoint="${BOOTSTRAP_SERVERS}" \
  --set controlcenter.dependencies.c3KafkaCluster.brokerCount=3 \
  --set controlcenter.dependencies.c3KafkaCluster.tls.enabled=true \
  --set controlcenter.dependencies.c3KafkaCluster.tls.internal=true \
  --set controlcenter.dependencies.c3KafkaCluster.tls.authentication.type="plain" \
  --set controlcenter.dependencies.schemaRegistry.url="${SCHEMA_REGISTRY_URL}" \
  --set connect.dependencies.schemaRegistry.authentication.type="basic" \
  --set connect.dependencies.schemaRegistry.authentication.source="USER_INFO" \
  --set controlcenter.dependencies.schemaRegistry.authentication.username="${SR_USERNAME}" \
  --set controlcenter.dependencies.schemaRegistry.authentication.password="${SR_SECRET}"

# kubectl -n operator exec -it connectors-0 -- bash


log "Sleep 60 seconds to let pods being started"
sleep 60

set +e
# Verify Kafka Connect has started within MAX_WAIT seconds
MAX_WAIT=480
CUR_WAIT=0
log "Waiting up to $MAX_WAIT seconds for Kafka Connect connectors-0 to start"
kubectl logs -n operator connectors-0 > /tmp/out.txt 2>&1
while [[ ! $(cat /tmp/out.txt) =~ "Finished starting connectors and tasks" ]]; do
  sleep 10
  kubectl logs -n operator connectors-0 > /tmp/out.txt 2>&1
  CUR_WAIT=$(( CUR_WAIT+10 ))
  if [[ "$CUR_WAIT" -gt "$MAX_WAIT" ]]; then
    echo -e "\nERROR: The logs in connectors-0 container do not show 'Finished starting connectors and tasks' after $MAX_WAIT seconds. Please troubleshoot'.\n"
    exit 1
  fi
done
log "Connect connectors-0 has started!"
set -e

log "Control Center is reachable at http://127.0.0.1:9021 (admin/Developer1)"
kubectl -n operator port-forward controlcenter-0 9021:9021 &

#######
# CONNECTOR TEST: Spool dir
#######

set +e
log "Create topic spooldir-json-topic"
kubectl cp ${CONFIG_FILE} operator/connectors-0:/tmp/config
kubectl -n operator exec -it connectors-0 -- kafka-topics --bootstrap-server ${BOOTSTRAP_SERVERS} --command-config /tmp/config --topic spooldir-json-topic --create --replication-factor 3 --partitions 1
set +e

if [ ! -f "${DIR}/json-spooldir-source.json" ]
then
     log "Generating data"
     curl "https://api.mockaroo.com/api/17c84440?count=500&key=25fd9c80" > "${DIR}/json-spooldir-source.json"
fi

kubectl -n operator exec -it connectors-0 -- mkdir -p /tmp/data/input
kubectl -n operator exec -it connectors-0 -- mkdir -p /tmp/data/error
kubectl -n operator exec -it connectors-0 -- mkdir -p /tmp/data/finished

kubectl cp json-spooldir-source.json operator/connectors-0:/tmp/data/input/

log "Creating JSON Spool Dir Source connector"
kubectl -n operator exec -i connectors-0 -- curl -X PUT \
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
kubectl -n operator exec -it connectors-0 -- kafka-avro-console-consumer --topic spooldir-json-topic --bootstrap-server $BOOTSTRAP_SERVERS --consumer-property ssl.endpoint.identification.algorithm=https --consumer-property sasl.mechanism=PLAIN --consumer-property security.protocol=SASL_SSL --consumer-property sasl.jaas.config="$SASL_JAAS_CONFIG" --property basic.auth.credentials.source=$BASIC_AUTH_CREDENTIALS_SOURCE --property schema.registry.basic.auth.user.info="$SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO" --property schema.registry.url=$SCHEMA_REGISTRY_URL --from-beginning --max-messages 2

#######
# MONITORING
#######
log "Create the Kubernetes namespace monitoring to install prometheus/grafana"
kubectl create namespace monitoring

log "Install Prometheus"
helm install prometheus stable/prometheus \
 --set alertmanager.persistentVolume.enabled=false \
 --set server.persistentVolume.enabled=false \
 --namespace monitoring

log "Install Grafana"
helm install grafana stable/grafana --namespace monitoring

sleep 90

log "Open Grafana in your Browser"
export POD_NAME=$(kubectl get pods --namespace monitoring -l "app.kubernetes.io/name=grafana,app.kubernetes.io/instance=grafana" -o jsonpath="{.items[0].metadata.name}")
kubectl --namespace monitoring port-forward $POD_NAME 3000 &

password=$(kubectl get secret --namespace monitoring grafana -o jsonpath="{.data.admin-password}" | base64 --decode)

log "Visit http://localhost:3000 in your browser, and login with admin/$password."
open "http://127.0.0.1:3000"


log "Add Prometheus data source with url http://prometheus-server.monitoring.svc.cluster.local"
log "Then you can import dashboard with id 1860 for node exporter full, and ./confluent-operator/grafana-dashboard/grafana-dashboard.json"
