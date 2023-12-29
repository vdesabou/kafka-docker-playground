#!/bin/bash

set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

verify_installed "kubectl"
verify_installed "helm"

bootstrap_ccloud_environment

if [ -f ${DIR}/../../.ccloud/env.delta ]
then
     source ${DIR}/../../.ccloud/env.delta
else
     logerror "ERROR: ${DIR}/../../.ccloud/env.delta has not been generated"
     exit 1
fi

# Use most basic values file and override it with --set
VALUES_FILE="${DIR}/../../operator/private.yaml"

if [ -z "$GITHUB_RUN_NUMBER" ]
then
   # not running with github actions
  verify_installed "minikube"
  set +e
  log "Stop minikube if required"
  minikube delete
  set -e
  log "Start minikube"
  minikube start --cpus=8 --disk-size='50gb' --memory=16384
  log "Launch minikube dashboard in background"
  minikube dashboard &
else
  verify_installed "eksctl"
  tag=$(echo "$TAG" | sed -e 's/\.//g')
  eksctl create cluster --name kafka-docker-playground-ci-$tag \
      --version 1.18 \
      --node-type t2.2xlarge \
      --region eu-west-3 \
      --nodes 2 \
      --node-ami auto

  log "Configure your computer to communicate with your cluster"
  aws eks update-kubeconfig \
      --region eu-west-3 \
      --name kafka-docker-playground-ci-$tag
fi

log "Download Confluent Operator in ${DIR}/confluent-operator"

rm -rf ${DIR}/confluent-operator
mkdir ${DIR}/confluent-operator
cd ${DIR}/confluent-operator
wget https://platform-ops-bin.s3-us-west-1.amazonaws.com/operator/confluent-operator-1.7.0.tar.gz
tar xvfz confluent-operator-1.7.0.tar.gz
cd -

# FIXTHIS: we need to do custom modifications in order to be able to connect Connect to Confluent Cloud Schema Registry:
# see https://github.com/abraham-leal/cc-components-operator/commit/50f1a21391b267a7b008b844ee4754ce1cfbcf04
sed -i.bak 's/^\(.*confluent.topic.replication.factor=.*\)//g' ${DIR}/confluent-operator/helm/confluent-operator/charts/connect/templates/connect-psc.yaml
sed -i.bak 's/^\(.*offset.storage.replication.factor=.*\)//g' ${DIR}/confluent-operator/helm/confluent-operator/charts/connect/templates/connect-psc.yaml
sed -i.bak 's/^\(.*config.storage.replication.factor=.*\)//g' ${DIR}/confluent-operator/helm/confluent-operator/charts/connect/templates/connect-psc.yaml
sed -i.bak 's/^\(.*status.storage.replication.factor=.*\)//g' ${DIR}/confluent-operator/helm/confluent-operator/charts/connect/templates/connect-psc.yaml
sed -i.bak 's/^\(.*          retry.backoff.ms=500\)/\1\n          confluent.topic.replication.factor=3\n          offset.storage.replication.factor=3\n          config.storage.replication.factor=3\n          status.storage.replication.factor=3\n          # Start Addon for Schema Registry for CCloud\n          {{- if eq .Values.dependencies.schemaRegistry.authentication.type "basic"}}\n          key.converter.basic.auth.credentials.source={{ .Values.dependencies.schemaRegistry.authentication.source }}\n          key.converter.basic.auth.user.info={{ $.Values.dependencies.schemaRegistry.authentication.username }}:{{ $.Values.dependencies.schemaRegistry.authentication.password }}\n          value.converter.basic.auth.credentials.source={{ .Values.dependencies.schemaRegistry.authentication.source }}\n          value.converter.basic.auth.user.info={{ $.Values.dependencies.schemaRegistry.authentication.username }}:{{ $.Values.dependencies.schemaRegistry.authentication.password }}\n          # End Addon for Schema Registry for CCloud\n          {{- end }}/g' ${DIR}/confluent-operator/helm/confluent-operator/charts/connect/templates/connect-psc.yaml
# to speedup statup, only need datagen
sed -i.bak 's/^\(.*\/usr\/share\/confluent-hub-components\)/\1\/confluentinc-kafka-connect-datagen/g' ${DIR}/confluent-operator/helm/confluent-operator/charts/connect/templates/connect-psc.yaml


