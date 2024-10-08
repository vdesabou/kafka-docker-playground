#!/bin/bash

set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

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

set +e
helm repo remove confluentinc
log "Add the Confluent for Kubernetes Helm repository"
helm repo add confluentinc https://packages.confluent.io/helm
helm repo update
set -e

log "Install Confluent for Kubernetes"
helm upgrade --install confluent-operator confluentinc/confluent-for-kubernetes --set debug="true"

log "Deploy OpenLdap"
helm upgrade --install -f ${DIR}/openldap/ldaps-rbac.yaml test-ldap ${DIR}/openldap --namespace confluent

sleep 90

log "Validate that OpenLDAP is running"
kubectl exec -it ldap-0 -- ldapsearch -LLL -x -H ldap://ldap.confluent.svc.cluster.local:389 -b 'dc=test,dc=com' -D "cn=mds,dc=test,dc=com" -w 'Developer!'

log "Create a Kubernetes secret object for Zookeeper, Kafka, and Control Center"
kubectl create secret generic credential \
 --from-file=plain-users.json=$DIR/creds-kafka-sasl-users.json \
 --from-file=digest-users.json=$DIR/creds-zookeeper-sasl-digest-users.json \
 --from-file=digest.txt=$DIR/creds-kafka-zookeeper-credentials.txt \
 --from-file=plain.txt=$DIR/creds-client-kafka-sasl-user.txt \
 --from-file=basic.txt=$DIR/creds-control-center-users.txt \
 --from-file=ldap.txt=$DIR/ldap.txt

log "Create a Kubernetes secret for inter-component TLS"
cp $DIR/ca.pem.txt $DIR/ca.pem
cp $DIR/ca-key.pem.txt $DIR/ca-key.pem
kubectl create secret tls ca-pair-sslcerts \
  --cert=$DIR/ca.pem \
  --key=$DIR/ca-key.pem

log "Create a Kubernetes secret object for MDS"
kubectl create secret generic mds-token \
  --from-file=mdsPublicKey.pem=$DIR/mds-publickey.txt \
  --from-file=mdsTokenKeyPair.pem=$DIR/mds-tokenkeypair.txt

# Kafka RBAC credential
kubectl create secret generic mds-client \
  --from-file=bearer.txt=$DIR/bearer.txt
# Control Center RBAC credential
kubectl create secret generic c3-mds-client \
  --from-file=bearer.txt=$DIR/c3-mds-client.txt
# Connect RBAC credential
kubectl create secret generic connect-mds-client \
  --from-file=bearer.txt=$DIR/connect-mds-client.txt
# Schema Registry RBAC credential
kubectl create secret generic sr-mds-client \
  --from-file=bearer.txt=$DIR/sr-mds-client.txt
# ksqlDB RBAC credential
kubectl create secret generic ksqldb-mds-client \
  --from-file=bearer.txt=$DIR/ksqldb-mds-client.txt
# Kafka REST credential
kubectl create secret generic rest-credential \
  --from-file=bearer.txt=$DIR/bearer.txt \
  --from-file=basic.txt=$DIR/bearer.txt

log "Install cluster"
kubectl apply -f "${DIR}/confluent-platform-production-autogeneratedcerts.yaml"

log "⌛ Waiting up to 900 seconds for all pods in namespace confluent to start"
wait-until-pods-ready "900" "10" "confluent"

kubectl get pods

log "Create RBAC Rolebindings for Control Center admin"
kubectl apply -f $DIR/controlcenter-testadmin-rolebindings.yaml

log "Control Center is reachable at http://127.0.0.1:9021"
kubectl -n confluent port-forward controlcenter-0 9021:9021 &

log "Control Center is reachable at https://127.0.0.1:9021 (testadmin/testadmin)"
# helm pull confluentinc_earlyaccess/confluent-for-kubernetes --untar --untardir=.

# Check for any error messages in events
# kubectl get events -n confluent

log "Create a topic"
kubectl apply -f topic.yaml