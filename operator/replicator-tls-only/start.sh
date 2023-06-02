#!/bin/bash

set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

verify_docker_and_memory
verify_installed "kubectl"
verify_installed "minikube"
verify_installed "helm"

if [ -z "$CI" ]
then
   # not running with github actions
  set +e
  log "Stop minikube if required"
  minikube delete
  set -e
  log "Start minikube"
  minikube start --cpus=8 --disk-size='50gb' --memory=16384
  log "Launch minikube dashboard in background"
  minikube dashboard &
fi

log "Download Confluent Operator in ${DIR}/confluent-operator"

rm -rf ${DIR}/confluent-operator
mkdir ${DIR}/confluent-operator
cd ${DIR}/confluent-operator
wget https://platform-ops-bin.s3-us-west-1.amazonaws.com/operator/confluent-operator-1.7.0.tar.gz
tar xvfz confluent-operator-1.7.0.tar.gz
cd -


log "Extend Kubernetes with first class CP primitives"
kubectl apply --filename ${DIR}/confluent-operator/resources/crds/

log "Create the Kubernetes namespaces to install Operator and clusters"

kubectl create namespace confluent
kubectl create namespace kafka-dest
kubectl create namespace kafka-src

log "Generating certificates"
openssl genrsa -out rootCA.key 2048
openssl req -x509  -new -nodes \
-key rootCA.key \
-days 3650 \
-out rootCA.pem \
-subj "/C=US/ST=CA/L=MVT/O=TestOrg/OU=Cloud/CN=TestCA"
openssl genrsa -out server.key 2048

openssl req -new -key server.key \
 -out server.csr \
 -subj "/C=US/ST=CA/L=MVT/O=TestOrg/OU=Cloud/CN=*.svc.cluster.local"

openssl x509 -req \
 -in server.csr \
 -extensions server_ext \
 -CA rootCA.pem \
 -CAkey rootCA.key \
 -CAcreateserial \
 -out server.crt \
 -days 365 \
 -extfile \
 <(echo "[server_ext]"; echo "extendedKeyUsage=serverAuth,clientAuth"; echo "subjectAltName=DNS:*.svc.cluster.local,DNS:kafka-0.kafka.kafka-dest.svc.cluster.local,DNS:kafka-0.kafka.kafka-src.svc.cluster.local")

# Use most basic values file and override it with --set
VALUES_FILE="${DIR}/../../operator/private.yaml"

log "installing operator"
helm upgrade --install \
  operator \
  ${DIR}/confluent-operator/helm/confluent-operator/ \
  --values $VALUES_FILE \
  --namespace confluent \
  --set operator.enabled=true

log "install kafka-dest cluster"
helm upgrade --install \
  zookeeper \
  ${DIR}/confluent-operator/helm/confluent-operator/ \
  --values $VALUES_FILE \
  --namespace kafka-dest \
  --set zookeeper.enabled=true

helm upgrade --install \
  kafka \
  ${DIR}/confluent-operator/helm/confluent-operator/ \
  --values $VALUES_FILE \
  --namespace kafka-dest \
  --set kafka.enabled=true \
  --set kafka.tls.enabled=true \
  --set-file kafka.tls.fullchain=${PWD}/server.crt \
  --set-file kafka.tls.privkey=${PWD}/server.key \
  --set-file kafka.tls.cacerts=${PWD}/rootCA.pem \
  --set 'kafka.configOverrides.server[0]=confluent.license.topic.replication.factor=1' \
  --set 'kafka.configOverrides.server[1]=confluent.balancer.enable=true' \
  --set 'kafka.configOverrides.server[2]=confluent.balancer.heal.uneven.load.trigger=ANY_UNEVEN_LOAD'


  # --set 'kafka.configOverrides.server[1]=listener.name.internal.ssl.principal.mapping.rules=RULE:^CN=([a-zA-Z0-9.]*).*$//L,DEFAULT' \
  # --set 'kafka.configOverrides.server[2]=listener.name.replication.ssl.principal.mapping.rules=RULE:^CN=([a-zA-Z0-9.]*).*$//L,DEFAULT'

# helm upgrade --install \
#   schemaregistry \
#     ${DIR}/confluent-operator/helm/confluent-operator/ \
#   --values $VALUES_FILE \
#   --namespace kafka-dest \
#   --set schemaregistry.enabled=true

helm upgrade --install \
  replicator \
    ${DIR}/confluent-operator/helm/confluent-operator/ \
  --values $VALUES_FILE \
  --namespace kafka-dest \
  --set replicator.enabled=true \
  --set replicator.tls.enabled=true \
  --set-file replicator.tls.fullchain=${PWD}/server.crt \
  --set-file replicator.tls.privkey=${PWD}/server.key \
  --set-file replicator.tls.cacerts=${PWD}/rootCA.pem \
  --set replicator.dependencies.kafka.tls.enabled=true \
  --set replicator.dependencies.kafka.brokerCount=1

helm upgrade --install \
  controlcenter \
    ${DIR}/confluent-operator/helm/confluent-operator/ \
  --values $VALUES_FILE \
  --namespace kafka-dest \
  --set controlcenter.enabled=true \
  --set-file controlcenter.tls.fullchain=${PWD}/server.crt \
  --set-file controlcenter.tls.privkey=${PWD}/server.key \
  --set-file controlcenter.tls.cacerts=${PWD}/rootCA.pem \
  --set controlcenter.dependencies.c3KafkaCluster.tls.enabled=true

