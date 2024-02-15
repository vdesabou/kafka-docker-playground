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
verify_installed "helm"

########
# MAKE SURE TO BE IDEMPOTENT
########
set +e
# delete namespaces
kubectl delete namespace confluent
# https://github.com/kubernetes/kubernetes/issues/77086#issuecomment-486840718
# kubectl delete namespace confluent --wait=false
# kubectl get ns confluent -o json | jq '.spec.finalizers=[]' > ns-without-finalizers.json
# curl -X PUT http://localhost:8001/api/v1/namespaces/confluent/finalize -H "Content-Type: application/json" --data-binary @ns-without-finalizers.json
kubectl delete namespace monitoring
kubectl delete namespace operator

# delete internal connect config to start from fresh state
CONFIG_FILE=${DIR}/client.properties
cat << EOF > ${CONFIG_FILE}
bootstrap.servers=${bootstrap_servers}
sasl.jaas.config=org.apache.kafka.common.security.plain.PlainLoginModule required username='${cluster_api_key}' password='${cluster_api_secret}';
schema.registry.url=${schema_registry_url}
basic.auth.credentials.source=USER_INFO
basic.auth.user.info=${schema_registry_api_key}:${schema_registry_api_secret}
security.protocol=SASL_SSL
sasl.mechanism=PLAIN
EOF
if [[ "$OSTYPE" == "darwin"* ]]
then
    # workaround for issue on linux, see https://github.com/vdesabou/kafka-docker-playground/issues/851#issuecomment-821151962
    chmod -R a+rw .
else
    # workaround for issue on linux, see https://github.com/vdesabou/kafka-docker-playground/issues/851#issuecomment-821151962
    sudo chmod -R a+rw .
fi
log "Delete internal connect topics"
docker run --rm -v $PWD:/tmp ${CP_CONNECT_IMAGE}:${CONNECT_TAG} kafka-topics --bootstrap-server ${bootstrap_servers} --command-config /tmp/client.properties --topic confluent.connectors-configs --delete > /dev/null 2>&1
docker run --rm -v $PWD:/tmp ${CP_CONNECT_IMAGE}:${CONNECT_TAG} kafka-topics --bootstrap-server ${bootstrap_servers} --command-config /tmp/client.properties --topic confluent.connectors-offsets --delete > /dev/null 2>&1
docker run --rm -v $PWD:/tmp ${CP_CONNECT_IMAGE}:${CONNECT_TAG} kafka-topics --bootstrap-server ${bootstrap_servers} --command-config /tmp/client.properties --topic confluent.connectors-status --delete > /dev/null 2>&1
set -e

VALUES_FILE=${DIR}/providers/${provider}.yaml

log "Download Confluent Operator in ${DIR}/confluent-operator"
rm -rf ${DIR}/confluent-operator
mkdir ${DIR}/confluent-operator
cd ${DIR}/confluent-operator
wget -q https://platform-ops-bin.s3-us-west-1.amazonaws.com/operator/confluent-operator-1.7.0.tar.gz
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
sed -i.bak 's/^\(.*          retry.backoff.ms=500\)/\1\n          ksql.internal.topic.replicas=3\n          ksql.internal.topic.replicas=3\n          ksql.sink.replicas=3\n          num.stream.threads=16\n          compression.type=lz4\n          ksql.streams.replication.factor=3\n          {{- if eq .Values.dependencies.schemaRegistry.authentication.type "basic"}}\n          ksql.schema.registry.url={{ .Values.dependencies.schemaRegistry.url }}\n          ksql.schema.registry.basic.auth.credentials.source={{ .Values.dependencies.schemaRegistry.authentication.source }}\n          ksql.schema.registry.basic.auth.user.info={{ $.Values.dependencies.schemaRegistry.authentication.username }}:{{ $.Values.dependencies.schemaRegistry.authentication.password }}\n          {{- end }}\n/g' ${DIR}/confluent-operator/helm/confluent-operator/charts/ksql/templates/ksql-psc.yaml


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

log "Create the Kubernetes namespaces to install Operator and cluster"
kubectl create namespace operator
kubectl create namespace confluent

log "installing operator"
helm upgrade --install \
  operator \
  ${DIR}/confluent-operator/helm/confluent-operator/ \
  --values $VALUES_FILE \
  --namespace operator \
  --set operator.enabled=true \
  --set global.provider.region="${eks_region}" \
  --set global.sasl.plain.username="${cluster_api_key}" \
  --set global.sasl.plain.password="${cluster_api_secret}"

kubectl config set-context --current --namespace=confluent

log "Install connect"
helm upgrade --install \
  connectors \
    ${DIR}/confluent-operator/helm/confluent-operator/ \
  --values $VALUES_FILE \
  --namespace confluent \
  --set connect.enabled=true \
  --set connect.replicas=1 \
  --set global.provider.region="${eks_region}" \
  --set global.sasl.plain.username="${cluster_api_key}" \
  --set global.sasl.plain.password="${cluster_api_secret}" \
  --set connect.imagePullPolicy="IfNotPresent" \
  --set connect.image.repository="${CP_CONNECT_IMAGE}-operator" \
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
  --set ksql.replicas=${ksql_replicas} \
  --set ksql.resources.requests.cpu="${ksql_cpu}" \
  --set ksql.resources.requests.memory="${ksql_memory}" \
  --set ksql.jvmConfig.heapSize="${ksql_jvm_memory}" \
  --set ksql.volume.data="30Gi" \
  --set global.provider.region="${eks_region}" \
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

log "Install control-center"
helm upgrade --install \
  controlcenter \
    ${DIR}/confluent-operator/helm/confluent-operator/ \
  --values $VALUES_FILE \
  --namespace confluent \
  --set controlcenter.enabled=true \
  --set global.provider.region="${eks_region}" \
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
# MONITORING
#######
log "Adding env label to pod (required for dashboards)"
kubectl label pod connectors-0 env=dev
kubectl label pod ksql-0 env=dev

log "Create the Kubernetes namespace monitoring to install prometheus/grafana"
kubectl create namespace monitoring

log "Store custom dashboards in configmap"
kubectl create -f grafana-dashboard-default.yaml -n monitoring
kubectl create -f grafana-dashboard-producer.yaml -n monitoring
kubectl create -f grafana-dashboard-consumer.yaml -n monitoring

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
