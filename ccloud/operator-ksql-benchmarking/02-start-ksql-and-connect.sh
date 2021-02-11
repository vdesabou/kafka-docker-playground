#!/bin/bash

set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

# read configuration files
#
if [ -r ${DIR}/test.properties ]
then
    . ${DIR}/test.properties
else
    logerror "Cannot read configuration file ${DIR}/test.properties"
    exit 1
fi

if [ -r ${DIR}/ccloud-cluster.properties ]
then
    . ${DIR}/ccloud-cluster.properties
else
    logerror "Cannot read configuration file ${APP_HOME}/ccloud-cluster.properties"
    exit 1
fi

verify_installed "kubectl"
verify_installed "minikube"
verify_installed "helm"

# TODO change file based on k8s cluster
# Use most basic values file and override it with --set
VALUES_FILE="${DIR}/../../operator/private.yaml"

log "Download Confluent Operator in ${DIR}/confluent-operator"

rm -rf ${DIR}/confluent-operator
mkdir ${DIR}/confluent-operator
cd ${DIR}/confluent-operator
wget https://platform-ops-bin.s3-us-west-1.amazonaws.com/operator/confluent-operator-1.6.1-for-confluent-platform-6.0.0.tar.gz
tar xvfz confluent-operator-1.6.1-for-confluent-platform-6.0.0.tar.gz
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
sed -i.bak 's/^\(.*          retry.backoff.ms=500\)/\1\n          ksql.internal.topic.replicas=3\n          ksql.internal.topic.replicas=3\n          ksql.sink.replicas=3\n          ksql.streams.replication.factor=3          {{- if eq .Values.dependencies.schemaRegistry.authentication.type "basic"}}\n          ksql.schema_registry_url={{ .Values.dependencies.schemaRegistry.url }}\n          ksql.schema.registry.basic.auth.credentials.source={{ .Values.dependencies.schemaRegistry.authentication.source }}\n          ksql.schema.registry.basic.auth.user.info={{ $.Values.dependencies.schemaRegistry.authentication.username }}:{{ $.Values.dependencies.schemaRegistry.authentication.password }}\n          {{- end }}\n/g' ${DIR}/confluent-operator/helm/confluent-operator/charts/ksql/templates/ksql-psc.yaml


# FIXTHIS: we need to do custom modifications in order to be able to controlcenter controlcenter to Confluent Cloud Schema Registry:
# see https://github.com/abraham-leal/cc-components-operator/commit/50f1a21391b267a7b008b844ee4754ce1cfbcf04
sed -i.bak 's/^\(.*confluent.monitoring.interceptor.topic.replication=.*\)//g' ${DIR}/confluent-operator/helm/confluent-operator/charts/controlcenter/templates/controlcenter-psc.yaml
sed -i.bak 's/^\(.*confluent.metrics.topic.replication=.*\)//g' ${DIR}/confluent-operator/helm/confluent-operator/charts/controlcenter/templates/controlcenter-psc.yaml
sed -i.bak 's/^\(.*confluent.controlcenter.command.topic.replication=.*\)//g' ${DIR}/confluent-operator/helm/confluent-operator/charts/controlcenter/templates/controlcenter-psc.yaml
sed -i.bak 's/^\(.*confluent.controlcenter.internal.topics.replication=.*\)//g' ${DIR}/confluent-operator/helm/confluent-operator/charts/controlcenter/templates/controlcenter-psc.yaml
sed -i.bak 's/^\(.*          confluent.controlcenter.schema_registry_url={{ .Values.dependencies.schemaRegistry.url }}\)/\1\n          {{- if eq .Values.dependencies.schemaRegistry.authentication.type "basic"}}\n          confluent.controlcenter.schema.registry.basic.auth.credentials.source={{ .Values.dependencies.schemaRegistry.authentication.source }}\n          confluent.controlcenter.schema.registry.basic.auth.user.info={{ $.Values.dependencies.schemaRegistry.authentication.username }}:{{ $.Values.dependencies.schemaRegistry.authentication.password }}\n          {{- end }}\n/g' ${DIR}/confluent-operator/helm/confluent-operator/charts/controlcenter/templates/controlcenter-psc.yaml
sed -i.bak 's/^\(.*confluent.controlcenter.schema_registry_url=.*\)//g' ${DIR}/confluent-operator/helm/confluent-operator/charts/controlcenter/templates/controlcenter-psc.yaml
sed -i.bak 's/^\(.*          confluent.controlcenter.schema.registry.enable=true\)/\1\n          confluent.controlcenter.schema_registry_url={{ .Values.dependencies.schemaRegistry.url }}\n/g' ${DIR}/confluent-operator/helm/confluent-operator/charts/controlcenter/templates/controlcenter-psc.yaml
sed -i.bak 's/^\(.*          confluent.monitoring.interceptor.topic.skip.backlog.minutes=15\)/\1\n          confluent.monitoring.interceptor.topic.replication=3\n          confluent.metrics.topic.replication=3\n          confluent.controlcenter.command.topic.replication=3\n          confluent.controlcenter.internal.topics.replication=3\n/g' ${DIR}/confluent-operator/helm/confluent-operator/charts/controlcenter/templates/controlcenter-psc.yaml


log "Extend Kubernetes with first class CP primitives"
kubectl apply --filename ${DIR}/confluent-operator/resources/crds/