log "install kafka-src cluster"
helm upgrade --install \
  zookeeper \
  ${DIR}/confluent-operator/helm/confluent-operator/ \
  --values $VALUES_FILE \
  --namespace kafka-src \
  --set zookeeper.enabled=true

helm upgrade --install \
  kafka \
  ${DIR}/confluent-operator/helm/confluent-operator/ \
  --values $VALUES_FILE \
  --namespace kafka-src \
  --set kafka.enabled=true \
  --set kafka.enabled=true \
  --set kafka.tls.enabled=true \
  --set-file kafka.tls.fullchain=${PWD}/server.crt \
  --set-file kafka.tls.privkey=${PWD}/server.key \
  --set-file kafka.tls.cacerts=${PWD}/rootCA.pem \
  --set kafka.configOverrides.server[0]='confluent.license.topic.replication.factor=1'

# helm upgrade --install \
#   schemaregistry \
#     ${DIR}/confluent-operator/helm/confluent-operator/ \
#   --values $VALUES_FILE \
#   --namespace kafka-src \
#   --set schemaregistry.enabled=true

# kubectl -n kafka-dest exec -it replicator-0 -- bash


log "Sleep 60 seconds to let pods being started"
sleep 60

set +e
# Verify Kafka Connect has started within MAX_WAIT seconds
MAX_WAIT=600
CUR_WAIT=0
log "⌛ Waiting up to $MAX_WAIT seconds for Kafka Connect replicator-0 to start"
kubectl logs -n kafka-dest replicator-0 > /tmp/out.txt 2>&1
while [[ ! $(cat /tmp/out.txt) =~ "Finished starting connectors and tasks" ]]; do
  sleep 10
  kubectl logs -n kafka-dest replicator-0 > /tmp/out.txt 2>&1
  CUR_WAIT=$(( CUR_WAIT+10 ))
  if [[ "$CUR_WAIT" -gt "$MAX_WAIT" ]]; then
    echo -e "\nERROR: The logs in replicator-0 container do not show 'Finished starting connectors and tasks' after $MAX_WAIT seconds. Please troubleshoot'.\n"
    kubectl logs -n kafka-dest replicator-0
    exit 1
  fi
done
log "Connect replicator-0 has started!"
set -e

log "⌛ Waiting up to 900 seconds for all pods in namespace kafka-dest to start"
wait-until-pods-ready "900" "10" "kafka-dest"
log "⌛ Waiting up to 900 seconds for all pods in namespace kafka-src to start"
wait-until-pods-ready "900" "10" "kafka-src"

log "Control Center is reachable at http://127.0.0.1:9021 (admin/Developer1)"
kubectl -n kafka-dest port-forward controlcenter-0 9021:9021 &

log "create a topic example on kafka-src cluster"
kubectl -n kafka-src exec -i kafka-0 -- bash -c 'kafka-topics --create --topic example --partitions 1 --replication-factor 1 --bootstrap-server kafka:9071'

# Create a secret called "onprem-trustore-jks":

# $ kubectl -n <namespace<> create secret generic onprem-trustore-jks --from-file=onprem-trustore-jks=/path/to/onprem/truststore.jks

# In $VALUES_FILE, add for connect or replicator components:
#  mountedSecrets:
#  - secretRef: onprem-trustore-jks
# This will mount the truststore into /mnt/secrets/onprem-trustore-jks/onprem-trustore-jks
# Replicator config can then be set to:
# "src.kafka.ssl.truststore.location": "/mnt/secrets/onprem-trustore-jks/onprem-trustore-jks"


log "create replicator"
kubectl -n kafka-dest exec -i replicator-0 -- curl -k -X PUT \
     -H "Content-Type: application/json" \
     --data '{
            "connector.class": "io.confluent.connect.replicator.ReplicatorSourceConnector",
            "tasks.max": "1",
            "topic.whitelist": "example",
            "topic.rename.format": "\${topic}_replica",
            "key.converter": "io.confluent.connect.replicator.util.ByteArrayConverter",
            "value.converter": "io.confluent.connect.replicator.util.ByteArrayConverter",
            "src.kafka.bootstrap.servers": "kafka-0.kafka.kafka-src.svc.cluster.local:9092",
            "src.kafka.security.protocol": "SSL",
            "src.kafka.ssl.truststore.location": "/tmp/truststore.jks",
            "src.kafka.ssl.truststore.password": "mystorepassword",
            "dest.kafka.bootstrap.servers": "kafka-0.kafka.kafka-dest.svc.cluster.local:9092",
            "dest.kafka.security.protocol": "SSL",
            "dest.kafka.ssl.truststore.location": "/tmp/truststore.jks",
            "dest.kafka.ssl.truststore.password": "mystorepassword",
            "confluent.license": "",
            "confluent.topic.replication.factor": "1",
            "confluent.topic.bootstrap.servers": "kafka-0.kafka.kafka-dest.svc.cluster.local:9092",
            "confluent.topic.security.protocol": "SSL",
            "confluent.topic.ssl.truststore.location": "/tmp/truststore.jks",
            "confluent.topic.ssl.truststore.password": "mystorepassword"
          }' \
     https://localhost:8083/connectors/test-replicator/config | jq

log "produce data on topic example on kafka-src cluster"
kubectl -n kafka-src exec -i kafka-0 -- bash -c 'seq 10 | kafka-console-producer --broker-list kafka:9071 --topic example'

sleep 5

log "check data on topic example_replica on kafka-dest cluster"
playground topic consume --topic example_replica --min-expected-messages 10 --timeout 60

#######
# MONITORING
#######
log "Adding env label to pod (required for dashboards)"
kubectl -n kafka-dest label pod replicator-0 env=dev

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
