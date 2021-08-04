# Testing with Minikube and Bitnami

https://docs.bitnami.com/tutorials/deploy-scalable-kafka-zookeeper-cluster-kubernetes/

```bash
minikube start --cpus=8 --disk-size='50gb' --memory=16384
minikube dashboard &
```

```bash
helm repo add bitnami https://charts.bitnami.com/bitnami
```

```
helm install zookeeper bitnami/zookeeper \
  --set replicaCount=3 \
  --set auth.enabled=false \
  --set allowAnonymousLogin=true
```

```
helm install kafka bitnami/kafka \
  --set zookeeper.enabled=false \
  --set replicaCount=3 \
  --set externalZookeeper.servers=zookeeper.default.svc.cluster.local
```

```
eval $(minikube docker-env)
docker build -t vdesabou/kafkajs-bitnami-example-docker . -f ./Dockerfile-minikube
```

```
kubectl apply -f pod.yml
```

Update a config (numPartitions) to have a rolling restart
```
helm upgrade kafka bitnami/kafka \
  --set zookeeper.enabled=false \
  --set replicaCount=3 \
  --set numPartitions=5 \
  --set externalZookeeper.servers=zookeeper.default.svc.cluster.local
```