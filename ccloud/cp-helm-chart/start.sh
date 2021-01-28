#!/bin/bash

set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

verify_memory
verify_installed "kubectl"
verify_installed "minikube"
verify_installed "helm"

# FIXTHIS: helm 3 is not supported;
# brew install helm@2
# export PATH="/usr/local/opt/helm@2/bin:$PATH" >> ~/.bash_profile
# helm init --stable-repo-url=https://charts.helm.sh/stable --client-only
# helm repo add stable https://charts.helm.sh/stable
# helm repo update

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
minikube dashboard &

#helm repo add stable https://charts.helm.sh/stable
#helm repo update
helm repo add confluentinc https://confluentinc.github.io/cp-helm-charts/

helm install demo -f values.yaml --set cp-schema-registry.enabled=false,cp-kafka-rest.enabled=false,cp-ksql-server.enabled=false confluentinc/cp-helm-charts

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