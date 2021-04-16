#!/bin/bash

set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

USER=${USER:-$1}
EMAIL=${EMAIL:-$2}
APIKEY=${APIKEY:-$3}

if [ -z "$USER" ]
then
     logerror "USER is not set. Export it as environment variable or pass it as argument"
     exit 1
fi

if [ -z "$EMAIL" ]
then
     logerror "EMAIL is not set. Export it as environment variable or pass it as argument"
     exit 1
fi

if [ -z "$APIKEY" ]
then
     logerror "APIKEY is not set. Export it as environment variable or pass it as argument"
     exit 1
fi


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

verify_docker_and_memory
verify_installed "kubectl"
verify_installed "minikube"
verify_installed "helm"

set +e
log "Stop minikube if required"
minikube delete
set -e
log "Start minikube"
minikube start --cpus=8 --disk-size='50gb' --memory=16384
log "Launch minikube dashboard in background"
minikube dashboard &

log "Create the Kubernetes namespaces to install Operator and cluster"
kubectl create namespace confluent
kubectl config set-context --current --namespace=confluent

log "Setup Operator Early Access credentials."
kubectl create secret docker-registry confluent-registry \
  --docker-server=confluent-docker-internal-early-access-operator-2.jfrog.io \
  --docker-username=$USER \
        --docker-password=$APIKEY \
        --docker-email=$EMAIL

set +e
helm repo remove confluentinc_earlyaccess
log "Add repo confluentinc_earlyaccess"
helm repo add confluentinc_earlyaccess \
  https://confluent.jfrog.io/confluent/helm-early-access-operator-2 \
  --username $USER \
  --password $APIKEY
helm repo update
set -e

log "installing operator"
helm upgrade --install operator confluentinc_earlyaccess/confluent-operator \
  --set image.registry=confluent-docker-internal-early-access-operator-2.jfrog.io

log "Generate a CA pair"
# workaround for issue on linux, see https://github.com/vdesabou/kafka-docker-playground/issues/851#issuecomment-821151962
chmod -R a+w .
docker run --rm -v $PWD:/tmp vdesabou/kafka-docker-playground-connect:${CONNECT_TAG} openssl genrsa -out /tmp/ca-key.pem 2048
docker run --rm -v $PWD:/tmp vdesabou/kafka-docker-playground-connect:${CONNECT_TAG} openssl req -new -key /tmp/ca-key.pem -x509 \
  -days 1000 \
  -out /tmp/ca.pem \
  -subj "/C=US/ST=CA/L=MountainView/O=Confluent/OU=Operator/CN=TestCA"

log "Create a Kuebernetes secret for inter-component TLS"
kubectl create secret tls ca-pair-sslcerts \
  --cert=${DIR}/ca.pem \
  --key=${DIR}/ca-key.pem

log "Provide authentication credentials"

# generate creds-client-kafka-sasl-user.txt config
sed -e "s|:CLOUD_KEY:|$CLOUD_KEY|g" \
    -e "s|:CLOUD_SECRET:|$CLOUD_SECRET|g" \
    ${DIR}/creds-client-kafka-sasl-user-template.txt > ${DIR}/creds-client-kafka-sasl-user.txt
SR_USERNAME=$(echo $SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO | cut -d ":" -f 1)
SR_SECRET=$(echo $SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO | cut -d ":" -f 2)
# generate creds-schemaRegistry-user.txt config
sed -e "s|:SR_USERNAME:|$SR_USERNAME|g" \
    -e "s|:SR_SECRET:|$SR_SECRET|g" \
    ${DIR}/creds-schemaRegistry-user-template.txt > ${DIR}/creds-schemaRegistry-user.txt

kubectl create secret generic cloud-plain \
--from-file=plain.txt=${PWD}/creds-client-kafka-sasl-user.txt
kubectl create secret generic cloud-sr-access \
--from-file=basic.txt=${PWD}/creds-schemaRegistry-user.txt
kubectl create secret generic control-center-user \
--from-file=basic.txt=${PWD}/creds-control-center-users.txt

# generate confluent-platform-template.yaml config
sed -e "s|BOOTSTRAP_SERVERS|$BOOTSTRAP_SERVERS|g" \
    -e "s|SCHEMA_REGISTRY_URL|$SCHEMA_REGISTRY_URL|g" \
    ${DIR}/confluent-platform-template.yaml > ${DIR}/confluent-platform.yaml

log "install cluster"
kubectl apply -f "${DIR}/confluent-platform.yaml"

log "Waiting up to 900 seconds for all pods in namespace confluent to start"
wait-until-pods-ready "900" "10" "confluent"

kubectl get confluent