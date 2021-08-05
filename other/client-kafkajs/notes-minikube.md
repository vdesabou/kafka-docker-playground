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
helm upgrade zookeeper bitnami/zookeeper \
  --set replicaCount=3 \
  --set auth.enabled=false \
  --set allowAnonymousLogin=true
```

```
helm upgrade kafka bitnami/kafka \
  --set zookeeper.enabled=false \
  --set replicaCount=4 \
  --set defaultReplicationFactor=3 \
  --set deleteTopicEnable=true \
  --set numPartitions=8 \
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
  --set replicaCount=4 \
  --set defaultReplicationFactor=3 \
  --set numPartitions=10 \
  --set externalZookeeper.servers=zookeeper.default.svc.cluster.local
```

kafka-topics.sh --bootstrap-server kafka-0.kafka-headless.default.svc.cluster.local:9092  --topic kafkajs --describe
kafka-topics.sh --bootstrap-server kafka-0.kafka-headless.default.svc.cluster.local:9092  --topic kafkajs --delete

kafka-console-consumer.sh \
            --bootstrap-server kafka-1.kafka-headless.default.svc.cluster.local:9092 \
            --topic kafkajs --partition 4 --max-messages 2\
            --from-beginning