# FIXTHIS: we need to do custom modifications in order to be able to connect KSQL to Confluent Cloud:
# see https://github.com/abraham-leal/cc-components-operator/commit/50f1a21391b267a7b008b844ee4754ce1cfbcf04
sed -i.bak 's/^\(.*ksql.sink.replicas=.*\)//g' ${DIR}/confluent-operator/helm/confluent-operator/charts/ksql/templates/ksql-psc.yaml
sed -i.bak 's/^\(.*ksql.streams.replication.factor=.*\)//g' ${DIR}/confluent-operator/helm/confluent-operator/charts/ksql/templates/ksql-psc.yaml
sed -i.bak 's/^\(.*          retry.backoff.ms=500\)/\1\n          ksql.internal.topic.replicas=3\n          ksql.internal.topic.replicas=3\n          ksql.sink.replicas=3\n          compression.type=lz4\n          ksql.streams.replication.factor=3\n          {{- if eq .Values.dependencies.schemaRegistry.authentication.type "basic"}}\n          ksql.schema.registry.url={{ .Values.dependencies.schemaRegistry.url }}\n          ksql.schema.registry.basic.auth.credentials.source={{ .Values.dependencies.schemaRegistry.authentication.source }}\n          ksql.schema.registry.basic.auth.user.info={{ $.Values.dependencies.schemaRegistry.authentication.username }}:{{ $.Values.dependencies.schemaRegistry.authentication.password }}\n          {{- end }}\n/g' ${DIR}/confluent-operator/helm/confluent-operator/charts/ksql/templates/ksql-psc.yaml


# FIXTHIS: we need to do custom modifications in order to be able to controlcenter controlcenter to Confluent Cloud Schema Registry:
# see https://github.com/abraham-leal/cc-components-operator/commit/50f1a21391b267a7b008b844ee4754ce1cfbcf04
sed -i.bak 's/^\(.*confluent.monitoring.interceptor.topic.replication=.*\)//g' ${DIR}/confluent-operator/helm/confluent-operator/charts/controlcenter/templates/controlcenter-psc.yaml
sed -i.bak 's/^\(.*confluent.metrics.topic.replication=.*\)//g' ${DIR}/confluent-operator/helm/confluent-operator/charts/controlcenter/templates/controlcenter-psc.yaml
sed -i.bak 's/^\(.*confluent.controlcenter.command.topic.replication=.*\)//g' ${DIR}/confluent-operator/helm/confluent-operator/charts/controlcenter/templates/controlcenter-psc.yaml
sed -i.bak 's/^\(.*confluent.controlcenter.internal.topics.replication=.*\)//g' ${DIR}/confluent-operator/helm/confluent-operator/charts/controlcenter/templates/controlcenter-psc.yaml
sed -i.bak 's/^\(.*          confluent.controlcenter.schema.registry.url={{ .Values.dependencies.schemaRegistry.url }}\)/\1\n          {{- if eq .Values.dependencies.schemaRegistry.authentication.type "basic"}}\n          confluent.controlcenter.schema.registry.basic.auth.credentials.source={{ .Values.dependencies.schemaRegistry.authentication.source }}\n          confluent.controlcenter.schema.registry.basic.auth.user.info={{ $.Values.dependencies.schemaRegistry.authentication.username }}:{{ $.Values.dependencies.schemaRegistry.authentication.password }}\n          {{- end }}\n/g' ${DIR}/confluent-operator/helm/confluent-operator/charts/controlcenter/templates/controlcenter-psc.yaml
sed -i.bak 's/^\(.*confluent.controlcenter.schema.registry.url=.*\)//g' ${DIR}/confluent-operator/helm/confluent-operator/charts/controlcenter/templates/controlcenter-psc.yaml
sed -i.bak 's/^\(.*          confluent.controlcenter.schema.registry.enable=true\)/\1\n          confluent.controlcenter.schema.registry.url={{ .Values.dependencies.schemaRegistry.url }}\n/g' ${DIR}/confluent-operator/helm/confluent-operator/charts/controlcenter/templates/controlcenter-psc.yaml
sed -i.bak 's/^\(.*          confluent.monitoring.interceptor.topic.skip.backlog.minutes=15\)/\1\n          confluent.monitoring.interceptor.topic.replication=3\n          confluent.metrics.topic.replication=3\n          confluent.controlcenter.command.topic.replication=3\n          confluent.controlcenter.internal.topics.replication=3\n          confluent.metrics.topic.max.message.bytes=8388608\n/g' ${DIR}/confluent-operator/helm/confluent-operator/charts/controlcenter/templates/controlcenter-psc.yaml

