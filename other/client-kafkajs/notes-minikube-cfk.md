# Testing with Minikube and CFK


```bash
minikube start --cpus=8 --disk-size='50gb' --memory=16384
minikube dashboard &
```

Create the Kubernetes namespaces to install Operator and cluster

```bash
kubectl create namespace confluent
kubectl config set-context --current --namespace=confluent
```


Add the Confluent for Kubernetes Helm repository

```bash
helm repo add confluentinc https://packages.confluent.io/helm
helm repo update
```

Install Confluent for Kubernetes

```bash
helm upgrade --install confluent-operator confluentinc/confluent-for-kubernetes
```

Install cluster

```bash
kubectl apply -f confluent-platform.yaml
```

Waiting up to 900 seconds for all pods in namespace confluent to start

Control Center is reachable at http://127.0.0.1:9021

```bash
kubectl -n confluent port-forward controlcenter-0 9021:9021 &
```

Create a topic

```bash
kubectl apply -f create-kafkajs-topic.yaml
```

```bash
eval $(minikube docker-env)
docker build -t vdesabou/kafkajs-cfk-example-docker . -f ./Dockerfile-minikube-cfk
```

```bash
kubectl apply -f pod-cfk.yml
```

Roll the cluster

```bash
kubectl get statefulset --namespace confluent
kubectl rollout restart statefulset/kafka --namespace confluent
```

