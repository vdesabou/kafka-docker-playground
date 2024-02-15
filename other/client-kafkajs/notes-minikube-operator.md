# Testing with Minikube and Operator

## Setup

If you want to use minkube:

```bash
minikube start --cpus=8 --disk-size='50gb' --memory=16384
minikube dashboard &
```

If you want to use AWS EKS:

```bash
# Start EKS cluster with t2.2xlarge instances
eksctl create cluster --name kafka-docker-playground-client-kafkajs \
    --version 1.18 \
    --nodegroup-name standard-workers \
    --node-type t2.2xlarge \
    --region eu-west-3 \
    --nodes-min 4 \
    --nodes-max 10 \
    --node-volume-size 500 \
    --node-ami auto

# Configure your computer to communicate with your cluster
aws eks update-kubeconfig \
    --region eu-west-3 \
    --name kafka-docker-playground-client-kafkajs

# Deploy the Metrics Server
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

# Deploy the Kubernetes dashboard
kubectl apply -f https://raw.githubusercontent.com/kubernetes/dashboard/v2.0.5/aio/deploy/recommended.yaml

kubectl apply -f ../../ccloud/operator-ksql-benchmarking/eks-admin-service-account.yaml

# Get the token from the output below to connect to dashboard
kubectl -n kube-system describe secret $(kubectl -n kube-system get secret | grep eks-admin | awk '{print $1}')

kubectl proxy &
```

If you want to use Kubernetes dashboard, run `kubectl proxy` and then login to http://localhost:8001/api/v1/namespaces/kubernetes-dashboard/services/https:kubernetes-dashboard:/proxy/#/login




Create the Kubernetes namespaces to install Operator and cluster

```bash
kubectl create namespace confluent
kubectl config set-context --current --namespace=confluent
```

```bash
mkdir confluent-operator
cd confluent-operator
wget -q https://platform-ops-bin.s3-us-west-1.amazonaws.com/operator/confluent-operator-1.7.0.tar.gz
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

# if using EKS, you can set kafka.replicas=32 for example
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

If using Minikube:

```bash
eval $(minikube docker-env)
docker build -t vdesabou/kafkajs-operator-example-docker . -f ./Dockerfile-minikube-operator
```

If using EKS:

```bash
docker build -t vdesabou/kafkajs-operator-example-docker . -f ./Dockerfile-minikube-operator
docker push vdesabou/kafkajs-operator-example-docker
```

```bash
kubectl cp kafka.properties confluent/kafka-0:/tmp/config
kubectl exec -it kafka-0 -- kafka-topics --bootstrap-server kafka:9071 --command-config /tmp/config --topic kafkajs --create --partitions 216 --replication-factor 3
```

If using Minikube:

```bash
kubectl apply -f pod-operator.yml
```

If using EKS:

```bash
kubectl apply -f deployment-pod-operator.yml

# then you can scale the number of pods using:
kubectl scale --replicas=50 deployment.apps/deploy-kafkajs
```

Roll the cluster

```bash
kubectl get statefulset --namespace confluent
kubectl rollout restart statefulset/kafka --namespace confluent
```

## Results

`kafka-2`is stopped first, we get a couple of `This server is not the leader for that topic-partition` errors:

```logs
[[09:04:01.637]] [ERROR] {"level":"ERROR","timestamp":"2021-08-31T09:04:01.633Z","logger":"kafkajs","message":"[Connection] Response Produce(key: 0, version: 7)","broker":"kafka-2.kafka.confluent.svc.cluster.local:9071","clientId":"my-kafkajs-producer","error":"This server is not the leader for that topic-partition","correlationId":118,"size":55}
[[09:04:01.638]] [LOG]   {"level":"DEBUG","timestamp":"2021-08-31T09:04:01.638Z","logger":"kafkajs","message":"[Connection] Response Produce(key: 0, version: 7)","broker":"kafka-2.kafka.confluent.svc.cluster.local:9071","clientId":"my-kafkajs-producer","error":"This server is not the leader for that topic-partition","correlationId":118,"payload":{"type":"Buffer","data":"[filtered]"}}
[[09:04:01.639]] [ERROR] {"level":"ERROR","timestamp":"2021-08-31T09:04:01.639Z","logger":"kafkajs","message":"[Producer] Failed to send messages: This server is not the leader for that topic-partition","retryCount":0,"retryTime":262}
```

Immediately followed by a request metadata where response has *offlineReplicas* set with `kafka-2`:

```bash
[[09:04:01.639]] [LOG]   {"level":"DEBUG","timestamp":"2021-08-31T09:04:01.639Z","logger":"kafkajs","message":"[Connection] Request Metadata(key: 3, version: 6)","broker":"kafka-0.kafka.confluent.svc.cluster.local:9071","clientId":"my-kafkajs-producer","correlationId":81,"expectResponse":true,"size":47}
[[09:04:01.641]] [LOG]   {"level":"DEBUG","timestamp":"2021-08-31T09:04:01.641Z","logger":"kafkajs","message":"[Connection] Response Metadata(key: 3, version: 6)","broker":"kafka-0.kafka.confluent.svc.cluster.local:9071","clientId":"my-kafkajs-producer","correlationId":81,"size":590,"data":{"throttleTime":0,"brokers":[{"nodeId":0,"host":"kafka-0.kafka.confluent.svc.cluster.local","port":9071,"rack":"0"},{"nodeId":2,"host":"kafka-2.kafka.confluent.svc.cluster.local","port":9071,"rack":"0"},{"nodeId":1,"host":"kafka-1.kafka.confluent.svc.cluster.local","port":9071,"rack":"0"}],"clusterId":"tPVmA6k0TCmamXlHFJOhHA","controllerId":2,"topicMetadata":[{"topicErrorCode":0,"topic":"kafkajs","isInternal":false,"partitionMetadata":[{"partitionErrorCode":0,"partitionId":0,"leader":1,"replicas":[1,2,0],"isr":[1,2,0],"offlineReplicas":[]},{"partitionErrorCode":0,"partitionId":5,"leader":0,"replicas":[0,2,1],"isr":[0,2,1],"offlineReplicas":[]},{"partitionErrorCode":0,"partitionId":4,"leader":1,"replicas":[2,1,0],"isr":[1,0],"offlineReplicas":[2]},{"partitionErrorCode":0,"partitionId":1,"leader":0,"replicas":[2,0,1],"isr":[0,1],"offlineReplicas":[2]},{"partitionErrorCode":0,"partitionId":6,"leader":1,"replicas":[1,2,0],"isr":[1,2,0],"offlineReplicas":[]},{"partitionErrorCode":0,"partitionId":7,"leader":0,"replicas":[2,0,1],"isr":[0,1],"offlineReplicas":[2]},{"partitionErrorCode":0,"partitionId":2,"leader":0,"replicas":[0,1,2],"isr":[0,1,2],"offlineReplicas":[]},{"partitionErrorCode":0,"partitionId":3,"leader":1,"replicas":[1,0,2],"isr":[1,0,2],"offlineReplicas":[]}]}],"clientSideThrottleTime":0}}
```