log "Extend Kubernetes with first class CP primitives"
kubectl apply --filename ${DIR}/confluent-operator/resources/crds/

log "Create the Kubernetes namespace to install Operator"
kubectl create namespace operator
kubectl create namespace confluent

log "installing operator"
helm upgrade --install \
  operator \
  ${DIR}/confluent-operator/helm/confluent-operator/ \
  --values $VALUES_FILE \
  --namespace operator \
  --set operator.enabled=true \
  --set global.sasl.plain.username="${CLOUD_KEY}" \
  --set global.sasl.plain.password="${CLOUD_SECRET}"

kubectl config set-context --current --namespace=confluent

SR_USERNAME=$(echo $SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO | cut -d ":" -f 1)
SR_SECRET=$(echo $SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO | cut -d ":" -f 2)

log "Install connect"
helm upgrade --install \
  connectors \
    ${DIR}/confluent-operator/helm/confluent-operator/ \
  --values $VALUES_FILE \
  --namespace confluent \
  --set connect.enabled=true \
  --set global.sasl.plain.username="${CLOUD_KEY}" \
  --set global.sasl.plain.password="${CLOUD_SECRET}" \
  --set connect.imagePullPolicy="IfNotPresent" \
  --set connect.image.repository="${CP_CONNECT_IMAGE}-operator" \
  --set connect.image.tag="${TAG}" \
  --set connect.dependencies.kafka.tls.enabled=true \
  --set connect.dependencies.kafka.tls.internal=true \
  --set connect.dependencies.kafka.tls.authentication.type="plain" \
  --set connect.dependencies.kafka.bootstrapEndpoint="${BOOTSTRAP_SERVERS}" \
  --set connect.dependencies.kafka.brokerCount=3 \
  --set connect.value.converter="io.confluent.connect.avro.AvroConverter" \
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
  --namespace confluent \
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
  --namespace confluent \
  --set controlcenter.enabled=true \
  --set global.sasl.plain.username="${CLOUD_KEY}" \
  --set global.sasl.plain.password="${CLOUD_SECRET}" \
  --set controlcenter.dependencies.c3KafkaCluster.bootstrapEndpoint="${BOOTSTRAP_SERVERS}" \
  --set controlcenter.dependencies.c3KafkaCluster.brokerCount=3 \
  --set controlcenter.dependencies.c3KafkaCluster.tls.enabled=true \
  --set controlcenter.dependencies.c3KafkaCluster.tls.internal=true \
  --set controlcenter.dependencies.c3KafkaCluster.tls.authentication.type="plain" \
  --set controlcenter.dependencies.schemaRegistry.url="${SCHEMA_REGISTRY_URL}" \
  --set controlcenter.dependencies.schemaRegistry.authentication.type="basic" \
  --set controlcenter.dependencies.schemaRegistry.authentication.source="USER_INFO" \
  --set controlcenter.dependencies.schemaRegistry.authentication.username="${SR_USERNAME}" \
  --set controlcenter.dependencies.schemaRegistry.authentication.password="${SR_SECRET}"

# kubectl exec -i connectors-0 -- bash


log "⌛ Waiting up to 1800 seconds for all pods in namespace confluent to start"
wait-until-pods-ready "1800" "10" "confluent"

set +e
# Verify Kafka Connect has started within MAX_WAIT seconds
MAX_WAIT=480
CUR_WAIT=0
log "⌛ Waiting up to $MAX_WAIT seconds for Kafka Connect connectors-0 to start"
kubectl logs connectors-0 > /tmp/out.txt 2>&1
while [[ ! $(cat /tmp/out.txt) =~ "Finished starting connectors and tasks" ]]; do
  sleep 10
  kubectl logs connectors-0 > /tmp/out.txt 2>&1
  CUR_WAIT=$(( CUR_WAIT+10 ))
  if [[ "$CUR_WAIT" -gt "$MAX_WAIT" ]]; then
    echo -e "\nERROR: The logs in connectors-0 container do not show 'Finished starting connectors and tasks' after $MAX_WAIT seconds. Please troubleshoot'.\n"
    tail -300 /tmp/out.txt
    exit 1
  fi
