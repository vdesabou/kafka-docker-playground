# Testing with Minikube and CFK

## Setup

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

## Results

Initial metadata, for example `partitionId` 0 has leader 2:

```log
[[08:39:32.648]] [LOG]   {"level":"DEBUG","timestamp":"2021-08-30T08:39:32.648Z","logger":"kafkajs","message":"[Connection] Request Metadata(key: 3, version: 6)","broker":"kafka-0.kafka.confluent.svc.cluster.local:9071","clientId":"my-kafkajs-producer","correlationId":1,"expectResponse":true,"size":47}
[[08:39:32.651]] [LOG]   {"level":"DEBUG","timestamp":"2021-08-30T08:39:32.651Z","logger":"kafkajs","message":"[Connection] Response Metadata(key: 3, version: 6)","broker":"kafka-0.kafka.confluent.svc.cluster.local:9071","clientId":"my-kafkajs-producer","correlationId":1,"size":590,"data":{"throttleTime":0,"brokers":[{"nodeId":0,"host":"kafka-0.kafka.confluent.svc.cluster.local","port":9071,"rack":"0"},{"nodeId":2,"host":"kafka-2.kafka.confluent.svc.cluster.local","port":9071,"rack":"2"},{"nodeId":1,"host":"kafka-1.kafka.confluent.svc.cluster.local","port":9071,"rack":"1"}],"clusterId":"PWaURBD7Q5m_ZfaHONxGAA","controllerId":2,"topicMetadata":[{"topicErrorCode":0,"topic":"kafkajs","isInternal":false,"partitionMetadata":[{"partitionErrorCode":0,"partitionId":0,"leader":2,"replicas":[2,1,0],"isr":[2,1,0],"offlineReplicas":[]},{"partitionErrorCode":0,"partitionId":5,"leader":1,"replicas":[1,2,0],"isr":[1,2,0],"offlineReplicas":[]},{"partitionErrorCode":0,"partitionId":4,"leader":0,"replicas":[0,1,2],"isr":[0,1,2],"offlineReplicas":[]},{"partitionErrorCode":0,"partitionId":1,"leader":0,"replicas":[0,2,1],"isr":[0,2,1],"offlineReplicas":[]},{"partitionErrorCode":0,"partitionId":6,"leader":2,"replicas":[2,1,0],"isr":[2,1,0],"offlineReplicas":[]},{"partitionErrorCode":0,"partitionId":7,"leader":0,"replicas":[0,2,1],"isr":[0,2,1],"offlineReplicas":[]},{"partitionErrorCode":0,"partitionId":2,"leader":1,"replicas":[1,0,2],"isr":[1,0,2],"offlineReplicas":[]},{"partitionErrorCode":0,"partitionId":3,"leader":2,"replicas":[2,0,1],"isr":[2,0,1],"offlineReplicas":[]}]}],"clientSideThrottleTime":0}}
```

`kafka-2` is rolled with pod stopped at `08:41:03` (it is rescheduled at `08:41:47`):

```yaml
  lastTimestamp: "2021-08-30T08:41:03Z"
  message: delete Pod kafka-2 in StatefulSet kafka successful
```

At `08:41:33`, producer starts to get `ECONNRESET`:

```log
[[08:41:33.973]] [ERROR] {"level":"ERROR","timestamp":"2021-08-30T08:41:33.973Z","logger":"kafkajs","message":"[Connection] Connection error: read ECONNRESET","broker":"kafka-2.kafka.confluent.svc.cluster.local:9071","clientId":"my-kafkajs-producer","stack":"Error: read ECONNRESET\n    at TCP.onStreamRead (internal/stream_base_commons.js:209:20)"}
[[08:41:33.979]] [ERROR] {"level":"ERROR","timestamp":"2021-08-30T08:41:33.979Z","logger":"kafkajs","message":"[Producer] Failed to send messages: Connection error: read ECONNRESET","retryCount":0,"retryTime":275}
[[08:41:33.982]] [LOG]   {"level":"DEBUG","timestamp":"2021-08-30T08:41:33.981Z","logger":"kafkajs","message":"[Connection] Request Metadata(key: 3, version: 6)","broker":"kafka-1.kafka.confluent.svc.cluster.local:9071","clientId":"my-kafkajs-producer","correlationId":303,"expectResponse":true,"size":47}
[[08:41:33.987]] [LOG]   {"level":"DEBUG","timestamp":"2021-08-30T08:41:33.987Z","logger":"kafkajs","message":"[Connection] Response Metadata(key: 3, version: 6)","broker":"kafka-1.kafka.confluent.svc.cluster.local:9071","clientId":"my-kafkajs-producer","correlationId":303,"size":590,"data":{"throttleTime":0,"brokers":[{"nodeId":0,"host":"kafka-0.kafka.confluent.svc.cluster.local","port":9071,"rack":"0"},{"nodeId":2,"host":"kafka-2.kafka.confluent.svc.cluster.local","port":9071,"rack":"2"},{"nodeId":1,"host":"kafka-1.kafka.confluent.svc.cluster.local","port":9071,"rack":"1"}],"clusterId":"PWaURBD7Q5m_ZfaHONxGAA","controllerId":2,"topicMetadata":[{"topicErrorCode":0,"topic":"kafkajs","isInternal":false,"partitionMetadata":[{"partitionErrorCode":0,"partitionId":0,"leader":2,"replicas":[2,1,0],"isr":[2,1,0],"offlineReplicas":[]},{"partitionErrorCode":0,"partitionId":5,"leader":1,"replicas":[1,2,0],"isr":[1,2,0],"offlineReplicas":[]},{"partitionErrorCode":0,"partitionId":4,"leader":0,"replicas":[0,1,2],"isr":[0,1,2],"offlineReplicas":[]},{"partitionErrorCode":0,"partitionId":1,"leader":0,"replicas":[0,2,1],"isr":[0,2,1],"offlineReplicas":[]},{"partitionErrorCode":0,"partitionId":6,"leader":2,"replicas":[2,1,0],"isr":[2,1,0],"offlineReplicas":[]},{"partitionErrorCode":0,"partitionId":7,"leader":0,"replicas":[0,2,1],"isr":[0,2,1],"offlineReplicas":[]},{"partitionErrorCode":0,"partitionId":2,"leader":1,"replicas":[1,0,2],"isr":[1,0,2],"offlineReplicas":[]},{"partitionErrorCode":0,"partitionId":3,"leader":2,"replicas":[2,0,1],"isr":[2,0,1],"offlineReplicas":[]}]}],"clientSideThrottleTime":0}}
```

-> Request Metadata sent but kafka-2 is still leader

-> we get reconnection attempts:

```log
[[08:41:34.003]] [LOG]   {"level":"DEBUG","timestamp":"2021-08-30T08:41:34.003Z","logger":"kafkajs","message":"[Connection] Connecting","broker":"kafka-2.kafka.confluent.svc.cluster.local:9071","clientId":"my-kafkajs-producer","ssl":false,"sasl":false}
[[08:41:34.007]] [LOG]   {"level":"DEBUG","timestamp":"2021-08-30T08:41:34.007Z","logger":"kafkajs","message":"[Connection] disconnecting...","broker":"kafka-2.kafka.confluent.svc.cluster.local:9071","clientId":"my-kafkajs-producer"}
[[08:41:34.008]] [LOG]   {"level":"DEBUG","timestamp":"2021-08-30T08:41:34.008Z","logger":"kafkajs","message":"[Connection] disconnected","broker":"kafka-2.kafka.confluent.svc.cluster.local:9071","clientId":"my-kafkajs-producer"}
[[08:41:34.008]] [LOG]   {"level":"DEBUG","timestamp":"2021-08-30T08:41:34.008Z","logger":"kafkajs","message":"[Connection] disconnecting...","broker":"kafka-2.kafka.confluent.svc.cluster.local:9071","clientId":"my-kafkajs-producer"}
[[08:41:34.008]] [LOG]   {"level":"DEBUG","timestamp":"2021-08-30T08:41:34.008Z","logger":"kafkajs","message":"[Connection] disconnected","broker":"kafka-2.kafka.confluent.svc.cluster.local:9071","clientId":"my-kafkajs-producer"}
[[08:41:34.007]] [ERROR] {"level":"ERROR","timestamp":"2021-08-30T08:41:34.007Z","logger":"kafkajs","message":"[Connection] Connection error: connect ECONNREFUSED 172.17.0.8:9071","broker":"kafka-2.kafka.confluent.svc.cluster.local:9071","clientId":"my-kafkajs-producer","stack":"Error: connect ECONNREFUSED 172.17.0.8:9071\n    at TCPConnectWrap.afterConnect [as oncomplete] (net.js:1148:16)"}
```