log "Create the Kubernetes namespaces to install Operator and cluster"
kubectl create namespace confluent
kubectl config set-context --current --namespace=confluent

log "installing operator"
helm upgrade --install \
  operator \
  ${DIR}/confluent-operator/helm/confluent-operator/ \
  --values $VALUES_FILE \
  --namespace confluent \
  --set operator.enabled=true \
  --set global.sasl.plain.username="${cluster_api_key}" \
  --set global.sasl.plain.password="${cluster_api_secret}"

log "Install connect"
helm upgrade --install \
  connectors \
    ${DIR}/confluent-operator/helm/confluent-operator/ \
  --values $VALUES_FILE \
  --namespace confluent \
  --set connect.enabled=true \
  --set global.sasl.plain.username="${cluster_api_key}" \
  --set global.sasl.plain.password="${cluster_api_secret}" \
  --set connect.imagePullPolicy="IfNotPresent" \
  --set connect.image.repository="vdesabou/kafka-docker-playground-connect-operator" \
  --set connect.image.tag="${TAG}" \
  --set connect.dependencies.kafka.tls.enabled=true \
  --set connect.dependencies.kafka.tls.internal=true \
  --set connect.dependencies.kafka.tls.authentication.type="plain" \
  --set connect.dependencies.kafka.bootstrapEndpoint="${bootstrap_servers}" \
  --set connect.dependencies.kafka.brokerCount=3 \
  --set connect.value.converter="io.confluent.connect.avro.AvroConverter" \
  --set connect.dependencies.schemaRegistry.url="${schema_registry_url}" \
  --set connect.dependencies.schemaRegistry.authentication.type="basic" \
  --set connect.dependencies.schemaRegistry.authentication.source="USER_INFO" \
  --set connect.dependencies.schemaRegistry.authentication.username="${schema_registry_api_key}" \
  --set connect.dependencies.schemaRegistry.authentication.password="${schema_registry_api_secret}"

log "Install ksql"
helm upgrade --install \
  ksql \
    ${DIR}/confluent-operator/helm/confluent-operator/ \
  --values $VALUES_FILE \
  --namespace confluent \
  --set ksql.enabled=true \
  --set global.sasl.plain.username="${cluster_api_key}" \
  --set global.sasl.plain.password="${cluster_api_secret}" \
  --set ksql.dependencies.kafka.tls.enabled=true \
  --set ksql.dependencies.kafka.tls.internal=true \
  --set ksql.dependencies.kafka.tls.authentication.type="plain" \
  --set ksql.dependencies.kafka.bootstrapEndpoint="${bootstrap_servers}" \
  --set ksql.dependencies.kafka.brokerEndpoints="${bootstrap_servers}" \
  --set ksql.dependencies.kafka.brokerCount=3 \
  --set ksql.dependencies.schemaRegistry.url="${schema_registry_url}" \
  --set ksql.dependencies.schemaRegistry.authentication.type="basic" \
  --set ksql.dependencies.schemaRegistry.authentication.source="USER_INFO" \
  --set ksql.dependencies.schemaRegistry.authentication.username="${schema_registry_api_key}" \
  --set ksql.dependencies.schemaRegistry.authentication.password="${schema_registry_api_secret}"

# FIXTHIS not required during real testing
log "Install control-center"
helm upgrade --install \
  controlcenter \
    ${DIR}/confluent-operator/helm/confluent-operator/ \
  --values $VALUES_FILE \
  --namespace confluent \
  --set controlcenter.enabled=true \
  --set global.sasl.plain.username="${cluster_api_key}" \
  --set global.sasl.plain.password="${cluster_api_secret}" \
  --set controlcenter.dependencies.c3KafkaCluster.bootstrapEndpoint="${bootstrap_servers}" \
  --set controlcenter.dependencies.c3KafkaCluster.brokerCount=3 \
  --set controlcenter.dependencies.c3KafkaCluster.tls.enabled=true \
  --set controlcenter.dependencies.c3KafkaCluster.tls.internal=true \
  --set controlcenter.dependencies.c3KafkaCluster.tls.authentication.type="plain" \
  --set controlcenter.dependencies.schemaRegistry.url="${schema_registry_url}" \
  --set controlcenter.dependencies.schemaRegistry.authentication.type="basic" \
  --set controlcenter.dependencies.schemaRegistry.authentication.source="USER_INFO" \
  --set controlcenter.dependencies.schemaRegistry.authentication.username="${schema_registry_api_key}" \
  --set controlcenter.dependencies.schemaRegistry.authentication.password="${schema_registry_api_secret}"

# kubectl exec -it connectors-0 -- bash


log "Waiting up to 1800 seconds for all pods in namespace confluent to start"
wait-until-pods-ready "1800" "10" "confluent"

set +e
# Verify Kafka Connect has started within MAX_WAIT seconds
MAX_WAIT=480
CUR_WAIT=0
log "Waiting up to $MAX_WAIT seconds for Kafka Connect connectors-0 to start"
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
open "http://127.0.0.1:3000" &


log "Add Prometheus data source with url http://prometheus-server.monitoring.svc.cluster.local"
log "Then you can import dashboard with id 1860 for node exporter full, and ./confluent-operator/grafana-dashboard/grafana-dashboard.json"