done
log "Connect connectors-0 has started!"
set -e

log "Control Center is reachable at http://127.0.0.1:9021 (admin/Developer1)"
kubectl port-forward controlcenter-0 9021:9021 &

#######
# CONNECTOR TEST: Spool dir
#######

set +e
log "Create topic spooldir-json-topic"
kubectl cp ${CONFIG_FILE} confluent/connectors-0:/tmp/config
kubectl exec -i connectors-0 -- kafka-topics --bootstrap-server ${BOOTSTRAP_SERVERS} --command-config /tmp/config --topic spooldir-json-topic --create --replication-factor 3 --partitions 1
set +e

if [ ! -f "${DIR}/json-spooldir-source.json" ]
then
     log "Generating data"
     curl -k "https://api.mockaroo.com/api/17c84440?count=500&key=25fd9c80" > "${DIR}/json-spooldir-source.json"
fi

kubectl exec -i connectors-0 -- mkdir -p /tmp/data/input
kubectl exec -i connectors-0 -- mkdir -p /tmp/data/error
kubectl exec -i connectors-0 -- mkdir -p /tmp/data/finished

kubectl cp json-spooldir-source.json confluent/connectors-0:/tmp/data/input/

log "Creating JSON Spool Dir Source connector"
kubectl exec -i connectors-0 -- curl -X PUT \
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
                "schema.generation.enabled": "true"
          }' \
     http://localhost:8083/connectors/spool-dir-source$RANDOM/config | jq

sleep 5

log "Verify we have received the data in spooldir-json-topic topic"
playground topic consume --topic spooldir-json-topic --min-expected-messages 2 --timeout 60

#######
# MONITORING
#######
log "Create the Kubernetes namespace monitoring to install prometheus/grafana"
kubectl create namespace monitoring

log "Store custom dashboard in configmap"
kubectl create -f grafana-dashboard-configmap.yaml -n monitoring

log "Install Prometheus"
helm install prometheus stable/prometheus \
 --set alertmanager.persistentVolume.enabled=false \
 --set server.persistentVolume.enabled=false \
 --namespace monitoring

log "Install Grafana"
helm upgrade --install grafana stable/grafana \
    --set adminPassword="admin" \
    --set datasources."datasources\.yaml".apiVersion=1 \
    --set datasources."datasources\.yaml".datasources[0].name=Prometheus \
    --set datasources."datasources\.yaml".datasources[0].type=prometheus \
    --set datasources."datasources\.yaml".datasources[0].url=http://prometheus-server.monitoring.svc.cluster.local \
    --set datasources."datasources\.yaml".datasources[0].access=proxy \
    --set datasources."datasources\.yaml".datasources[0].isDefault=true \
    --set sidecar.dashboards.enabled=true \
    --set dashboardProviders."dashboardproviders\.yaml".apiVersion=1 \
    --set dashboardProviders."dashboardproviders\.yaml".providers[0].name=default \
    --set dashboardProviders."dashboardproviders\.yaml".providers[0].orgId=1 \
    --set dashboardProviders."dashboardproviders\.yaml".providers[0].folder="" \
    --set dashboardProviders."dashboardproviders\.yaml".providers[0].type=file \
    --set dashboardProviders."dashboardproviders\.yaml".providers[0].disableDeletion=false \
    --set dashboardProviders."dashboardproviders\.yaml".providers[0].editable=true \
    --set dashboardProviders."dashboardproviders\.yaml".providers[0].options.path=/var/lib/grafana/dashboards/default \
    --set dashboards.default.kubernetes-all-nodes.gnetId=3131 \
    --set dashboards.default.kubernetes-all-nodes.datasource=Prometheus \
    --set dashboards.default.kubernetes-pods.gnetId=3146 \
    --set dashboards.default.kubernetes-pods.datasource=Prometheus \
    --namespace monitoring

sleep 90

log "Open Grafana in your Browser"
export POD_NAME=$(kubectl get pods --namespace monitoring -l "app.kubernetes.io/name=grafana,app.kubernetes.io/instance=grafana" -o jsonpath="{.items[0].metadata.name}")
kubectl --namespace monitoring port-forward $POD_NAME 3000 &

log "Visit http://localhost:3000 in your browser, and login with admin/admin"
open "http://127.0.0.1:3000" &