With metadata request every time:

```log
[[08:41:34.008]] [LOG]   {"level":"DEBUG","timestamp":"2021-08-30T08:41:34.008Z","logger":"kafkajs","message":"[Connection] Request Metadata(key: 3, version: 6)","broker":"kafka-1.kafka.confluent.svc.cluster.local:9071","clientId":"my-kafkajs-producer","correlationId":304,"expectResponse":true,"size":47}
[[08:41:34.012]] [LOG]   {"level":"DEBUG","timestamp":"2021-08-30T08:41:34.011Z","logger":"kafkajs","message":"[Connection] Response Metadata(key: 3, version: 6)","broker":"kafka-1.kafka.confluent.svc.cluster.local:9071","clientId":"my-kafkajs-producer","correlationId":304,"size":590,"data":{"throttleTime":0,"brokers":[{"nodeId":0,"host":"kafka-0.kafka.confluent.svc.cluster.local","port":9071,"rack":"0"},{"nodeId":2,"host":"kafka-2.kafka.confluent.svc.cluster.local","port":9071,"rack":"2"},{"nodeId":1,"host":"kafka-1.kafka.confluent.svc.cluster.local","port":9071,"rack":"1"}],"clusterId":"PWaURBD7Q5m_ZfaHONxGAA","controllerId":2,"topicMetadata":[{"topicErrorCode":0,"topic":"kafkajs","isInternal":false,"partitionMetadata":[{"partitionErrorCode":0,"partitionId":0,"leader":2,"replicas":[2,1,0],"isr":[2,1,0],"offlineReplicas":[]},{"partitionErrorCode":0,"partitionId":5,"leader":1,"replicas":[1,2,0],"isr":[1,2,0],"offlineReplicas":[]},{"partitionErrorCode":0,"partitionId":4,"leader":0,"replicas":[0,1,2],"isr":[0,1,2],"offlineReplicas":[]},{"partitionErrorCode":0,"partitionId":1,"leader":0,"replicas":[0,2,1],"isr":[0,2,1],"offlineReplicas":[]},{"partitionErrorCode":0,"partitionId":6,"leader":2,"replicas":[2,1,0],"isr":[2,1,0],"offlineReplicas":[]},{"partitionErrorCode":0,"partitionId":7,"leader":0,"replicas":[0,2,1],"isr":[0,2,1],"offlineReplicas":[]},{"partitionErrorCode":0,"partitionId":2,"leader":1,"replicas":[1,0,2],"isr":[1,0,2],"offlineReplicas":[]},{"partitionErrorCode":0,"partitionId":3,"leader":2,"replicas":[2,0,1],"isr":[2,0,1],"offlineReplicas":[]}]}],"clientSideThrottleTime":0}}
```

But still same leader 2...

Etc..

