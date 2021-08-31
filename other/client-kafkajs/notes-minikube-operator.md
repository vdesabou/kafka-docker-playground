# Testing with Minikube and Operator


```bash
minikube start --cpus=8 --disk-size='50gb' --memory=16384
minikube dashboard &
```

Create the Kubernetes namespaces to install Operator and cluster

```bash
kubectl create namespace confluent
kubectl config set-context --current --namespace=confluent
```

```bash
mkdir confluent-operator
cd confluent-operator
wget https://platform-ops-bin.s3-us-west-1.amazonaws.com/operator/confluent-operator-1.7.0.tar.gz
tar xvfz confluent-operator-1.7.0.tar.gz
cd -
```

```bash
kubectl apply --filename confluent-operator/resources/crds/
```

```bash
VALUES_FILE="confluent-platform-operator.yaml"

helm upgrade --install \
  operator \
  confluent-operator/helm/confluent-operator/ \
  --values $VALUES_FILE \
  --namespace confluent \
  --set operator.enabled=true

helm upgrade --install \
  zookeeper \
  confluent-operator/helm/confluent-operator/ \
  --values $VALUES_FILE \
  --namespace confluent \
  --set zookeeper.enabled=true

helm upgrade --install \
  kafka \
  confluent-operator/helm/confluent-operator/ \
  --values $VALUES_FILE \
  --namespace confluent \
  --set kafka.enabled=true \
  --set kafka.replicas=3 \
  --set kafka.metricReporter.enabled=true \
  --set kafka.metricReporter.bootstrapEndpoint="kafka:9071" \
  --set kafka.oneReplicaPerNode=false

helm upgrade --install \
  controlcenter \
    confluent-operator/helm/confluent-operator/ \
  --values $VALUES_FILE \
  --namespace confluent \
  --set controlcenter.enabled=true
```

Waiting up to 900 seconds for all pods in namespace confluent to start

Control Center is reachable at http://127.0.0.1:9021

```bash
kubectl -n confluent port-forward controlcenter-0 9021:9021 &
```

```bash
eval $(minikube docker-env)
docker build -t vdesabou/kafkajs-operator-example-docker . -f ./Dockerfile-minikube-operator
```

```bash
kubectl cp kafka.properties confluent/kafka-0:/tmp/config
kubectl exec -it kafka-0 -- kafka-topics --bootstrap-server kafka:9071 --command-config /tmp/config --topic kafkajs --create --partitions 8 --replication-factor 3
```

```bash
kubectl apply -f pod-operator.yml
```

Roll the cluster

```bash
kubectl get statefulset --namespace confluent
kubectl rollout restart statefulset/kafka --namespace confluent
```
