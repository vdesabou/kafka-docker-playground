# Testing with Minikube and Bitnami

https://docs.bitnami.com/tutorials/deploy-scalable-kafka-zookeeper-cluster-kubernetes/

## Setup

```bash
minikube start --cpus=8 --disk-size='50gb' --memory=16384
minikube dashboard &
```

```bash
helm repo add bitnami https://charts.bitnami.com/bitnami
```

```bash
helm install zookeeper bitnami/zookeeper \
  --set replicaCount=3 \
  --set auth.enabled=false \
  --set allowAnonymousLogin=true
```

```bash
helm install kafka bitnami/kafka \
  --set zookeeper.enabled=false \
  --set replicaCount=3 \
  --set defaultReplicationFactor=3 \
  --set deleteTopicEnable=true \
  --set numPartitions=8 \
  --set externalZookeeper.servers=zookeeper.default.svc.cluster.local
```

```bash
kubectl exec -it kafka-0 -- kafka-topics.sh --bootstrap-server kafka-0:9092 --topic kafkajs --create --partitions 8 --replication-factor 3
```

```bash
eval $(minikube docker-env)
docker build -t vdesabou/kafkajs-bitnami-example-docker . -f ./Dockerfile-minikube-bitnami
```

```bash
kubectl apply -f pod-bitnami.yml
```

Roll the cluster

```bash
kubectl get statefulset
kubectl rollout restart statefulset/kafka
```

Update a config (for example default numPartitions) to have a rolling restart:

```bash
helm upgrade kafka bitnami/kafka \
  --set zookeeper.enabled=false \
  --set replicaCount=3 \
  --set defaultReplicationFactor=3 \
  --set numPartitions=10 \
  --set externalZookeeper.servers=zookeeper.default.svc.cluster.local
```

To run commands on a pod:

```bash
kubectl run kafka-client --restart='Never' --image docker.io/bitnami/kafka:2.8.0-debian-10-r61 --namespace default --command -- sleep infinity
kubectl exec --tty -i kafka-client --namespace default -- bash


kafka-topics.sh --bootstrap-server kafka-0.kafka-headless.default.svc.cluster.local:9092  --topic kafkajs --describe
kafka-topics.sh --bootstrap-server kafka-0.kafka-headless.default.svc.cluster.local:9092  --topic kafkajs --delete
kafka-console-consumer.sh \
            --bootstrap-server kafka-1.kafka-headless.default.svc.cluster.local:9092 \
            --topic kafkajs --partition 4 --max-messages 2\
            --from-beginning
```

or

```bash
kubectl exec -it kafka-0 -- kafka-topics.sh --bootstrap-server kafka-0:9092 --topic kafkajs --delete
kubectl exec -it kafka-0 -- kafka-topics.sh --bootstrap-server kafka-0:9092 --topic kafkajs --describe
```

## Results

Bitnami kafka does not seem to do correct cluster rolls (waiting for URP for example), as I can see during roll:

```bash
$ kubectl exec -it kafka-0 -- kafka-topics.sh --bootstrap-server kafka-0:9092 --topic kafkajs --describe
Topic: kafkajs  TopicId: a9lB9-g7TX2r4nNTPpWhXg PartitionCount: 8       ReplicationFactor: 3    Configs: flush.ms=1000,segment.bytes=1073741824,flush.messages=10000,max.message.bytes=1000012,retention.bytes=1073741824
        Topic: kafkajs  Partition: 0    Leader: none    Replicas: 2,0,1 Isr: 0
        Topic: kafkajs  Partition: 1    Leader: none    Replicas: 1,2,0 Isr: 0
        Topic: kafkajs  Partition: 2    Leader: none    Replicas: 0,1,2 Isr: 0
        Topic: kafkajs  Partition: 3    Leader: none    Replicas: 2,1,0 Isr: 0
        Topic: kafkajs  Partition: 4    Leader: none    Replicas: 1,0,2 Isr: 0
        Topic: kafkajs  Partition: 5    Leader: none    Replicas: 0,2,1 Isr: 0
        Topic: kafkajs  Partition: 6    Leader: none    Replicas: 2,0,1 Isr: 0
        Topic: kafkajs  Partition: 7    Leader: none    Replicas: 1,2,0 Isr: 0
```

After all brokers are rolled, kafka-0 is leader for all partitions:

```bash
$ kubectl exec -it kafka-0 -- kafka-topics.sh --bootstrap-server kafka-0:9092 --topic kafkajs --describe
Topic: kafkajs  TopicId: a9lB9-g7TX2r4nNTPpWhXg PartitionCount: 8       ReplicationFactor: 3    Configs: flush.ms=1000,segment.bytes=1073741824,flush.messages=10000,max.message.bytes=1000012,retention.bytes=1073741824
        Topic: kafkajs  Partition: 0    Leader: 0       Replicas: 2,0,1 Isr: 0,2,1
        Topic: kafkajs  Partition: 1    Leader: 0       Replicas: 1,2,0 Isr: 0,2,1
        Topic: kafkajs  Partition: 2    Leader: 0       Replicas: 0,1,2 Isr: 0,2,1
        Topic: kafkajs  Partition: 3    Leader: 0       Replicas: 2,1,0 Isr: 0,2,1
        Topic: kafkajs  Partition: 4    Leader: 0       Replicas: 1,0,2 Isr: 0,2,1
        Topic: kafkajs  Partition: 5    Leader: 0       Replicas: 0,2,1 Isr: 0,2,1
        Topic: kafkajs  Partition: 6    Leader: 0       Replicas: 2,0,1 Isr: 0,2,1
        Topic: kafkajs  Partition: 7    Leader: 0       Replicas: 1,2,0 Isr: 0,2,1
```

After some time, automatic rebalance is done:

```bash
$ kubectl exec -it kafka-0 -- kafka-topics.sh --bootstrap-server kafka-0:9092 --topic kafkajs --describe
Topic: kafkajs  TopicId: a9lB9-g7TX2r4nNTPpWhXg PartitionCount: 8       ReplicationFactor: 3    Configs: flush.ms=1000,segment.bytes=1073741824,flush.messages=10000,max.message.bytes=1000012,retention.bytes=1073741824
        Topic: kafkajs  Partition: 0    Leader: 2       Replicas: 2,0,1 Isr: 0,2,1
        Topic: kafkajs  Partition: 1    Leader: 1       Replicas: 1,2,0 Isr: 0,2,1
        Topic: kafkajs  Partition: 2    Leader: 0       Replicas: 0,1,2 Isr: 0,2,1
        Topic: kafkajs  Partition: 3    Leader: 2       Replicas: 2,1,0 Isr: 0,2,1
        Topic: kafkajs  Partition: 4    Leader: 1       Replicas: 1,0,2 Isr: 0,2,1
        Topic: kafkajs  Partition: 5    Leader: 0       Replicas: 0,2,1 Isr: 0,2,1
        Topic: kafkajs  Partition: 6    Leader: 2       Replicas: 2,0,1 Isr: 0,2,1
        Topic: kafkajs  Partition: 7    Leader: 1       Replicas: 1,2,0 Isr: 0,2,1
```