```log
[[08:41:49.661]] [LOG]   {"level":"DEBUG","timestamp":"2021-08-30T08:41:49.661Z","logger":"kafkajs","message":"[Connection] Request Metadata(key: 3, version: 6)","broker":"kafka-1.kafka.confluent.svc.cluster.local:9071","clientId":"my-kafkajs-producer","correlationId":346,"expectResponse":true,"size":47}
[[08:41:49.664]] [LOG]   {"level":"DEBUG","timestamp":"2021-08-30T08:41:49.663Z","logger":"kafkajs","message":"[Connection] Response Metadata(key: 3, version: 6)","broker":"kafka-1.kafka.confluent.svc.cluster.local:9071","clientId":"my-kafkajs-producer","correlationId":346,"size":590,"data":{"throttleTime":0,"brokers":[{"nodeId":0,"host":"kafka-0.kafka.confluent.svc.cluster.local","port":9071,"rack":"0"},{"nodeId":2,"host":"kafka-2.kafka.confluent.svc.cluster.local","port":9071,"rack":"2"},{"nodeId":1,"host":"kafka-1.kafka.confluent.svc.cluster.local","port":9071,"rack":"1"}],"clusterId":"PWaURBD7Q5m_ZfaHONxGAA","controllerId":2,"topicMetadata":[{"topicErrorCode":0,"topic":"kafkajs","isInternal":false,"partitionMetadata":[{"partitionErrorCode":0,"partitionId":0,"leader":2,"replicas":[2,1,0],"isr":[2,1,0],"offlineReplicas":[]},{"partitionErrorCode":0,"partitionId":5,"leader":1,"replicas":[1,2,0],"isr":[1,2,0],"offlineReplicas":[]},{"partitionErrorCode":0,"partitionId":4,"leader":0,"replicas":[0,1,2],"isr":[0,1,2],"offlineReplicas":[]},{"partitionErrorCode":0,"partitionId":1,"leader":0,"replicas":[0,2,1],"isr":[0,2,1],"offlineReplicas":[]},{"partitionErrorCode":0,"partitionId":6,"leader":2,"replicas":[2,1,0],"isr":[2,1,0],"offlineReplicas":[]},{"partitionErrorCode":0,"partitionId":7,"leader":0,"replicas":[0,2,1],"isr":[0,2,1],"offlineReplicas":[]},{"partitionErrorCode":0,"partitionId":2,"leader":1,"replicas":[1,0,2],"isr":[1,0,2],"offlineReplicas":[]},{"partitionErrorCode":0,"partitionId":3,"leader":2,"replicas":[2,0,1],"isr":[2,0,1],"offlineReplicas":[]}]}],"clientSideThrottleTime":0}}
```

For partitionId 0, leader changed at `08:41:58` (this is due to PQFS-1364 and corresponds to the `zookeeper.session.timeout.ms` which is set to 22,5 seconds) and `kafka-2` is finally seen as offline replica:

```log
[[08:41:58.001]] [LOG]   {"level":"DEBUG","timestamp":"2021-08-30T08:41:58.000Z","logger":"kafkajs","message":"[Connection] Response Metadata(key: 3, version: 6)","broker":"kafka-0.kafka.confluent.svc.cluster.local:9071","clientId":"my-kafkajs-producer","correlationId":724,"size":536,"data":{"throttleTime":0,"brokers":[{"nodeId":0,"host":"kafka-0.kafka.confluent.svc.cluster.local","port":9071,"rack":"0"},{"nodeId":1,"host":"kafka-1.kafka.confluent.svc.cluster.local","port":9071,"rack":"1"}],"clusterId":"PWaURBD7Q5m_ZfaHONxGAA","controllerId":1,"topicMetadata":[{"topicErrorCode":0,"topic":"kafkajs","isInternal":false,"partitionMetadata":[{"partitionErrorCode":0,"partitionId":0,"leader":1,"replicas":[2,1,0],"isr":[1,0],"offlineReplicas":[2]},{"partitionErrorCode":0,"partitionId":5,"leader":1,"replicas":[1,2,0],"isr":[1,0],"offlineReplicas":[2]},{"partitionErrorCode":0,"partitionId":4,"leader":0,"replicas":[0,1,2],"isr":[0,1],"offlineReplicas":[2]},{"partitionErrorCode":0,"partitionId":1,"leader":0,"replicas":[0,2,1],"isr":[0,1],"offlineReplicas":[2]},{"partitionErrorCode":0,"partitionId":6,"leader":1,"replicas":[2,1,0],"isr":[1,0],"offlineReplicas":[2]},{"partitionErrorCode":0,"partitionId":7,"leader":0,"replicas":[0,2,1],"isr":[0,1],"offlineReplicas":[2]},{"partitionErrorCode":0,"partitionId":2,"leader":1,"replicas":[1,0,2],"isr":[1,0],"offlineReplicas":[2]},{"partitionErrorCode":0,"partitionId":3,"leader":0,"replicas":[2,0,1],"isr":[0,1],"offlineReplicas":[2]}]}],"clientSideThrottleTime":0}}
```