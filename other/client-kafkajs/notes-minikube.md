# Testing with Minikube and Bitnami

https://docs.bitnami.com/tutorials/deploy-scalable-kafka-zookeeper-cluster-kubernetes/

```bash
minikube start --cpus=8 --disk-size='50gb' --memory=16384
minikube dashboard &
```

```bash
helm repo add bitnami https://charts.bitnami.com/bitnami
```

```bash
helm upgrade zookeeper bitnami/zookeeper \
  --set replicaCount=3 \
  --set auth.enabled=false \
  --set allowAnonymousLogin=true
```

```bash
helm upgrade kafka bitnami/kafka \
  --set zookeeper.enabled=false \
  --set replicaCount=4 \
  --set defaultReplicationFactor=3 \
  --set deleteTopicEnable=true \
  --set numPartitions=8 \
  --set externalZookeeper.servers=zookeeper.default.svc.cluster.local
```

```bash
eval $(minikube docker-env)
docker build -t vdesabou/kafkajs-bitnami-example-docker . -f ./Dockerfile-minikube
```

```bash
kubectl apply -f pod.yml
```

Update a config (for example default numPartitions) to have a rolling restart:

```bash
helm upgrade kafka bitnami/kafka \
  --set zookeeper.enabled=false \
  --set replicaCount=4 \
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

If we take one broker as an example:

```log
[[11:10:15.558]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:10:15.558Z","logger":"kafkajs","message":"[Connection] Response Produce(key: 0, version: 7)","broker":"kafka-1.kafka-headless.default.svc.cluster.local:9092","clientId":"my-kafkajs-producer","error":"This server is not the leader for that topic-partition","correlationId":273,"size":55}
[[11:10:30.457]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:10:30.457Z","logger":"kafkajs","message":"[Connection] Connection error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local","broker":"kafka-1.kafka-headless.default.svc.cluster.local:9092","clientId":"my-kafkajs-producer","stack":"Error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local\n    at GetAddrInfoReqWrap.onlookup [as oncomplete] (dns.js:69:26)"}
[[11:10:30.462]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:10:30.462Z","logger":"kafkajs","message":"[Producer] Failed to send messages: Connection error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local","retryCount":0,"retryTime":351}
[[11:10:30.819]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:10:30.819Z","logger":"kafkajs","message":"[Connection] Connection error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local","broker":"kafka-1.kafka-headless.default.svc.cluster.local:9092","clientId":"my-kafkajs-producer","stack":"Error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local\n    at GetAddrInfoReqWrap.onlookup [as oncomplete] (dns.js:69:26)"}
[[11:10:30.822]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:10:30.822Z","logger":"kafkajs","message":"[Producer] Failed to send messages: Connection error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local","retryCount":1,"retryTime":824}
[[11:10:31.158]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:10:31.158Z","logger":"kafkajs","message":"[Connection] Connection error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local","broker":"kafka-1.kafka-headless.default.svc.cluster.local:9092","clientId":"my-kafkajs-producer","stack":"Error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local\n    at GetAddrInfoReqWrap.onlookup [as oncomplete] (dns.js:69:26)"}
[[11:10:31.167]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:10:31.167Z","logger":"kafkajs","message":"[Producer] Failed to send messages: Connection error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local","retryCount":0,"retryTime":284}
[[11:10:31.462]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:10:31.462Z","logger":"kafkajs","message":"[Connection] Connection error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local","broker":"kafka-1.kafka-headless.default.svc.cluster.local:9092","clientId":"my-kafkajs-producer","stack":"Error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local\n    at GetAddrInfoReqWrap.onlookup [as oncomplete] (dns.js:69:26)"}
[[11:10:31.763]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:10:31.763Z","logger":"kafkajs","message":"[Connection] Connection error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local","broker":"kafka-1.kafka-headless.default.svc.cluster.local:9092","clientId":"my-kafkajs-producer","stack":"Error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local\n    at GetAddrInfoReqWrap.onlookup [as oncomplete] (dns.js:69:26)"}
[[11:10:32.162]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:10:32.162Z","logger":"kafkajs","message":"[Connection] Connection error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local","broker":"kafka-1.kafka-headless.default.svc.cluster.local:9092","clientId":"my-kafkajs-producer","stack":"Error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local\n    at GetAddrInfoReqWrap.onlookup [as oncomplete] (dns.js:69:26)"}
[[11:10:32.563]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:10:32.563Z","logger":"kafkajs","message":"[Connection] Connection error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local","broker":"kafka-1.kafka-headless.default.svc.cluster.local:9092","clientId":"my-kafkajs-producer","stack":"Error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local\n    at GetAddrInfoReqWrap.onlookup [as oncomplete] (dns.js:69:26)"}
[[11:10:32.966]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:10:32.966Z","logger":"kafkajs","message":"[Connection] Connection error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local","broker":"kafka-1.kafka-headless.default.svc.cluster.local:9092","clientId":"my-kafkajs-producer","stack":"Error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local\n    at GetAddrInfoReqWrap.onlookup [as oncomplete] (dns.js:69:26)"}
[[11:10:33.369]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:10:33.369Z","logger":"kafkajs","message":"[Connection] Connection error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local","broker":"kafka-1.kafka-headless.default.svc.cluster.local:9092","clientId":"my-kafkajs-producer","stack":"Error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local\n    at GetAddrInfoReqWrap.onlookup [as oncomplete] (dns.js:69:26)"}
[[11:10:33.767]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:10:33.767Z","logger":"kafkajs","message":"[Connection] Connection error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local","broker":"kafka-1.kafka-headless.default.svc.cluster.local:9092","clientId":"my-kafkajs-producer","stack":"Error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local\n    at GetAddrInfoReqWrap.onlookup [as oncomplete] (dns.js:69:26)"}
[[11:10:34.168]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:10:34.168Z","logger":"kafkajs","message":"[Connection] Connection error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local","broker":"kafka-1.kafka-headless.default.svc.cluster.local:9092","clientId":"my-kafkajs-producer","stack":"Error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local\n    at GetAddrInfoReqWrap.onlookup [as oncomplete] (dns.js:69:26)"}
[[11:10:34.569]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:10:34.569Z","logger":"kafkajs","message":"[Connection] Connection error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local","broker":"kafka-1.kafka-headless.default.svc.cluster.local:9092","clientId":"my-kafkajs-producer","stack":"Error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local\n    at GetAddrInfoReqWrap.onlookup [as oncomplete] (dns.js:69:26)"}
[[11:10:34.971]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:10:34.971Z","logger":"kafkajs","message":"[Connection] Connection error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local","broker":"kafka-1.kafka-headless.default.svc.cluster.local:9092","clientId":"my-kafkajs-producer","stack":"Error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local\n    at GetAddrInfoReqWrap.onlookup [as oncomplete] (dns.js:69:26)"}
[[11:10:35.372]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:10:35.371Z","logger":"kafkajs","message":"[Connection] Connection error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local","broker":"kafka-1.kafka-headless.default.svc.cluster.local:9092","clientId":"my-kafkajs-producer","stack":"Error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local\n    at GetAddrInfoReqWrap.onlookup [as oncomplete] (dns.js:69:26)"}
[[11:10:35.774]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:10:35.774Z","logger":"kafkajs","message":"[Connection] Connection error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local","broker":"kafka-1.kafka-headless.default.svc.cluster.local:9092","clientId":"my-kafkajs-producer","stack":"Error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local\n    at GetAddrInfoReqWrap.onlookup [as oncomplete] (dns.js:69:26)"}
[[11:10:36.176]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:10:36.176Z","logger":"kafkajs","message":"[Connection] Connection error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local","broker":"kafka-1.kafka-headless.default.svc.cluster.local:9092","clientId":"my-kafkajs-producer","stack":"Error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local\n    at GetAddrInfoReqWrap.onlookup [as oncomplete] (dns.js:69:26)"}
[[11:10:36.578]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:10:36.577Z","logger":"kafkajs","message":"[Connection] Connection error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local","broker":"kafka-1.kafka-headless.default.svc.cluster.local:9092","clientId":"my-kafkajs-producer","stack":"Error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local\n    at GetAddrInfoReqWrap.onlookup [as oncomplete] (dns.js:69:26)"}
[[11:10:36.977]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:10:36.977Z","logger":"kafkajs","message":"[Connection] Connection error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local","broker":"kafka-1.kafka-headless.default.svc.cluster.local:9092","clientId":"my-kafkajs-producer","stack":"Error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local\n    at GetAddrInfoReqWrap.onlookup [as oncomplete] (dns.js:69:26)"}
[[11:10:37.379]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:10:37.379Z","logger":"kafkajs","message":"[Connection] Connection error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local","broker":"kafka-1.kafka-headless.default.svc.cluster.local:9092","clientId":"my-kafkajs-producer","stack":"Error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local\n    at GetAddrInfoReqWrap.onlookup [as oncomplete] (dns.js:69:26)"}
[[11:10:37.780]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:10:37.780Z","logger":"kafkajs","message":"[Connection] Connection error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local","broker":"kafka-1.kafka-headless.default.svc.cluster.local:9092","clientId":"my-kafkajs-producer","stack":"Error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local\n    at GetAddrInfoReqWrap.onlookup [as oncomplete] (dns.js:69:26)"}
[[11:10:38.183]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:10:38.182Z","logger":"kafkajs","message":"[Connection] Connection error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local","broker":"kafka-1.kafka-headless.default.svc.cluster.local:9092","clientId":"my-kafkajs-producer","stack":"Error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local\n    at GetAddrInfoReqWrap.onlookup [as oncomplete] (dns.js:69:26)"}
[[11:10:38.583]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:10:38.583Z","logger":"kafkajs","message":"[Connection] Connection error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local","broker":"kafka-1.kafka-headless.default.svc.cluster.local:9092","clientId":"my-kafkajs-producer","stack":"Error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local\n    at GetAddrInfoReqWrap.onlookup [as oncomplete] (dns.js:69:26)"}
[[11:10:38.985]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:10:38.984Z","logger":"kafkajs","message":"[Connection] Connection error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local","broker":"kafka-1.kafka-headless.default.svc.cluster.local:9092","clientId":"my-kafkajs-producer","stack":"Error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local\n    at GetAddrInfoReqWrap.onlookup [as oncomplete] (dns.js:69:26)"}
[[11:10:39.388]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:10:39.388Z","logger":"kafkajs","message":"[Connection] Connection error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local","broker":"kafka-1.kafka-headless.default.svc.cluster.local:9092","clientId":"my-kafkajs-producer","stack":"Error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local\n    at GetAddrInfoReqWrap.onlookup [as oncomplete] (dns.js:69:26)"}
[[11:10:39.787]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:10:39.787Z","logger":"kafkajs","message":"[Connection] Connection error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local","broker":"kafka-1.kafka-headless.default.svc.cluster.local:9092","clientId":"my-kafkajs-producer","stack":"Error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local\n    at GetAddrInfoReqWrap.onlookup [as oncomplete] (dns.js:69:26)"}
[[11:10:40.189]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:10:40.189Z","logger":"kafkajs","message":"[Connection] Connection error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local","broker":"kafka-1.kafka-headless.default.svc.cluster.local:9092","clientId":"my-kafkajs-producer","stack":"Error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local\n    at GetAddrInfoReqWrap.onlookup [as oncomplete] (dns.js:69:26)"}
[[11:10:40.591]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:10:40.590Z","logger":"kafkajs","message":"[Connection] Connection error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local","broker":"kafka-1.kafka-headless.default.svc.cluster.local:9092","clientId":"my-kafkajs-producer","stack":"Error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local\n    at GetAddrInfoReqWrap.onlookup [as oncomplete] (dns.js:69:26)"}
[[11:10:40.991]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:10:40.991Z","logger":"kafkajs","message":"[Connection] Connection error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local","broker":"kafka-1.kafka-headless.default.svc.cluster.local:9092","clientId":"my-kafkajs-producer","stack":"Error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local\n    at GetAddrInfoReqWrap.onlookup [as oncomplete] (dns.js:69:26)"}
[[11:10:41.392]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:10:41.392Z","logger":"kafkajs","message":"[Connection] Connection error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local","broker":"kafka-1.kafka-headless.default.svc.cluster.local:9092","clientId":"my-kafkajs-producer","stack":"Error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local\n    at GetAddrInfoReqWrap.onlookup [as oncomplete] (dns.js:69:26)"}
[[11:10:41.793]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:10:41.793Z","logger":"kafkajs","message":"[Connection] Connection error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local","broker":"kafka-1.kafka-headless.default.svc.cluster.local:9092","clientId":"my-kafkajs-producer","stack":"Error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local\n    at GetAddrInfoReqWrap.onlookup [as oncomplete] (dns.js:69:26)"}
[[11:10:42.197]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:10:42.197Z","logger":"kafkajs","message":"[Connection] Connection error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local","broker":"kafka-1.kafka-headless.default.svc.cluster.local:9092","clientId":"my-kafkajs-producer","stack":"Error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local\n    at GetAddrInfoReqWrap.onlookup [as oncomplete] (dns.js:69:26)"}
[[11:10:42.596]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:10:42.596Z","logger":"kafkajs","message":"[Connection] Connection error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local","broker":"kafka-1.kafka-headless.default.svc.cluster.local:9092","clientId":"my-kafkajs-producer","stack":"Error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local\n    at GetAddrInfoReqWrap.onlookup [as oncomplete] (dns.js:69:26)"}
[[11:10:43.000]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:10:43.000Z","logger":"kafkajs","message":"[Connection] Connection error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local","broker":"kafka-1.kafka-headless.default.svc.cluster.local:9092","clientId":"my-kafkajs-producer","stack":"Error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local\n    at GetAddrInfoReqWrap.onlookup [as oncomplete] (dns.js:69:26)"}
[[11:10:43.399]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:10:43.399Z","logger":"kafkajs","message":"[Connection] Connection error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local","broker":"kafka-1.kafka-headless.default.svc.cluster.local:9092","clientId":"my-kafkajs-producer","stack":"Error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local\n    at GetAddrInfoReqWrap.onlookup [as oncomplete] (dns.js:69:26)"}
[[11:10:43.800]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:10:43.800Z","logger":"kafkajs","message":"[Connection] Connection error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local","broker":"kafka-1.kafka-headless.default.svc.cluster.local:9092","clientId":"my-kafkajs-producer","stack":"Error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local\n    at GetAddrInfoReqWrap.onlookup [as oncomplete] (dns.js:69:26)"}
[[11:10:44.201]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:10:44.201Z","logger":"kafkajs","message":"[Connection] Connection error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local","broker":"kafka-1.kafka-headless.default.svc.cluster.local:9092","clientId":"my-kafkajs-producer","stack":"Error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local\n    at GetAddrInfoReqWrap.onlookup [as oncomplete] (dns.js:69:26)"}
[[11:10:44.604]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:10:44.603Z","logger":"kafkajs","message":"[Connection] Connection error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local","broker":"kafka-1.kafka-headless.default.svc.cluster.local:9092","clientId":"my-kafkajs-producer","stack":"Error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local\n    at GetAddrInfoReqWrap.onlookup [as oncomplete] (dns.js:69:26)"}
[[11:10:44.876]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:10:44.876Z","logger":"kafkajs","message":"[Producer] Failed to send messages: Connection error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local","retryCount":0,"retryTime":341}
[[11:10:44.922]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:10:44.922Z","logger":"kafkajs","message":"[Producer] Failed to send messages: Connection error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local","retryCount":0,"retryTime":297}
[[11:10:44.936]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:10:44.935Z","logger":"kafkajs","message":"[Producer] Failed to send messages: Connection error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local","retryCount":0,"retryTime":242}
[[11:10:45.004]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:10:45.004Z","logger":"kafkajs","message":"[Connection] Connection error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local","broker":"kafka-1.kafka-headless.default.svc.cluster.local:9092","clientId":"my-kafkajs-producer","stack":"Error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local\n    at GetAddrInfoReqWrap.onlookup [as oncomplete] (dns.js:69:26)"}
[[11:10:45.014]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:10:45.014Z","logger":"kafkajs","message":"[Producer] Failed to send messages: Connection error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local","retryCount":0,"retryTime":289}
[[11:10:45.073]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:10:45.073Z","logger":"kafkajs","message":"[Producer] Failed to send messages: Connection error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local","retryCount":0,"retryTime":293}
[[11:10:45.219]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:10:45.219Z","logger":"kafkajs","message":"[Connection] Connection error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local","broker":"kafka-1.kafka-headless.default.svc.cluster.local:9092","clientId":"my-kafkajs-producer","stack":"Error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local\n    at GetAddrInfoReqWrap.onlookup [as oncomplete] (dns.js:69:26)"}
[[11:10:45.223]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:10:45.223Z","logger":"kafkajs","message":"[Producer] Failed to send messages: Connection error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local","retryCount":1,"retryTime":658}
[[11:10:45.303]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:10:45.303Z","logger":"kafkajs","message":"[Connection] Connection error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local","broker":"kafka-1.kafka-headless.default.svc.cluster.local:9092","clientId":"my-kafkajs-producer","stack":"Error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local\n    at GetAddrInfoReqWrap.onlookup [as oncomplete] (dns.js:69:26)"}
[[11:10:45.324]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:10:45.324Z","logger":"kafkajs","message":"[Producer] Failed to send messages: Connection error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local","retryCount":0,"retryTime":329}
[[11:10:45.346]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:10:45.346Z","logger":"kafkajs","message":"[Producer] Failed to send messages: Connection error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local","retryCount":0,"retryTime":272}
[[11:10:45.403]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:10:45.403Z","logger":"kafkajs","message":"[Connection] Connection error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local","broker":"kafka-1.kafka-headless.default.svc.cluster.local:9092","clientId":"my-kafkajs-producer","stack":"Error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local\n    at GetAddrInfoReqWrap.onlookup [as oncomplete] (dns.js:69:26)"}
[[11:10:45.406]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:10:45.406Z","logger":"kafkajs","message":"[Producer] Failed to send messages: Connection error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local","retryCount":0,"retryTime":247}
[[11:10:45.486]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:10:45.485Z","logger":"kafkajs","message":"[Connection] Connection error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local","broker":"kafka-1.kafka-headless.default.svc.cluster.local:9092","clientId":"my-kafkajs-producer","stack":"Error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local\n    at GetAddrInfoReqWrap.onlookup [as oncomplete] (dns.js:69:26)"}
[[11:10:45.489]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:10:45.489Z","logger":"kafkajs","message":"[Producer] Failed to send messages: Connection error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local","retryCount":1,"retryTime":614}
[[11:10:45.505]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:10:45.504Z","logger":"kafkajs","message":"[Producer] Failed to send messages: Connection error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local","retryCount":0,"retryTime":267}
[[11:10:45.610]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:10:45.609Z","logger":"kafkajs","message":"[Producer] Failed to send messages: Connection error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local","retryCount":0,"retryTime":313}
[[11:10:45.622]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:10:45.622Z","logger":"kafkajs","message":"[Connection] Connection error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local","broker":"kafka-1.kafka-headless.default.svc.cluster.local:9092","clientId":"my-kafkajs-producer","stack":"Error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local\n    at GetAddrInfoReqWrap.onlookup [as oncomplete] (dns.js:69:26)"}
[[11:10:45.628]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:10:45.628Z","logger":"kafkajs","message":"[Producer] Failed to send messages: Connection error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local","retryCount":1,"retryTime":598}
[[11:10:45.634]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:10:45.634Z","logger":"kafkajs","message":"[Producer] Failed to send messages: Connection error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local","retryCount":0,"retryTime":360}
[[11:10:45.709]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:10:45.708Z","logger":"kafkajs","message":"[Producer] Failed to send messages: Connection error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local","retryCount":0,"retryTime":352}
[[11:10:45.778]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:10:45.778Z","logger":"kafkajs","message":"[Connection] Connection error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local","broker":"kafka-1.kafka-headless.default.svc.cluster.local:9092","clientId":"my-kafkajs-producer","stack":"Error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local\n    at GetAddrInfoReqWrap.onlookup [as oncomplete] (dns.js:69:26)"}
[[11:10:45.782]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:10:45.782Z","logger":"kafkajs","message":"[Producer] Failed to send messages: Connection error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local","retryCount":1,"retryTime":604}
[[11:10:45.860]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:10:45.860Z","logger":"kafkajs","message":"[Producer] Failed to send messages: Connection error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local","retryCount":0,"retryTime":250}
[[11:10:45.931]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:10:45.931Z","logger":"kafkajs","message":"[Connection] Connection error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local","broker":"kafka-1.kafka-headless.default.svc.cluster.local:9092","clientId":"my-kafkajs-producer","stack":"Error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local\n    at GetAddrInfoReqWrap.onlookup [as oncomplete] (dns.js:69:26)"}
[[11:10:45.941]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:10:45.941Z","logger":"kafkajs","message":"[Producer] Failed to send messages: Connection error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local","retryCount":1,"retryTime":602}
[[11:10:46.068]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:10:46.068Z","logger":"kafkajs","message":"[Connection] Connection error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local","broker":"kafka-1.kafka-headless.default.svc.cluster.local:9092","clientId":"my-kafkajs-producer","stack":"Error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local\n    at GetAddrInfoReqWrap.onlookup [as oncomplete] (dns.js:69:26)"}
[[11:10:46.075]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:10:46.073Z","logger":"kafkajs","message":"[Producer] Failed to send messages: Connection error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local","retryCount":1,"retryTime":722}
[[11:10:46.127]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:10:46.127Z","logger":"kafkajs","message":"[Connection] Connection error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local","broker":"kafka-1.kafka-headless.default.svc.cluster.local:9092","clientId":"my-kafkajs-producer","stack":"Error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local\n    at GetAddrInfoReqWrap.onlookup [as oncomplete] (dns.js:69:26)"}
[[11:10:46.131]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:10:46.131Z","logger":"kafkajs","message":"[Producer] Failed to send messages: Connection error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local","retryCount":0,"retryTime":303}
[[11:10:46.136]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:10:46.136Z","logger":"kafkajs","message":"[Producer] Failed to send messages: Connection error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local","retryCount":1,"retryTime":570}
[[11:10:46.233]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:10:46.233Z","logger":"kafkajs","message":"[Connection] Connection error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local","broker":"kafka-1.kafka-headless.default.svc.cluster.local:9092","clientId":"my-kafkajs-producer","stack":"Error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local\n    at GetAddrInfoReqWrap.onlookup [as oncomplete] (dns.js:69:26)"}
[[11:10:46.239]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:10:46.239Z","logger":"kafkajs","message":"[Producer] Failed to send messages: Connection error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local","retryCount":2,"retryTime":1234}
[[11:10:46.408]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:10:46.408Z","logger":"kafkajs","message":"[Connection] Connection error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local","broker":"kafka-1.kafka-headless.default.svc.cluster.local:9092","clientId":"my-kafkajs-producer","stack":"Error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local\n    at GetAddrInfoReqWrap.onlookup [as oncomplete] (dns.js:69:26)"}
[[11:10:46.413]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:10:46.413Z","logger":"kafkajs","message":"[Producer] Failed to send messages: Connection error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local","retryCount":0,"retryTime":273}
[[11:10:46.522]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:10:46.522Z","logger":"kafkajs","message":"[Producer] Failed to send messages: Connection error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local","retryCount":0,"retryTime":278}
[[11:10:46.533]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:10:46.533Z","logger":"kafkajs","message":"[Producer] Failed to send messages: Connection error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local","retryCount":0,"retryTime":347}
[[11:10:46.608]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:10:46.608Z","logger":"kafkajs","message":"[Connection] Connection error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local","broker":"kafka-1.kafka-headless.default.svc.cluster.local:9092","clientId":"my-kafkajs-producer","stack":"Error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local\n    at GetAddrInfoReqWrap.onlookup [as oncomplete] (dns.js:69:26)"}
[[11:10:46.611]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:10:46.611Z","logger":"kafkajs","message":"[Producer] Failed to send messages: Connection error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local","retryCount":0,"retryTime":353}
[[11:10:46.666]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:10:46.666Z","logger":"kafkajs","message":"[Producer] Failed to send messages: Connection error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local","retryCount":0,"retryTime":298}
[[11:10:46.718]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:10:46.718Z","logger":"kafkajs","message":"[Connection] Connection error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local","broker":"kafka-1.kafka-headless.default.svc.cluster.local:9092","clientId":"my-kafkajs-producer","stack":"Error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local\n    at GetAddrInfoReqWrap.onlookup [as oncomplete] (dns.js:69:26)"}
[[11:10:46.720]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:10:46.720Z","logger":"kafkajs","message":"[Producer] Failed to send messages: Connection error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local","retryCount":2,"retryTime":962}
[[11:10:46.806]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:10:46.806Z","logger":"kafkajs","message":"[Producer] Failed to send messages: Connection error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local","retryCount":0,"retryTime":317}
[[11:10:46.885]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:10:46.885Z","logger":"kafkajs","message":"[Connection] Connection error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local","broker":"kafka-1.kafka-headless.default.svc.cluster.local:9092","clientId":"my-kafkajs-producer","stack":"Error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local\n    at GetAddrInfoReqWrap.onlookup [as oncomplete] (dns.js:69:26)"}
[[11:10:46.888]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:10:46.888Z","logger":"kafkajs","message":"[Producer] Failed to send messages: Connection error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local","retryCount":1,"retryTime":696}
[[11:10:46.942]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:10:46.942Z","logger":"kafkajs","message":"[Producer] Failed to send messages: Connection error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local","retryCount":0,"retryTime":243}
[[11:10:47.005]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:10:47.005Z","logger":"kafkajs","message":"[Connection] Connection error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local","broker":"kafka-1.kafka-headless.default.svc.cluster.local:9092","clientId":"my-kafkajs-producer","stack":"Error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local\n    at GetAddrInfoReqWrap.onlookup [as oncomplete] (dns.js:69:26)"}
[[11:10:47.009]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:10:47.009Z","logger":"kafkajs","message":"[Producer] Failed to send messages: Connection error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local","retryCount":1,"retryTime":508}
[[11:10:47.162]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:10:47.162Z","logger":"kafkajs","message":"[Connection] Connection error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local","broker":"kafka-1.kafka-headless.default.svc.cluster.local:9092","clientId":"my-kafkajs-producer","stack":"Error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local\n    at GetAddrInfoReqWrap.onlookup [as oncomplete] (dns.js:69:26)"}
[[11:10:47.164]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:10:47.164Z","logger":"kafkajs","message":"[Producer] Failed to send messages: Connection error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local","retryCount":1,"retryTime":476}
[[11:10:47.331]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:10:47.331Z","logger":"kafkajs","message":"[Producer] Failed to send messages: Connection error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local","retryCount":0,"retryTime":342}
[[11:10:47.346]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:10:47.346Z","logger":"kafkajs","message":"[Producer] Failed to send messages: Connection error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local","retryCount":0,"retryTime":296}
[[11:10:47.407]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:10:47.407Z","logger":"kafkajs","message":"[Connection] Connection error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local","broker":"kafka-1.kafka-headless.default.svc.cluster.local:9092","clientId":"my-kafkajs-producer","stack":"Error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local\n    at GetAddrInfoReqWrap.onlookup [as oncomplete] (dns.js:69:26)"}
[[11:10:47.415]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:10:47.415Z","logger":"kafkajs","message":"[Producer] Failed to send messages: Connection error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local","retryCount":1,"retryTime":710}
[[11:10:47.511]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:10:47.511Z","logger":"kafkajs","message":"[Connection] Connection error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local","broker":"kafka-1.kafka-headless.default.svc.cluster.local:9092","clientId":"my-kafkajs-producer","stack":"Error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local\n    at GetAddrInfoReqWrap.onlookup [as oncomplete] (dns.js:69:26)"}
[[11:10:47.514]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:10:47.514Z","logger":"kafkajs","message":"[Producer] Failed to send messages: Connection error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local","retryCount":0,"retryTime":350}
[[11:10:47.635]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:10:47.635Z","logger":"kafkajs","message":"[Producer] Failed to send messages: Connection error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local","retryCount":0,"retryTime":352}
[[11:10:47.644]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:10:47.643Z","logger":"kafkajs","message":"[Connection] Connection error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local","broker":"kafka-1.kafka-headless.default.svc.cluster.local:9092","clientId":"my-kafkajs-producer","stack":"Error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local\n    at GetAddrInfoReqWrap.onlookup [as oncomplete] (dns.js:69:26)"}
[[11:10:47.650]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:10:47.649Z","logger":"kafkajs","message":"[Producer] Failed to send messages: Connection error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local","retryCount":2,"retryTime":1060}
[[11:10:47.691]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:10:47.691Z","logger":"kafkajs","message":"[Connection] Connection error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local","broker":"kafka-1.kafka-headless.default.svc.cluster.local:9092","clientId":"my-kafkajs-producer","stack":"Error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local\n    at GetAddrInfoReqWrap.onlookup [as oncomplete] (dns.js:69:26)"}
[[11:10:47.696]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:10:47.696Z","logger":"kafkajs","message":"[Producer] Failed to send messages: Connection error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local","retryCount":1,"retryTime":762}
[[11:10:47.781]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:10:47.781Z","logger":"kafkajs","message":"[Producer] Failed to send messages: Connection error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local","retryCount":0,"retryTime":320}
[[11:10:47.834]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:10:47.834Z","logger":"kafkajs","message":"[Connection] Connection error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local","broker":"kafka-1.kafka-headless.default.svc.cluster.local:9092","clientId":"my-kafkajs-producer","stack":"Error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local\n    at GetAddrInfoReqWrap.onlookup [as oncomplete] (dns.js:69:26)"}
[[11:10:47.841]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:10:47.840Z","logger":"kafkajs","message":"[Producer] Failed to send messages: Connection error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local","retryCount":1,"retryTime":694}
[[11:10:47.940]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:10:47.939Z","logger":"kafkajs","message":"[Connection] Connection error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local","broker":"kafka-1.kafka-headless.default.svc.cluster.local:9092","clientId":"my-kafkajs-producer","stack":"Error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local\n    at GetAddrInfoReqWrap.onlookup [as oncomplete] (dns.js:69:26)"}
[[11:10:47.943]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:10:47.943Z","logger":"kafkajs","message":"[Producer] Failed to send messages: Connection error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local","retryCount":1,"retryTime":560}
[[11:10:48.114]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:10:48.114Z","logger":"kafkajs","message":"[Connection] Connection error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local","broker":"kafka-1.kafka-headless.default.svc.cluster.local:9092","clientId":"my-kafkajs-producer","stack":"Error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local\n    at GetAddrInfoReqWrap.onlookup [as oncomplete] (dns.js:69:26)"}
[[11:10:48.119]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:10:48.119Z","logger":"kafkajs","message":"[Producer] Failed to send messages: Connection error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local","retryCount":0,"retryTime":331}
[[11:10:48.257]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:10:48.257Z","logger":"kafkajs","message":"[Producer] Failed to send messages: Connection error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local","retryCount":0,"retryTime":269}
[[11:10:48.314]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:10:48.314Z","logger":"kafkajs","message":"[Connection] Connection error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local","broker":"kafka-1.kafka-headless.default.svc.cluster.local:9092","clientId":"my-kafkajs-producer","stack":"Error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local\n    at GetAddrInfoReqWrap.onlookup [as oncomplete] (dns.js:69:26)"}
[[11:10:48.321]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:10:48.321Z","logger":"kafkajs","message":"[Producer] Failed to send messages: Connection error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local","retryCount":0,"retryTime":250}
[[11:10:48.465]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:10:48.465Z","logger":"kafkajs","message":"[Connection] Connection error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local","broker":"kafka-1.kafka-headless.default.svc.cluster.local:9092","clientId":"my-kafkajs-producer","stack":"Error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local\n    at GetAddrInfoReqWrap.onlookup [as oncomplete] (dns.js:69:26)"}
[[11:10:48.470]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:10:48.470Z","logger":"kafkajs","message":"[Producer] Failed to send messages: Connection error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local","retryCount":2,"retryTime":1460}
[[11:10:48.538]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:10:48.538Z","logger":"kafkajs","message":"[Connection] Connection error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local","broker":"kafka-1.kafka-headless.default.svc.cluster.local:9092","clientId":"my-kafkajs-producer","stack":"Error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local\n    at GetAddrInfoReqWrap.onlookup [as oncomplete] (dns.js:69:26)"}
[[11:10:48.543]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:10:48.543Z","logger":"kafkajs","message":"[Producer] Failed to send messages: Connection error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local","retryCount":2,"retryTime":1264}
[[11:10:48.713]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:10:48.713Z","logger":"kafkajs","message":"[Producer] Failed to send messages: Connection error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local","retryCount":0,"retryTime":308}
[[11:10:48.719]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:10:48.719Z","logger":"kafkajs","message":"[Connection] Connection error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local","broker":"kafka-1.kafka-headless.default.svc.cluster.local:9092","clientId":"my-kafkajs-producer","stack":"Error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local\n    at GetAddrInfoReqWrap.onlookup [as oncomplete] (dns.js:69:26)"}
[[11:10:48.722]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:10:48.722Z","logger":"kafkajs","message":"[Producer] Failed to send messages: Connection error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local","retryCount":3,"retryTime":2174}
[[11:10:49.027]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:10:49.027Z","logger":"kafkajs","message":"[Connection] Connection error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local","broker":"kafka-1.kafka-headless.default.svc.cluster.local:9092","clientId":"my-kafkajs-producer","stack":"Error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local\n    at GetAddrInfoReqWrap.onlookup [as oncomplete] (dns.js:69:26)"}
[[11:10:49.030]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:10:49.030Z","logger":"kafkajs","message":"[Producer] Failed to send messages: Connection error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local","retryCount":1,"retryTime":612}
[[11:10:49.217]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:10:49.216Z","logger":"kafkajs","message":"[Connection] Connection error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local","broker":"kafka-1.kafka-headless.default.svc.cluster.local:9092","clientId":"my-kafkajs-producer","stack":"Error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local\n    at GetAddrInfoReqWrap.onlookup [as oncomplete] (dns.js:69:26)"}
[[11:10:49.224]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:10:49.223Z","logger":"kafkajs","message":"[Producer] Failed to send messages: Connection error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local","retryCount":0,"retryTime":251}
[[11:10:49.517]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:10:49.517Z","logger":"kafkajs","message":"[Connection] Connection error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local","broker":"kafka-1.kafka-headless.default.svc.cluster.local:9092","clientId":"my-kafkajs-producer","stack":"Error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local\n    at GetAddrInfoReqWrap.onlookup [as oncomplete] (dns.js:69:26)"}
[[11:10:49.519]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:10:49.519Z","logger":"kafkajs","message":"[Producer] Failed to send messages: Connection error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local","retryCount":0,"retryTime":344}
[[11:10:49.720]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:10:49.720Z","logger":"kafkajs","message":"[Connection] Connection error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local","broker":"kafka-1.kafka-headless.default.svc.cluster.local:9092","clientId":"my-kafkajs-producer","stack":"Error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local\n    at GetAddrInfoReqWrap.onlookup [as oncomplete] (dns.js:69:26)"}
[[11:10:49.725]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:10:49.725Z","logger":"kafkajs","message":"[Producer] Failed to send messages: Connection error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local","retryCount":0,"retryTime":290}
[[11:10:49.918]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:10:49.918Z","logger":"kafkajs","message":"[Connection] Connection error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local","broker":"kafka-1.kafka-headless.default.svc.cluster.local:9092","clientId":"my-kafkajs-producer","stack":"Error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local\n    at GetAddrInfoReqWrap.onlookup [as oncomplete] (dns.js:69:26)"}
[[11:10:49.889]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:10:49.889Z","logger":"kafkajs","message":"[Producer] Failed to send messages: Connection error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local","retryCount":0,"retryTime":333}
[[11:10:50.088]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:10:50.087Z","logger":"kafkajs","message":"[Connection] Connection error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local","broker":"kafka-1.kafka-headless.default.svc.cluster.local:9092","clientId":"my-kafkajs-producer","stack":"Error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local\n    at GetAddrInfoReqWrap.onlookup [as oncomplete] (dns.js:69:26)"}
[[11:10:50.093]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:10:50.093Z","logger":"kafkajs","message":"[Producer] Failed to send messages: Connection error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local","retryCount":0,"retryTime":357}
[[11:10:50.298]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:10:50.298Z","logger":"kafkajs","message":"[Connection] Connection error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local","broker":"kafka-1.kafka-headless.default.svc.cluster.local:9092","clientId":"my-kafkajs-producer","stack":"Error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local\n    at GetAddrInfoReqWrap.onlookup [as oncomplete] (dns.js:69:26)"}
[[11:10:50.302]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:10:50.302Z","logger":"kafkajs","message":"[Producer] Failed to send messages: Connection error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local","retryCount":0,"retryTime":274}
[[11:10:50.586]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:10:50.586Z","logger":"kafkajs","message":"[Connection] Connection error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local","broker":"kafka-1.kafka-headless.default.svc.cluster.local:9092","clientId":"my-kafkajs-producer","stack":"Error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local\n    at GetAddrInfoReqWrap.onlookup [as oncomplete] (dns.js:69:26)"}
[[11:10:50.596]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:10:50.596Z","logger":"kafkajs","message":"[Producer] Failed to send messages: Connection error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local","retryCount":1,"retryTime":524}
[[11:10:50.787]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:10:50.787Z","logger":"kafkajs","message":"[Connection] Connection error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local","broker":"kafka-1.kafka-headless.default.svc.cluster.local:9092","clientId":"my-kafkajs-producer","stack":"Error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local\n    at GetAddrInfoReqWrap.onlookup [as oncomplete] (dns.js:69:26)"}
[[11:10:50.790]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:10:50.790Z","logger":"kafkajs","message":"[Producer] Failed to send messages: Connection error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local","retryCount":0,"retryTime":332}
[[11:10:50.989]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:10:50.989Z","logger":"kafkajs","message":"[Connection] Connection error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local","broker":"kafka-1.kafka-headless.default.svc.cluster.local:9092","clientId":"my-kafkajs-producer","stack":"Error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local\n    at GetAddrInfoReqWrap.onlookup [as oncomplete] (dns.js:69:26)"}
[[11:10:50.995]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:10:50.995Z","logger":"kafkajs","message":"[Producer] Failed to send messages: Connection error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local","retryCount":0,"retryTime":283}
[[11:10:51.190]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:10:51.189Z","logger":"kafkajs","message":"[Connection] Connection error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local","broker":"kafka-1.kafka-headless.default.svc.cluster.local:9092","clientId":"my-kafkajs-producer","stack":"Error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local\n    at GetAddrInfoReqWrap.onlookup [as oncomplete] (dns.js:69:26)"}
[[11:10:51.195]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:10:51.195Z","logger":"kafkajs","message":"[Producer] Failed to send messages: Connection error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local","retryCount":0,"retryTime":318}
[[11:10:51.444]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:10:51.444Z","logger":"kafkajs","message":"[Connection] Connection error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local","broker":"kafka-1.kafka-headless.default.svc.cluster.local:9092","clientId":"my-kafkajs-producer","stack":"Error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local\n    at GetAddrInfoReqWrap.onlookup [as oncomplete] (dns.js:69:26)"}
[[11:10:51.449]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:10:51.449Z","logger":"kafkajs","message":"[Producer] Failed to send messages: Connection error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local","retryCount":1,"retryTime":552}
[[11:10:51.692]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:10:51.691Z","logger":"kafkajs","message":"[Connection] Connection error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local","broker":"kafka-1.kafka-headless.default.svc.cluster.local:9092","clientId":"my-kafkajs-producer","stack":"Error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local\n    at GetAddrInfoReqWrap.onlookup [as oncomplete] (dns.js:69:26)"}
[[11:10:51.696]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:10:51.696Z","logger":"kafkajs","message":"[Producer] Failed to send messages: Connection error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local","retryCount":0,"retryTime":320}
[[11:10:51.992]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:10:51.992Z","logger":"kafkajs","message":"[Connection] Connection error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local","broker":"kafka-1.kafka-headless.default.svc.cluster.local:9092","clientId":"my-kafkajs-producer","stack":"Error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local\n    at GetAddrInfoReqWrap.onlookup [as oncomplete] (dns.js:69:26)"}
[[11:10:51.997]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:10:51.997Z","logger":"kafkajs","message":"[Producer] Failed to send messages: Connection error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local","retryCount":0,"retryTime":333}
[[11:10:52.196]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:10:52.196Z","logger":"kafkajs","message":"[Connection] Connection error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local","broker":"kafka-1.kafka-headless.default.svc.cluster.local:9092","clientId":"my-kafkajs-producer","stack":"Error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local\n    at GetAddrInfoReqWrap.onlookup [as oncomplete] (dns.js:69:26)"}
[[11:10:52.204]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:10:52.204Z","logger":"kafkajs","message":"[Producer] Failed to send messages: Connection error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local","retryCount":0,"retryTime":263}
[[11:10:52.471]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:10:52.471Z","logger":"kafkajs","message":"[Connection] Connection error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local","broker":"kafka-1.kafka-headless.default.svc.cluster.local:9092","clientId":"my-kafkajs-producer","stack":"Error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local\n    at GetAddrInfoReqWrap.onlookup [as oncomplete] (dns.js:69:26)"}
[[11:10:52.475]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:10:52.475Z","logger":"kafkajs","message":"[Producer] Failed to send messages: Connection error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local","retryCount":1,"retryTime":560}
[[11:10:52.796]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:10:52.796Z","logger":"kafkajs","message":"[Connection] Connection error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local","broker":"kafka-1.kafka-headless.default.svc.cluster.local:9092","clientId":"my-kafkajs-producer","stack":"Error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local\n    at GetAddrInfoReqWrap.onlookup [as oncomplete] (dns.js:69:26)"}
[[11:10:52.800]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:10:52.800Z","logger":"kafkajs","message":"[Producer] Failed to send messages: Connection error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local","retryCount":0,"retryTime":261}
[[11:10:53.065]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:10:53.065Z","logger":"kafkajs","message":"[Connection] Connection error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local","broker":"kafka-1.kafka-headless.default.svc.cluster.local:9092","clientId":"my-kafkajs-producer","stack":"Error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local\n    at GetAddrInfoReqWrap.onlookup [as oncomplete] (dns.js:69:26)"}
[[11:10:53.070]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:10:53.070Z","logger":"kafkajs","message":"[Producer] Failed to send messages: Connection error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local","retryCount":1,"retryTime":428}
[[11:10:53.401]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:10:53.401Z","logger":"kafkajs","message":"[Connection] Connection error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local","broker":"kafka-1.kafka-headless.default.svc.cluster.local:9092","clientId":"my-kafkajs-producer","stack":"Error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local\n    at GetAddrInfoReqWrap.onlookup [as oncomplete] (dns.js:69:26)"}
[[11:10:53.406]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:10:53.406Z","logger":"kafkajs","message":"[Producer] Failed to send messages: Connection error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local","retryCount":0,"retryTime":267}
[[11:10:53.681]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:10:53.681Z","logger":"kafkajs","message":"[Connection] Connection error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local","broker":"kafka-1.kafka-headless.default.svc.cluster.local:9092","clientId":"my-kafkajs-producer","stack":"Error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local\n    at GetAddrInfoReqWrap.onlookup [as oncomplete] (dns.js:69:26)"}
[[11:10:53.684]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:10:53.684Z","logger":"kafkajs","message":"[Producer] Failed to send messages: Connection error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local","retryCount":1,"retryTime":442}
[[11:10:53.900]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:10:53.900Z","logger":"kafkajs","message":"[Connection] Connection error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local","broker":"kafka-1.kafka-headless.default.svc.cluster.local:9092","clientId":"my-kafkajs-producer","stack":"Error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local\n    at GetAddrInfoReqWrap.onlookup [as oncomplete] (dns.js:69:26)"}
[[11:10:53.903]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:10:53.903Z","logger":"kafkajs","message":"[Producer] Failed to send messages: Connection error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local","retryCount":0,"retryTime":288}
[[11:10:54.200]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:10:54.200Z","logger":"kafkajs","message":"[Connection] Connection error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local","broker":"kafka-1.kafka-headless.default.svc.cluster.local:9092","clientId":"my-kafkajs-producer","stack":"Error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local\n    at GetAddrInfoReqWrap.onlookup [as oncomplete] (dns.js:69:26)"}
[[11:10:54.207]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:10:54.207Z","logger":"kafkajs","message":"[Producer] Failed to send messages: Connection error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local","retryCount":1,"retryTime":518}
[[11:10:54.501]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:10:54.501Z","logger":"kafkajs","message":"[Connection] Connection error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local","broker":"kafka-1.kafka-headless.default.svc.cluster.local:9092","clientId":"my-kafkajs-producer","stack":"Error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local\n    at GetAddrInfoReqWrap.onlookup [as oncomplete] (dns.js:69:26)"}
[[11:10:54.504]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:10:54.504Z","logger":"kafkajs","message":"[Producer] Failed to send messages: Connection error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local","retryCount":0,"retryTime":304}
[[11:10:54.802]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:10:54.802Z","logger":"kafkajs","message":"[Connection] Connection error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local","broker":"kafka-1.kafka-headless.default.svc.cluster.local:9092","clientId":"my-kafkajs-producer","stack":"Error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local\n    at GetAddrInfoReqWrap.onlookup [as oncomplete] (dns.js:69:26)"}
[[11:10:54.806]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:10:54.806Z","logger":"kafkajs","message":"[Producer] Failed to send messages: Connection error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local","retryCount":0,"retryTime":259}
[[11:10:55.070]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:10:55.070Z","logger":"kafkajs","message":"[Connection] Connection error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local","broker":"kafka-1.kafka-headless.default.svc.cluster.local:9092","clientId":"my-kafkajs-producer","stack":"Error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local\n    at GetAddrInfoReqWrap.onlookup [as oncomplete] (dns.js:69:26)"}
[[11:10:55.073]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:10:55.073Z","logger":"kafkajs","message":"[Producer] Failed to send messages: Connection error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local","retryCount":1,"retryTime":598}
[[11:10:55.404]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:10:55.403Z","logger":"kafkajs","message":"[Connection] Connection error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local","broker":"kafka-1.kafka-headless.default.svc.cluster.local:9092","clientId":"my-kafkajs-producer","stack":"Error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local\n    at GetAddrInfoReqWrap.onlookup [as oncomplete] (dns.js:69:26)"}
[[11:10:55.406]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:10:55.406Z","logger":"kafkajs","message":"[Producer] Failed to send messages: Connection error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local","retryCount":0,"retryTime":292}
[[11:10:55.704]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:10:55.703Z","logger":"kafkajs","message":"[Connection] Connection error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local","broker":"kafka-1.kafka-headless.default.svc.cluster.local:9092","clientId":"my-kafkajs-producer","stack":"Error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local\n    at GetAddrInfoReqWrap.onlookup [as oncomplete] (dns.js:69:26)"}
[[11:10:55.708]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:10:55.708Z","logger":"kafkajs","message":"[Producer] Failed to send messages: Connection error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local","retryCount":1,"retryTime":700}
[[11:10:56.008]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:10:56.008Z","logger":"kafkajs","message":"[Connection] Connection error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local","broker":"kafka-1.kafka-headless.default.svc.cluster.local:9092","clientId":"my-kafkajs-producer","stack":"Error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local\n    at GetAddrInfoReqWrap.onlookup [as oncomplete] (dns.js:69:26)"}
[[11:10:56.011]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:10:56.011Z","logger":"kafkajs","message":"[Producer] Failed to send messages: Connection error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local","retryCount":0,"retryTime":358}
[[11:10:56.371]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:10:56.371Z","logger":"kafkajs","message":"[Connection] Connection error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local","broker":"kafka-1.kafka-headless.default.svc.cluster.local:9092","clientId":"my-kafkajs-producer","stack":"Error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local\n    at GetAddrInfoReqWrap.onlookup [as oncomplete] (dns.js:69:26)"}
[[11:10:56.374]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:10:56.374Z","logger":"kafkajs","message":"[Producer] Failed to send messages: Connection error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local","retryCount":1,"retryTime":792}
[[11:10:56.608]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:10:56.608Z","logger":"kafkajs","message":"[Connection] Connection error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local","broker":"kafka-1.kafka-headless.default.svc.cluster.local:9092","clientId":"my-kafkajs-producer","stack":"Error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local\n    at GetAddrInfoReqWrap.onlookup [as oncomplete] (dns.js:69:26)"}
[[11:10:56.611]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:10:56.611Z","logger":"kafkajs","message":"[Producer] Failed to send messages: Connection error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local","retryCount":0,"retryTime":271}
[[11:10:56.909]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:10:56.909Z","logger":"kafkajs","message":"[Connection] Connection error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local","broker":"kafka-1.kafka-headless.default.svc.cluster.local:9092","clientId":"my-kafkajs-producer","stack":"Error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local\n    at GetAddrInfoReqWrap.onlookup [as oncomplete] (dns.js:69:26)"}
[[11:10:56.913]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:10:56.913Z","logger":"kafkajs","message":"[Producer] Failed to send messages: Connection error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local","retryCount":0,"retryTime":291}
[[11:10:57.210]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:10:57.209Z","logger":"kafkajs","message":"[Connection] Connection error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local","broker":"kafka-1.kafka-headless.default.svc.cluster.local:9092","clientId":"my-kafkajs-producer","stack":"Error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local\n    at GetAddrInfoReqWrap.onlookup [as oncomplete] (dns.js:69:26)"}
[[11:10:57.216]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:10:57.215Z","logger":"kafkajs","message":"[Producer] Failed to send messages: Connection error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local","retryCount":0,"retryTime":282}
[[11:10:57.503]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:10:57.503Z","logger":"kafkajs","message":"[Connection] Connection error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local","broker":"kafka-1.kafka-headless.default.svc.cluster.local:9092","clientId":"my-kafkajs-producer","stack":"Error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local\n    at GetAddrInfoReqWrap.onlookup [as oncomplete] (dns.js:69:26)"}
[[11:10:57.508]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:10:57.508Z","logger":"kafkajs","message":"[Producer] Failed to send messages: Connection error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local","retryCount":1,"retryTime":636}
[[11:10:57.879]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:10:57.879Z","logger":"kafkajs","message":"[Connection] Response Produce(key: 0, version: 7)","broker":"kafka-1.kafka-headless.default.svc.cluster.local:9092","clientId":"my-kafkajs-producer","error":"This server does not host this topic-partition","correlationId":311,"size":55}
[[11:10:58.149]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:10:58.149Z","logger":"kafkajs","message":"[Connection] Response Produce(key: 0, version: 7)","broker":"kafka-1.kafka-headless.default.svc.cluster.local:9092","clientId":"my-kafkajs-producer","error":"This server does not host this topic-partition","correlationId":312,"size":55}
[[11:10:58.415]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:10:58.415Z","logger":"kafkajs","message":"[Connection] Response Produce(key: 0, version: 7)","broker":"kafka-1.kafka-headless.default.svc.cluster.local:9092","clientId":"my-kafkajs-producer","error":"This server does not host this topic-partition","correlationId":313,"size":55}
[[11:10:58.715]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:10:58.714Z","logger":"kafkajs","message":"[Connection] Response Produce(key: 0, version: 7)","broker":"kafka-1.kafka-headless.default.svc.cluster.local:9092","clientId":"my-kafkajs-producer","error":"This server does not host this topic-partition","correlationId":314,"size":55}
[[11:10:59.018]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:10:59.018Z","logger":"kafkajs","message":"[Connection] Response Produce(key: 0, version: 7)","broker":"kafka-1.kafka-headless.default.svc.cluster.local:9092","clientId":"my-kafkajs-producer","error":"This server does not host this topic-partition","correlationId":315,"size":55}
[[11:10:59.327]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:10:59.327Z","logger":"kafkajs","message":"[Connection] Response Produce(key: 0, version: 7)","broker":"kafka-1.kafka-headless.default.svc.cluster.local:9092","clientId":"my-kafkajs-producer","error":"This server does not host this topic-partition","correlationId":316,"size":55}
[[11:10:59.367]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:10:59.367Z","logger":"kafkajs","message":"[Connection] Response Metadata(key: 3, version: 6)","broker":"kafka-1.kafka-headless.default.svc.cluster.local:9092","clientId":"my-kafkajs-producer","error":"Replication-factor is invalid","correlationId":317,"size":60}
[[11:10:59.615]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:10:59.615Z","logger":"kafkajs","message":"[Connection] Response Produce(key: 0, version: 7)","broker":"kafka-1.kafka-headless.default.svc.cluster.local:9092","clientId":"my-kafkajs-producer","error":"This server does not host this topic-partition","correlationId":318,"size":55}
[[11:10:59.931]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:10:59.931Z","logger":"kafkajs","message":"[Connection] Response Produce(key: 0, version: 7)","broker":"kafka-1.kafka-headless.default.svc.cluster.local:9092","clientId":"my-kafkajs-producer","error":"This server does not host this topic-partition","correlationId":319,"size":55}
[[11:11:00.323]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:11:00.323Z","logger":"kafkajs","message":"[Connection] Response Produce(key: 0, version: 7)","broker":"kafka-1.kafka-headless.default.svc.cluster.local:9092","clientId":"my-kafkajs-producer","error":"This server does not host this topic-partition","correlationId":320,"size":55}
[[11:11:00.330]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:11:00.330Z","logger":"kafkajs","message":"[Connection] Response Metadata(key: 3, version: 6)","broker":"kafka-1.kafka-headless.default.svc.cluster.local:9092","clientId":"my-kafkajs-producer","error":"Replication-factor is invalid","correlationId":321,"size":60}
[[11:11:00.666]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:11:00.666Z","logger":"kafkajs","message":"[Connection] Response Produce(key: 0, version: 7)","broker":"kafka-1.kafka-headless.default.svc.cluster.local:9092","clientId":"my-kafkajs-producer","error":"This server does not host this topic-partition","correlationId":322,"size":55}
[[11:11:00.674]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:11:00.674Z","logger":"kafkajs","message":"[Connection] Response Metadata(key: 3, version: 6)","broker":"kafka-1.kafka-headless.default.svc.cluster.local:9092","clientId":"my-kafkajs-producer","error":"Replication-factor is invalid","correlationId":323,"size":60}
[[11:11:01.024]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:11:01.024Z","logger":"kafkajs","message":"[Connection] Response Produce(key: 0, version: 7)","broker":"kafka-1.kafka-headless.default.svc.cluster.local:9092","clientId":"my-kafkajs-producer","error":"This server does not host this topic-partition","correlationId":324,"size":55}
[[11:11:01.392]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:11:01.392Z","logger":"kafkajs","message":"[Connection] Response Produce(key: 0, version: 7)","broker":"kafka-1.kafka-headless.default.svc.cluster.local:9092","clientId":"my-kafkajs-producer","error":"This server does not host this topic-partition","correlationId":325,"size":55}
[[11:11:01.724]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:11:01.724Z","logger":"kafkajs","message":"[Connection] Response Produce(key: 0, version: 7)","broker":"kafka-1.kafka-headless.default.svc.cluster.local:9092","clientId":"my-kafkajs-producer","error":"This server does not host this topic-partition","correlationId":326,"size":55}
[[11:11:01.732]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:11:01.731Z","logger":"kafkajs","message":"[Connection] Response Metadata(key: 3, version: 6)","broker":"kafka-1.kafka-headless.default.svc.cluster.local:9092","clientId":"my-kafkajs-producer","error":"Replication-factor is invalid","correlationId":327,"size":60}
[[11:11:02.124]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:11:02.124Z","logger":"kafkajs","message":"[Connection] Response Produce(key: 0, version: 7)","broker":"kafka-1.kafka-headless.default.svc.cluster.local:9092","clientId":"my-kafkajs-producer","error":"This server does not host this topic-partition","correlationId":328,"size":55}
[[11:11:02.128]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:11:02.128Z","logger":"kafkajs","message":"[Connection] Response Metadata(key: 3, version: 6)","broker":"kafka-1.kafka-headless.default.svc.cluster.local:9092","clientId":"my-kafkajs-producer","error":"Replication-factor is invalid","correlationId":329,"size":60}
[[11:11:02.428]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:11:02.428Z","logger":"kafkajs","message":"[Connection] Response Produce(key: 0, version: 7)","broker":"kafka-1.kafka-headless.default.svc.cluster.local:9092","clientId":"my-kafkajs-producer","error":"This server does not host this topic-partition","correlationId":330,"size":55}
[[11:11:02.434]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:11:02.433Z","logger":"kafkajs","message":"[Connection] Response Metadata(key: 3, version: 6)","broker":"kafka-1.kafka-headless.default.svc.cluster.local:9092","clientId":"my-kafkajs-producer","error":"Replication-factor is invalid","correlationId":331,"size":60}
[[11:11:02.828]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:11:02.827Z","logger":"kafkajs","message":"[Connection] Response Produce(key: 0, version: 7)","broker":"kafka-1.kafka-headless.default.svc.cluster.local:9092","clientId":"my-kafkajs-producer","error":"This server does not host this topic-partition","correlationId":332,"size":55}
[[11:11:02.834]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:11:02.834Z","logger":"kafkajs","message":"[Connection] Response Metadata(key: 3, version: 6)","broker":"kafka-1.kafka-headless.default.svc.cluster.local:9092","clientId":"my-kafkajs-producer","error":"Replication-factor is invalid","correlationId":333,"size":60}
[[11:11:03.228]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:11:03.228Z","logger":"kafkajs","message":"[Connection] Response Produce(key: 0, version: 7)","broker":"kafka-1.kafka-headless.default.svc.cluster.local:9092","clientId":"my-kafkajs-producer","error":"This server does not host this topic-partition","correlationId":334,"size":55}
[[11:11:03.238]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:11:03.238Z","logger":"kafkajs","message":"[Connection] Response Metadata(key: 3, version: 6)","broker":"kafka-1.kafka-headless.default.svc.cluster.local:9092","clientId":"my-kafkajs-producer","error":"Replication-factor is invalid","correlationId":335,"size":60}
[[11:11:03.632]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:11:03.631Z","logger":"kafkajs","message":"[Connection] Response Produce(key: 0, version: 7)","broker":"kafka-1.kafka-headless.default.svc.cluster.local:9092","clientId":"my-kafkajs-producer","error":"This server does not host this topic-partition","correlationId":336,"size":55}
[[11:11:04.006]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:11:04.006Z","logger":"kafkajs","message":"[Connection] Response Produce(key: 0, version: 7)","broker":"kafka-1.kafka-headless.default.svc.cluster.local:9092","clientId":"my-kafkajs-producer","error":"This server does not host this topic-partition","correlationId":337,"size":55}
[[11:11:04.335]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:11:04.334Z","logger":"kafkajs","message":"[Connection] Response Produce(key: 0, version: 7)","broker":"kafka-1.kafka-headless.default.svc.cluster.local:9092","clientId":"my-kafkajs-producer","error":"This server does not host this topic-partition","correlationId":338,"size":55}
[[11:11:04.345]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:11:04.345Z","logger":"kafkajs","message":"[Connection] Response Metadata(key: 3, version: 6)","broker":"kafka-1.kafka-headless.default.svc.cluster.local:9092","clientId":"my-kafkajs-producer","error":"Replication-factor is invalid","correlationId":339,"size":60}
[[11:11:04.740]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:11:04.740Z","logger":"kafkajs","message":"[Connection] Response Produce(key: 0, version: 7)","broker":"kafka-1.kafka-headless.default.svc.cluster.local:9092","clientId":"my-kafkajs-producer","error":"This server does not host this topic-partition","correlationId":340,"size":55}
[[11:11:05.039]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:11:05.039Z","logger":"kafkajs","message":"[Connection] Response Produce(key: 0, version: 7)","broker":"kafka-1.kafka-headless.default.svc.cluster.local:9092","clientId":"my-kafkajs-producer","error":"This server does not host this topic-partition","correlationId":341,"size":55}
```

Logs from broker:

```log
[38;5;6mkafka [38;5;5m11:10:40.08 [0m
[38;5;6mkafka [38;5;5m11:10:40.09 [0m[1mWelcome to the Bitnami kafka container[0m
[38;5;6mkafka [38;5;5m11:10:40.09 [0mSubscribe to project updates by watching [1mhttps://github.com/bitnami/bitnami-docker-kafka[0m
[38;5;6mkafka [38;5;5m11:10:40.09 [0mSubmit issues and feature requests at [1mhttps://github.com/bitnami/bitnami-docker-kafka/issues[0m
[38;5;6mkafka [38;5;5m11:10:40.09 [0m
[38;5;6mkafka [38;5;5m11:10:40.10 [0m[38;5;2mINFO [0m ==> ** Starting Kafka setup **
[38;5;6mkafka [38;5;5m11:10:40.18 [0m[38;5;3mWARN [0m ==> You set the environment variable ALLOW_PLAINTEXT_LISTENER=yes. For safety reasons, do not use this flag in a production environment.
[38;5;6mkafka [38;5;5m11:10:40.20 [0m[38;5;2mINFO [0m ==> Initializing Kafka...
[38;5;6mkafka [38;5;5m11:10:40.20 [0m[38;5;2mINFO [0m ==> No injected configuration files found, creating default config files
[38;5;6mkafka [38;5;5m11:10:40.44 [0m[38;5;2mINFO [0m ==> Configuring Kafka for inter-broker communications with PLAINTEXT authentication.
[38;5;6mkafka [38;5;5m11:10:40.44 [0m[38;5;3mWARN [0m ==> Inter-broker communications are configured as PLAINTEXT. This is not safe for production environments.
[38;5;6mkafka [38;5;5m11:10:40.45 [0m[38;5;2mINFO [0m ==> Configuring Kafka for client communications with PLAINTEXT authentication.
[38;5;6mkafka [38;5;5m11:10:40.46 [0m[38;5;3mWARN [0m ==> Client communications are configured using PLAINTEXT listeners. For safety reasons, do not use this in a production environment.
[38;5;6mkafka [38;5;5m11:10:40.48 [0m[38;5;2mINFO [0m ==> ** Kafka setup finished! **

[38;5;6mkafka [38;5;5m11:10:40.50 [0m[38;5;2mINFO [0m ==> ** Starting Kafka **
[2021-08-05 11:10:41,790] INFO Registered kafka:type=kafka.Log4jController MBean (kafka.utils.Log4jControllerRegistration$)
[2021-08-05 11:10:42,443] INFO Setting -D jdk.tls.rejectClientInitiatedRenegotiation=true to disable client-initiated TLS renegotiation (org.apache.zookeeper.common.X509Util)
[2021-08-05 11:10:42,588] INFO Registered signal handlers for TERM, INT, HUP (org.apache.kafka.common.utils.LoggingSignalHandler)
[2021-08-05 11:10:42,594] INFO starting (kafka.server.KafkaServer)
[2021-08-05 11:10:42,595] INFO Connecting to zookeeper on zookeeper.default.svc.cluster.local (kafka.server.KafkaServer)
[2021-08-05 11:10:42,627] INFO [ZooKeeperClient Kafka server] Initializing a new session to zookeeper.default.svc.cluster.local. (kafka.zookeeper.ZooKeeperClient)
[2021-08-05 11:10:42,634] INFO Client environment:zookeeper.version=3.5.9-83df9301aa5c2a5d284a9940177808c01bc35cef, built on 01/06/2021 20:03 GMT (org.apache.zookeeper.ZooKeeper)
[2021-08-05 11:10:42,634] INFO Client environment:host.name=kafka-1.kafka-headless.default.svc.cluster.local (org.apache.zookeeper.ZooKeeper)
[2021-08-05 11:10:42,634] INFO Client environment:java.version=11.0.12 (org.apache.zookeeper.ZooKeeper)
[2021-08-05 11:10:42,634] INFO Client environment:java.vendor=BellSoft (org.apache.zookeeper.ZooKeeper)
[2021-08-05 11:10:42,634] INFO Client environment:java.home=/opt/bitnami/java (org.apache.zookeeper.ZooKeeper)
[2021-08-05 11:10:42,634] INFO Client environment:java.class.path=/opt/bitnami/kafka/bin/../libs/activation-1.1.1.jar:/opt/bitnami/kafka/bin/../libs/aopalliance-repackaged-2.6.1.jar:/opt/bitnami/kafka/bin/../libs/argparse4j-0.7.0.jar:/opt/bitnami/kafka/bin/../libs/audience-annotations-0.5.0.jar:/opt/bitnami/kafka/bin/../libs/commons-cli-1.4.jar:/opt/bitnami/kafka/bin/../libs/commons-lang3-3.8.1.jar:/opt/bitnami/kafka/bin/../libs/connect-api-2.8.0.jar:/opt/bitnami/kafka/bin/../libs/connect-basic-auth-extension-2.8.0.jar:/opt/bitnami/kafka/bin/../libs/connect-file-2.8.0.jar:/opt/bitnami/kafka/bin/../libs/connect-json-2.8.0.jar:/opt/bitnami/kafka/bin/../libs/connect-mirror-2.8.0.jar:/opt/bitnami/kafka/bin/../libs/connect-mirror-client-2.8.0.jar:/opt/bitnami/kafka/bin/../libs/connect-runtime-2.8.0.jar:/opt/bitnami/kafka/bin/../libs/connect-transforms-2.8.0.jar:/opt/bitnami/kafka/bin/../libs/hk2-api-2.6.1.jar:/opt/bitnami/kafka/bin/../libs/hk2-locator-2.6.1.jar:/opt/bitnami/kafka/bin/../libs/hk2-utils-2.6.1.jar:/opt/bitnami/kafka/bin/../libs/jackson-annotations-2.10.5.jar:/opt/bitnami/kafka/bin/../libs/jackson-core-2.10.5.jar:/opt/bitnami/kafka/bin/../libs/jackson-databind-2.10.5.1.jar:/opt/bitnami/kafka/bin/../libs/jackson-dataformat-csv-2.10.5.jar:/opt/bitnami/kafka/bin/../libs/jackson-datatype-jdk8-2.10.5.jar:/opt/bitnami/kafka/bin/../libs/jackson-jaxrs-base-2.10.5.jar:/opt/bitnami/kafka/bin/../libs/jackson-jaxrs-json-provider-2.10.5.jar:/opt/bitnami/kafka/bin/../libs/jackson-module-jaxb-annotations-2.10.5.jar:/opt/bitnami/kafka/bin/../libs/jackson-module-paranamer-2.10.5.jar:/opt/bitnami/kafka/bin/../libs/jackson-module-scala_2.12-2.10.5.jar:/opt/bitnami/kafka/bin/../libs/jakarta.activation-api-1.2.1.jar:/opt/bitnami/kafka/bin/../libs/jakarta.annotation-api-1.3.5.jar:/opt/bitnami/kafka/bin/../libs/jakarta.inject-2.6.1.jar:/opt/bitnami/kafka/bin/../libs/jakarta.validation-api-2.0.2.jar:/opt/bitnami/kafka/bin/../libs/jakarta.ws.rs-api-2.1.6.jar:/opt/bitnami/kafka/bin/../libs/jakarta.xml.bind-api-2.3.2.jar:/opt/bitnami/kafka/bin/../libs/javassist-3.27.0-GA.jar:/opt/bitnami/kafka/bin/../libs/javax.servlet-api-3.1.0.jar:/opt/bitnami/kafka/bin/../libs/javax.ws.rs-api-2.1.1.jar:/opt/bitnami/kafka/bin/../libs/jaxb-api-2.3.0.jar:/opt/bitnami/kafka/bin/../libs/jersey-client-2.31.jar:/opt/bitnami/kafka/bin/../libs/jersey-common-2.31.jar:/opt/bitnami/kafka/bin/../libs/jersey-container-servlet-2.31.jar:/opt/bitnami/kafka/bin/../libs/jersey-container-servlet-core-2.31.jar:/opt/bitnami/kafka/bin/../libs/jersey-hk2-2.31.jar:/opt/bitnami/kafka/bin/../libs/jersey-media-jaxb-2.31.jar:/opt/bitnami/kafka/bin/../libs/jersey-server-2.31.jar:/opt/bitnami/kafka/bin/../libs/jetty-client-9.4.39.v20210325.jar:/opt/bitnami/kafka/bin/../libs/jetty-continuation-9.4.39.v20210325.jar:/opt/bitnami/kafka/bin/../libs/jetty-http-9.4.39.v20210325.jar:/opt/bitnami/kafka/bin/../libs/jetty-io-9.4.39.v20210325.jar:/opt/bitnami/kafka/bin/../libs/jetty-security-9.4.39.v20210325.jar:/opt/bitnami/kafka/bin/../libs/jetty-server-9.4.39.v20210325.jar:/opt/bitnami/kafka/bin/../libs/jetty-servlet-9.4.39.v20210325.jar:/opt/bitnami/kafka/bin/../libs/jetty-servlets-9.4.39.v20210325.jar:/opt/bitnami/kafka/bin/../libs/jetty-util-9.4.39.v20210325.jar:/opt/bitnami/kafka/bin/../libs/jetty-util-ajax-9.4.39.v20210325.jar:/opt/bitnami/kafka/bin/../libs/jline-3.12.1.jar:/opt/bitnami/kafka/bin/../libs/jopt-simple-5.0.4.jar:/opt/bitnami/kafka/bin/../libs/kafka-clients-2.8.0.jar:/opt/bitnami/kafka/bin/../libs/kafka-log4j-appender-2.8.0.jar:/opt/bitnami/kafka/bin/../libs/kafka-metadata-2.8.0.jar:/opt/bitnami/kafka/bin/../libs/kafka-raft-2.8.0.jar:/opt/bitnami/kafka/bin/../libs/kafka-shell-2.8.0.jar:/opt/bitnami/kafka/bin/../libs/kafka-streams-2.8.0.jar:/opt/bitnami/kafka/bin/../libs/kafka-streams-examples-2.8.0.jar:/opt/bitnami/kafka/bin/../libs/kafka-streams-scala_2.12-2.8.0.jar:/opt/bitnami/kafka/bin/../libs/kafka-streams-test-utils-2.8.0.jar:/opt/bitnami/kafka/bin/../libs/kafka-tools-2.8.0.jar:/opt/bitnami/kafka/bin/../libs/kafka_2.12-2.8.0-sources.jar:/opt/bitnami/kafka/bin/../libs/kafka_2.12-2.8.0.jar:/opt/bitnami/kafka/bin/../libs/log4j-1.2.17.jar:/opt/bitnami/kafka/bin/../libs/lz4-java-1.7.1.jar:/opt/bitnami/kafka/bin/../libs/maven-artifact-3.6.3.jar:/opt/bitnami/kafka/bin/../libs/metrics-core-2.2.0.jar:/opt/bitnami/kafka/bin/../libs/netty-buffer-4.1.62.Final.jar:/opt/bitnami/kafka/bin/../libs/netty-codec-4.1.62.Final.jar:/opt/bitnami/kafka/bin/../libs/netty-common-4.1.62.Final.jar:/opt/bitnami/kafka/bin/../libs/netty-handler-4.1.62.Final.jar:/opt/bitnami/kafka/bin/../libs/netty-resolver-4.1.62.Final.jar:/opt/bitnami/kafka/bin/../libs/netty-transport-4.1.62.Final.jar:/opt/bitnami/kafka/bin/../libs/netty-transport-native-epoll-4.1.62.Final.jar:/opt/bitnami/kafka/bin/../libs/netty-transport-native-unix-common-4.1.62.Final.jar:/opt/bitnami/kafka/bin/../libs/osgi-resource-locator-1.0.3.jar:/opt/bitnami/kafka/bin/../libs/paranamer-2.8.jar:/opt/bitnami/kafka/bin/../libs/plexus-utils-3.2.1.jar:/opt/bitnami/kafka/bin/../libs/reflections-0.9.12.jar:/opt/bitnami/kafka/bin/../libs/rocksdbjni-5.18.4.jar:/opt/bitnami/kafka/bin/../libs/scala-collection-compat_2.12-2.3.0.jar:/opt/bitnami/kafka/bin/../libs/scala-java8-compat_2.12-0.9.1.jar:/opt/bitnami/kafka/bin/../libs/scala-library-2.12.13.jar:/opt/bitnami/kafka/bin/../libs/scala-logging_2.12-3.9.2.jar:/opt/bitnami/kafka/bin/../libs/scala-reflect-2.12.13.jar:/opt/bitnami/kafka/bin/../libs/slf4j-api-1.7.30.jar:/opt/bitnami/kafka/bin/../libs/slf4j-log4j12-1.7.30.jar:/opt/bitnami/kafka/bin/../libs/snappy-java-1.1.8.1.jar:/opt/bitnami/kafka/bin/../libs/zookeeper-3.5.9.jar:/opt/bitnami/kafka/bin/../libs/zookeeper-jute-3.5.9.jar:/opt/bitnami/kafka/bin/../libs/zstd-jni-1.4.9-1.jar (org.apache.zookeeper.ZooKeeper)
[2021-08-05 11:10:42,635] INFO Client environment:java.library.path=/usr/java/packages/lib:/usr/lib64:/lib64:/lib:/usr/lib (org.apache.zookeeper.ZooKeeper)
[2021-08-05 11:10:42,635] INFO Client environment:java.io.tmpdir=/tmp (org.apache.zookeeper.ZooKeeper)
[2021-08-05 11:10:42,635] INFO Client environment:java.compiler=<NA> (org.apache.zookeeper.ZooKeeper)
[2021-08-05 11:10:42,635] INFO Client environment:os.name=Linux (org.apache.zookeeper.ZooKeeper)
[2021-08-05 11:10:42,635] INFO Client environment:os.arch=amd64 (org.apache.zookeeper.ZooKeeper)
[2021-08-05 11:10:42,635] INFO Client environment:os.version=5.10.25-linuxkit (org.apache.zookeeper.ZooKeeper)
[2021-08-05 11:10:42,635] INFO Client environment:user.name=? (org.apache.zookeeper.ZooKeeper)
[2021-08-05 11:10:42,635] INFO Client environment:user.home=? (org.apache.zookeeper.ZooKeeper)
[2021-08-05 11:10:42,635] INFO Client environment:user.dir=/ (org.apache.zookeeper.ZooKeeper)
[2021-08-05 11:10:42,635] INFO Client environment:os.memory.free=1011MB (org.apache.zookeeper.ZooKeeper)
[2021-08-05 11:10:42,635] INFO Client environment:os.memory.max=1024MB (org.apache.zookeeper.ZooKeeper)
[2021-08-05 11:10:42,635] INFO Client environment:os.memory.total=1024MB (org.apache.zookeeper.ZooKeeper)
[2021-08-05 11:10:42,639] INFO Initiating client connection, connectString=zookeeper.default.svc.cluster.local sessionTimeout=18000 watcher=kafka.zookeeper.ZooKeeperClient$ZooKeeperClientWatcher$@40844aab (org.apache.zookeeper.ZooKeeper)
[2021-08-05 11:10:42,645] INFO jute.maxbuffer value is 4194304 Bytes (org.apache.zookeeper.ClientCnxnSocket)
[2021-08-05 11:10:42,652] INFO zookeeper.request.timeout value is 0. feature enabled= (org.apache.zookeeper.ClientCnxn)
[2021-08-05 11:10:42,655] INFO [ZooKeeperClient Kafka server] Waiting until connected. (kafka.zookeeper.ZooKeeperClient)
[2021-08-05 11:10:42,672] INFO Opening socket connection to server zookeeper.default.svc.cluster.local/10.101.132.137:2181. Will not attempt to authenticate using SASL (unknown error) (org.apache.zookeeper.ClientCnxn)
[2021-08-05 11:10:42,684] INFO Socket connection established, initiating session, client: /172.17.0.10:59930, server: zookeeper.default.svc.cluster.local/10.101.132.137:2181 (org.apache.zookeeper.ClientCnxn)
[2021-08-05 11:10:42,695] INFO Session establishment complete on server zookeeper.default.svc.cluster.local/10.101.132.137:2181, sessionid = 0x100030e9f6e0004, negotiated timeout = 18000 (org.apache.zookeeper.ClientCnxn)
[2021-08-05 11:10:42,705] INFO [ZooKeeperClient Kafka server] Connected. (kafka.zookeeper.ZooKeeperClient)
[2021-08-05 11:10:42,832] INFO [feature-zk-node-event-process-thread]: Starting (kafka.server.FinalizedFeatureChangeListener$ChangeNotificationProcessorThread)
[2021-08-05 11:10:43,091] INFO Updated cache from existing <empty> to latest FinalizedFeaturesAndEpoch(features=Features{}, epoch=0). (kafka.server.FinalizedFeatureCache)
[2021-08-05 11:10:43,102] INFO Cluster ID = bfU21jUXTyyvJtH9rWiZHw (kafka.server.KafkaServer)
[2021-08-05 11:10:43,243] INFO KafkaConfig values:
	advertised.host.name = null
	advertised.listeners = INTERNAL://kafka-1.kafka-headless.default.svc.cluster.local:9093,CLIENT://kafka-1.kafka-headless.default.svc.cluster.local:9092
	advertised.port = null
	alter.config.policy.class.name = null
	alter.log.dirs.replication.quota.window.num = 11
	alter.log.dirs.replication.quota.window.size.seconds = 1
	authorizer.class.name =
	auto.create.topics.enable = true
	auto.leader.rebalance.enable = true
	background.threads = 10
	broker.heartbeat.interval.ms = 2000
	broker.id = 1
	broker.id.generation.enable = true
	broker.rack = null
	broker.session.timeout.ms = 9000
	client.quota.callback.class = null
	compression.type = producer
	connection.failed.authentication.delay.ms = 100
	connections.max.idle.ms = 600000
	connections.max.reauth.ms = 0
	control.plane.listener.name = null
	controlled.shutdown.enable = true
	controlled.shutdown.max.retries = 3
	controlled.shutdown.retry.backoff.ms = 5000
	controller.listener.names = null
	controller.quorum.append.linger.ms = 25
	controller.quorum.election.backoff.max.ms = 1000
	controller.quorum.election.timeout.ms = 1000
	controller.quorum.fetch.timeout.ms = 2000
	controller.quorum.request.timeout.ms = 2000
	controller.quorum.retry.backoff.ms = 20
	controller.quorum.voters = []
	controller.quota.window.num = 11
	controller.quota.window.size.seconds = 1
	controller.socket.timeout.ms = 30000
	create.topic.policy.class.name = null
	default.replication.factor = 3
	delegation.token.expiry.check.interval.ms = 3600000
	delegation.token.expiry.time.ms = 86400000
	delegation.token.master.key = null
	delegation.token.max.lifetime.ms = 604800000
	delegation.token.secret.key = null
	delete.records.purgatory.purge.interval.requests = 1
	delete.topic.enable = false
	fetch.max.bytes = 57671680
	fetch.purgatory.purge.interval.requests = 1000
	group.initial.rebalance.delay.ms = 0
	group.max.session.timeout.ms = 1800000
	group.max.size = 2147483647
	group.min.session.timeout.ms = 6000
	host.name =
	initial.broker.registration.timeout.ms = 60000
	inter.broker.listener.name = INTERNAL
	inter.broker.protocol.version = 2.8-IV1
	kafka.metrics.polling.interval.secs = 10
	kafka.metrics.reporters = []
	leader.imbalance.check.interval.seconds = 300
	leader.imbalance.per.broker.percentage = 10
	listener.security.protocol.map = INTERNAL:PLAINTEXT,CLIENT:PLAINTEXT
	listeners = INTERNAL://:9093,CLIENT://:9092
	log.cleaner.backoff.ms = 15000
	log.cleaner.dedupe.buffer.size = 134217728
	log.cleaner.delete.retention.ms = 86400000
	log.cleaner.enable = true
	log.cleaner.io.buffer.load.factor = 0.9
	log.cleaner.io.buffer.size = 524288
	log.cleaner.io.max.bytes.per.second = 1.7976931348623157E308
	log.cleaner.max.compaction.lag.ms = 9223372036854775807
	log.cleaner.min.cleanable.ratio = 0.5
	log.cleaner.min.compaction.lag.ms = 0
	log.cleaner.threads = 1
	log.cleanup.policy = [delete]
	log.dir = /tmp/kafka-logs
	log.dirs = /bitnami/kafka/data
	log.flush.interval.messages = 10000
	log.flush.interval.ms = 1000
	log.flush.offset.checkpoint.interval.ms = 60000
	log.flush.scheduler.interval.ms = 9223372036854775807
	log.flush.start.offset.checkpoint.interval.ms = 60000
	log.index.interval.bytes = 4096
	log.index.size.max.bytes = 10485760
	log.message.downconversion.enable = true
	log.message.format.version = 2.8-IV1
	log.message.timestamp.difference.max.ms = 9223372036854775807
	log.message.timestamp.type = CreateTime
	log.preallocate = false
	log.retention.bytes = 1073741824
	log.retention.check.interval.ms = 300000
	log.retention.hours = 168
	log.retention.minutes = null
	log.retention.ms = null
	log.roll.hours = 168
	log.roll.jitter.hours = 0
	log.roll.jitter.ms = null
	log.roll.ms = null
	log.segment.bytes = 1073741824
	log.segment.delete.delay.ms = 60000
	max.connection.creation.rate = 2147483647
	max.connections = 2147483647
	max.connections.per.ip = 2147483647
	max.connections.per.ip.overrides =
	max.incremental.fetch.session.cache.slots = 1000
	message.max.bytes = 1000012
	metadata.log.dir = null
	metric.reporters = []
	metrics.num.samples = 2
	metrics.recording.level = INFO
	metrics.sample.window.ms = 30000
	min.insync.replicas = 1
	node.id = -1
	num.io.threads = 8
	num.network.threads = 3
	num.partitions = 10
	num.recovery.threads.per.data.dir = 1
	num.replica.alter.log.dirs.threads = null
	num.replica.fetchers = 1
	offset.metadata.max.bytes = 4096
	offsets.commit.required.acks = -1
	offsets.commit.timeout.ms = 5000
	offsets.load.buffer.size = 5242880
	offsets.retention.check.interval.ms = 600000
	offsets.retention.minutes = 10080
	offsets.topic.compression.codec = 0
	offsets.topic.num.partitions = 50
	offsets.topic.replication.factor = 1
	offsets.topic.segment.bytes = 104857600
	password.encoder.cipher.algorithm = AES/CBC/PKCS5Padding
	password.encoder.iterations = 4096
	password.encoder.key.length = 128
	password.encoder.keyfactory.algorithm = null
	password.encoder.old.secret = null
	password.encoder.secret = null
	port = 9092
	principal.builder.class = null
	process.roles = []
	producer.purgatory.purge.interval.requests = 1000
	queued.max.request.bytes = -1
	queued.max.requests = 500
	quota.consumer.default = 9223372036854775807
	quota.producer.default = 9223372036854775807
	quota.window.num = 11
	quota.window.size.seconds = 1
	replica.fetch.backoff.ms = 1000
	replica.fetch.max.bytes = 1048576
	replica.fetch.min.bytes = 1
	replica.fetch.response.max.bytes = 10485760
	replica.fetch.wait.max.ms = 500
	replica.high.watermark.checkpoint.interval.ms = 5000
	replica.lag.time.max.ms = 30000
	replica.selector.class = null
	replica.socket.receive.buffer.bytes = 65536
	replica.socket.timeout.ms = 30000
	replication.quota.window.num = 11
	replication.quota.window.size.seconds = 1
	request.timeout.ms = 30000
	reserved.broker.max.id = 1000
	sasl.client.callback.handler.class = null
	sasl.enabled.mechanisms = [PLAIN, SCRAM-SHA-256, SCRAM-SHA-512]
	sasl.jaas.config = null
	sasl.kerberos.kinit.cmd = /usr/bin/kinit
	sasl.kerberos.min.time.before.relogin = 60000
	sasl.kerberos.principal.to.local.rules = [DEFAULT]
	sasl.kerberos.service.name = null
	sasl.kerberos.ticket.renew.jitter = 0.05
	sasl.kerberos.ticket.renew.window.factor = 0.8
	sasl.login.callback.handler.class = null
	sasl.login.class = null
	sasl.login.refresh.buffer.seconds = 300
	sasl.login.refresh.min.period.seconds = 60
	sasl.login.refresh.window.factor = 0.8
	sasl.login.refresh.window.jitter = 0.05
	sasl.mechanism.controller.protocol = GSSAPI
	sasl.mechanism.inter.broker.protocol =
	sasl.server.callback.handler.class = null
	security.inter.broker.protocol = PLAINTEXT
	security.providers = null
	socket.connection.setup.timeout.max.ms = 30000
	socket.connection.setup.timeout.ms = 10000
	socket.receive.buffer.bytes = 102400
	socket.request.max.bytes = 104857600
	socket.send.buffer.bytes = 102400
	ssl.cipher.suites = []
	ssl.client.auth = none
	ssl.enabled.protocols = [TLSv1.2, TLSv1.3]
	ssl.endpoint.identification.algorithm = https
	ssl.engine.factory.class = null
	ssl.key.password = null
	ssl.keymanager.algorithm = SunX509
	ssl.keystore.certificate.chain = null
	ssl.keystore.key = null
	ssl.keystore.location = null
	ssl.keystore.password = null
	ssl.keystore.type = JKS
	ssl.principal.mapping.rules = DEFAULT
	ssl.protocol = TLSv1.3
	ssl.provider = null
	ssl.secure.random.implementation = null
	ssl.trustmanager.algorithm = PKIX
	ssl.truststore.certificates = null
	ssl.truststore.location = null
	ssl.truststore.password = null
	ssl.truststore.type = JKS
	transaction.abort.timed.out.transaction.cleanup.interval.ms = 10000
	transaction.max.timeout.ms = 900000
	transaction.remove.expired.transaction.cleanup.interval.ms = 3600000
	transaction.state.log.load.buffer.size = 5242880
	transaction.state.log.min.isr = 1
	transaction.state.log.num.partitions = 50
	transaction.state.log.replication.factor = 1
	transaction.state.log.segment.bytes = 104857600
	transactional.id.expiration.ms = 604800000
	unclean.leader.election.enable = false
	zookeeper.clientCnxnSocket = null
	zookeeper.connect = zookeeper.default.svc.cluster.local
	zookeeper.connection.timeout.ms = 6000
	zookeeper.max.in.flight.requests = 10
	zookeeper.session.timeout.ms = 18000
	zookeeper.set.acl = false
	zookeeper.ssl.cipher.suites = null
	zookeeper.ssl.client.enable = false
	zookeeper.ssl.crl.enable = false
	zookeeper.ssl.enabled.protocols = null
	zookeeper.ssl.endpoint.identification.algorithm = HTTPS
	zookeeper.ssl.keystore.location = null
	zookeeper.ssl.keystore.password = null
	zookeeper.ssl.keystore.type = null
	zookeeper.ssl.ocsp.enable = false
	zookeeper.ssl.protocol = TLSv1.2
	zookeeper.ssl.truststore.location = null
	zookeeper.ssl.truststore.password = null
	zookeeper.ssl.truststore.type = null
	zookeeper.sync.time.ms = 2000
 (kafka.server.KafkaConfig)
[2021-08-05 11:10:43,260] INFO KafkaConfig values:
	advertised.host.name = null
	advertised.listeners = INTERNAL://kafka-1.kafka-headless.default.svc.cluster.local:9093,CLIENT://kafka-1.kafka-headless.default.svc.cluster.local:9092
	advertised.port = null
	alter.config.policy.class.name = null
	alter.log.dirs.replication.quota.window.num = 11
	alter.log.dirs.replication.quota.window.size.seconds = 1
	authorizer.class.name =
	auto.create.topics.enable = true
	auto.leader.rebalance.enable = true
	background.threads = 10
	broker.heartbeat.interval.ms = 2000
	broker.id = 1
	broker.id.generation.enable = true
	broker.rack = null
	broker.session.timeout.ms = 9000
	client.quota.callback.class = null
	compression.type = producer
	connection.failed.authentication.delay.ms = 100
	connections.max.idle.ms = 600000
	connections.max.reauth.ms = 0
	control.plane.listener.name = null
	controlled.shutdown.enable = true
	controlled.shutdown.max.retries = 3
	controlled.shutdown.retry.backoff.ms = 5000
	controller.listener.names = null
	controller.quorum.append.linger.ms = 25
	controller.quorum.election.backoff.max.ms = 1000
	controller.quorum.election.timeout.ms = 1000
	controller.quorum.fetch.timeout.ms = 2000
	controller.quorum.request.timeout.ms = 2000
	controller.quorum.retry.backoff.ms = 20
	controller.quorum.voters = []
	controller.quota.window.num = 11
	controller.quota.window.size.seconds = 1
	controller.socket.timeout.ms = 30000
	create.topic.policy.class.name = null
	default.replication.factor = 3
	delegation.token.expiry.check.interval.ms = 3600000
	delegation.token.expiry.time.ms = 86400000
	delegation.token.master.key = null
	delegation.token.max.lifetime.ms = 604800000
	delegation.token.secret.key = null
	delete.records.purgatory.purge.interval.requests = 1
	delete.topic.enable = false
	fetch.max.bytes = 57671680
	fetch.purgatory.purge.interval.requests = 1000
	group.initial.rebalance.delay.ms = 0
	group.max.session.timeout.ms = 1800000
	group.max.size = 2147483647
	group.min.session.timeout.ms = 6000
	host.name =
	initial.broker.registration.timeout.ms = 60000
	inter.broker.listener.name = INTERNAL
	inter.broker.protocol.version = 2.8-IV1
	kafka.metrics.polling.interval.secs = 10
	kafka.metrics.reporters = []
	leader.imbalance.check.interval.seconds = 300
	leader.imbalance.per.broker.percentage = 10
	listener.security.protocol.map = INTERNAL:PLAINTEXT,CLIENT:PLAINTEXT
	listeners = INTERNAL://:9093,CLIENT://:9092
	log.cleaner.backoff.ms = 15000
	log.cleaner.dedupe.buffer.size = 134217728
	log.cleaner.delete.retention.ms = 86400000
	log.cleaner.enable = true
	log.cleaner.io.buffer.load.factor = 0.9
	log.cleaner.io.buffer.size = 524288
	log.cleaner.io.max.bytes.per.second = 1.7976931348623157E308
	log.cleaner.max.compaction.lag.ms = 9223372036854775807
	log.cleaner.min.cleanable.ratio = 0.5
	log.cleaner.min.compaction.lag.ms = 0
	log.cleaner.threads = 1
	log.cleanup.policy = [delete]
	log.dir = /tmp/kafka-logs
	log.dirs = /bitnami/kafka/data
	log.flush.interval.messages = 10000
	log.flush.interval.ms = 1000
	log.flush.offset.checkpoint.interval.ms = 60000
	log.flush.scheduler.interval.ms = 9223372036854775807
	log.flush.start.offset.checkpoint.interval.ms = 60000
	log.index.interval.bytes = 4096
	log.index.size.max.bytes = 10485760
	log.message.downconversion.enable = true
	log.message.format.version = 2.8-IV1
	log.message.timestamp.difference.max.ms = 9223372036854775807
	log.message.timestamp.type = CreateTime
	log.preallocate = false
	log.retention.bytes = 1073741824
	log.retention.check.interval.ms = 300000
	log.retention.hours = 168
	log.retention.minutes = null
	log.retention.ms = null
	log.roll.hours = 168
	log.roll.jitter.hours = 0
	log.roll.jitter.ms = null
	log.roll.ms = null
	log.segment.bytes = 1073741824
	log.segment.delete.delay.ms = 60000
	max.connection.creation.rate = 2147483647
	max.connections = 2147483647
	max.connections.per.ip = 2147483647
	max.connections.per.ip.overrides =
	max.incremental.fetch.session.cache.slots = 1000
	message.max.bytes = 1000012
	metadata.log.dir = null
	metric.reporters = []
	metrics.num.samples = 2
	metrics.recording.level = INFO
	metrics.sample.window.ms = 30000
	min.insync.replicas = 1
	node.id = -1
	num.io.threads = 8
	num.network.threads = 3
	num.partitions = 10
	num.recovery.threads.per.data.dir = 1
	num.replica.alter.log.dirs.threads = null
	num.replica.fetchers = 1
	offset.metadata.max.bytes = 4096
	offsets.commit.required.acks = -1
	offsets.commit.timeout.ms = 5000
	offsets.load.buffer.size = 5242880
	offsets.retention.check.interval.ms = 600000
	offsets.retention.minutes = 10080
	offsets.topic.compression.codec = 0
	offsets.topic.num.partitions = 50
	offsets.topic.replication.factor = 1
	offsets.topic.segment.bytes = 104857600
	password.encoder.cipher.algorithm = AES/CBC/PKCS5Padding
	password.encoder.iterations = 4096
	password.encoder.key.length = 128
	password.encoder.keyfactory.algorithm = null
	password.encoder.old.secret = null
	password.encoder.secret = null
	port = 9092
	principal.builder.class = null
	process.roles = []
	producer.purgatory.purge.interval.requests = 1000
	queued.max.request.bytes = -1
	queued.max.requests = 500
	quota.consumer.default = 9223372036854775807
	quota.producer.default = 9223372036854775807
	quota.window.num = 11
	quota.window.size.seconds = 1
	replica.fetch.backoff.ms = 1000
	replica.fetch.max.bytes = 1048576
	replica.fetch.min.bytes = 1
	replica.fetch.response.max.bytes = 10485760
	replica.fetch.wait.max.ms = 500
	replica.high.watermark.checkpoint.interval.ms = 5000
	replica.lag.time.max.ms = 30000
	replica.selector.class = null
	replica.socket.receive.buffer.bytes = 65536
	replica.socket.timeout.ms = 30000
	replication.quota.window.num = 11
	replication.quota.window.size.seconds = 1
	request.timeout.ms = 30000
	reserved.broker.max.id = 1000
	sasl.client.callback.handler.class = null
	sasl.enabled.mechanisms = [PLAIN, SCRAM-SHA-256, SCRAM-SHA-512]
	sasl.jaas.config = null
	sasl.kerberos.kinit.cmd = /usr/bin/kinit
	sasl.kerberos.min.time.before.relogin = 60000
	sasl.kerberos.principal.to.local.rules = [DEFAULT]
	sasl.kerberos.service.name = null
	sasl.kerberos.ticket.renew.jitter = 0.05
	sasl.kerberos.ticket.renew.window.factor = 0.8
	sasl.login.callback.handler.class = null
	sasl.login.class = null
	sasl.login.refresh.buffer.seconds = 300
	sasl.login.refresh.min.period.seconds = 60
	sasl.login.refresh.window.factor = 0.8
	sasl.login.refresh.window.jitter = 0.05
	sasl.mechanism.controller.protocol = GSSAPI
	sasl.mechanism.inter.broker.protocol =
	sasl.server.callback.handler.class = null
	security.inter.broker.protocol = PLAINTEXT
	security.providers = null
	socket.connection.setup.timeout.max.ms = 30000
	socket.connection.setup.timeout.ms = 10000
	socket.receive.buffer.bytes = 102400
	socket.request.max.bytes = 104857600
	socket.send.buffer.bytes = 102400
	ssl.cipher.suites = []
	ssl.client.auth = none
	ssl.enabled.protocols = [TLSv1.2, TLSv1.3]
	ssl.endpoint.identification.algorithm = https
	ssl.engine.factory.class = null
	ssl.key.password = null
	ssl.keymanager.algorithm = SunX509
	ssl.keystore.certificate.chain = null
	ssl.keystore.key = null
	ssl.keystore.location = null
	ssl.keystore.password = null
	ssl.keystore.type = JKS
	ssl.principal.mapping.rules = DEFAULT
	ssl.protocol = TLSv1.3
	ssl.provider = null
	ssl.secure.random.implementation = null
	ssl.trustmanager.algorithm = PKIX
	ssl.truststore.certificates = null
	ssl.truststore.location = null
	ssl.truststore.password = null
	ssl.truststore.type = JKS
	transaction.abort.timed.out.transaction.cleanup.interval.ms = 10000
	transaction.max.timeout.ms = 900000
	transaction.remove.expired.transaction.cleanup.interval.ms = 3600000
	transaction.state.log.load.buffer.size = 5242880
	transaction.state.log.min.isr = 1
	transaction.state.log.num.partitions = 50
	transaction.state.log.replication.factor = 1
	transaction.state.log.segment.bytes = 104857600
	transactional.id.expiration.ms = 604800000
	unclean.leader.election.enable = false
	zookeeper.clientCnxnSocket = null
	zookeeper.connect = zookeeper.default.svc.cluster.local
	zookeeper.connection.timeout.ms = 6000
	zookeeper.max.in.flight.requests = 10
	zookeeper.session.timeout.ms = 18000
	zookeeper.set.acl = false
	zookeeper.ssl.cipher.suites = null
	zookeeper.ssl.client.enable = false
	zookeeper.ssl.crl.enable = false
	zookeeper.ssl.enabled.protocols = null
	zookeeper.ssl.endpoint.identification.algorithm = HTTPS
	zookeeper.ssl.keystore.location = null
	zookeeper.ssl.keystore.password = null
	zookeeper.ssl.keystore.type = null
	zookeeper.ssl.ocsp.enable = false
	zookeeper.ssl.protocol = TLSv1.2
	zookeeper.ssl.truststore.location = null
	zookeeper.ssl.truststore.password = null
	zookeeper.ssl.truststore.type = null
	zookeeper.sync.time.ms = 2000
 (kafka.server.KafkaConfig)
[2021-08-05 11:10:43,330] INFO [ThrottledChannelReaper-Fetch]: Starting (kafka.server.ClientQuotaManager$ThrottledChannelReaper)
[2021-08-05 11:10:43,332] INFO [ThrottledChannelReaper-Produce]: Starting (kafka.server.ClientQuotaManager$ThrottledChannelReaper)
[2021-08-05 11:10:43,336] INFO [ThrottledChannelReaper-Request]: Starting (kafka.server.ClientQuotaManager$ThrottledChannelReaper)
[2021-08-05 11:10:43,338] INFO [ThrottledChannelReaper-ControllerMutation]: Starting (kafka.server.ClientQuotaManager$ThrottledChannelReaper)
[2021-08-05 11:10:43,443] INFO Loading logs from log dirs ArrayBuffer(/bitnami/kafka/data) (kafka.log.LogManager)
[2021-08-05 11:10:43,447] INFO Skipping recovery for all logs in /bitnami/kafka/data since clean shutdown file was found (kafka.log.LogManager)
[2021-08-05 11:10:43,596] INFO [Log partition=kafkajs-7, dir=/bitnami/kafka/data] Loading producer state till offset 168 with message format version 2 (kafka.log.Log)
[2021-08-05 11:10:43,601] INFO [ProducerStateManager partition=kafkajs-7] Loading producer state from snapshot file 'SnapshotFile(/bitnami/kafka/data/kafkajs-7/00000000000000000168.snapshot,168)' (kafka.log.ProducerStateManager)
[2021-08-05 11:10:43,624] INFO Completed load of Log(dir=/bitnami/kafka/data/kafkajs-7, topic=kafkajs, partition=7, highWatermark=0, lastStableOffset=0, logStartOffset=0, logEndOffset=168) with 1 segments in 155ms (1/18 loaded in /bitnami/kafka/data) (kafka.log.LogManager)
[2021-08-05 11:10:43,634] INFO [Log partition=__consumer_offsets-34, dir=/bitnami/kafka/data] Loading producer state till offset 0 with message format version 2 (kafka.log.Log)
[2021-08-05 11:10:43,640] INFO Completed load of Log(dir=/bitnami/kafka/data/__consumer_offsets-34, topic=__consumer_offsets, partition=34, highWatermark=0, lastStableOffset=0, logStartOffset=0, logEndOffset=0) with 1 segments in 14ms (2/18 loaded in /bitnami/kafka/data) (kafka.log.LogManager)
[2021-08-05 11:10:43,647] INFO [Log partition=__consumer_offsets-30, dir=/bitnami/kafka/data] Loading producer state till offset 0 with message format version 2 (kafka.log.Log)
[2021-08-05 11:10:43,651] INFO Completed load of Log(dir=/bitnami/kafka/data/__consumer_offsets-30, topic=__consumer_offsets, partition=30, highWatermark=0, lastStableOffset=0, logStartOffset=0, logEndOffset=0) with 1 segments in 10ms (3/18 loaded in /bitnami/kafka/data) (kafka.log.LogManager)
[2021-08-05 11:10:43,662] INFO [Log partition=kafkajs-0, dir=/bitnami/kafka/data] Loading producer state till offset 185 with message format version 2 (kafka.log.Log)
[2021-08-05 11:10:43,663] INFO [ProducerStateManager partition=kafkajs-0] Loading producer state from snapshot file 'SnapshotFile(/bitnami/kafka/data/kafkajs-0/00000000000000000185.snapshot,185)' (kafka.log.ProducerStateManager)
[2021-08-05 11:10:43,666] INFO Completed load of Log(dir=/bitnami/kafka/data/kafkajs-0, topic=kafkajs, partition=0, highWatermark=0, lastStableOffset=0, logStartOffset=0, logEndOffset=185) with 1 segments in 14ms (4/18 loaded in /bitnami/kafka/data) (kafka.log.LogManager)
[2021-08-05 11:10:43,672] INFO [Log partition=__consumer_offsets-42, dir=/bitnami/kafka/data] Loading producer state till offset 0 with message format version 2 (kafka.log.Log)
[2021-08-05 11:10:43,676] INFO Completed load of Log(dir=/bitnami/kafka/data/__consumer_offsets-42, topic=__consumer_offsets, partition=42, highWatermark=0, lastStableOffset=0, logStartOffset=0, logEndOffset=0) with 1 segments in 9ms (5/18 loaded in /bitnami/kafka/data) (kafka.log.LogManager)
[2021-08-05 11:10:43,683] INFO [Log partition=__consumer_offsets-2, dir=/bitnami/kafka/data] Loading producer state till offset 0 with message format version 2 (kafka.log.Log)
[2021-08-05 11:10:43,686] INFO Completed load of Log(dir=/bitnami/kafka/data/__consumer_offsets-2, topic=__consumer_offsets, partition=2, highWatermark=0, lastStableOffset=0, logStartOffset=0, logEndOffset=0) with 1 segments in 9ms (6/18 loaded in /bitnami/kafka/data) (kafka.log.LogManager)
[2021-08-05 11:10:43,692] INFO [Log partition=__consumer_offsets-10, dir=/bitnami/kafka/data] Loading producer state till offset 0 with message format version 2 (kafka.log.Log)
[2021-08-05 11:10:43,698] INFO Completed load of Log(dir=/bitnami/kafka/data/__consumer_offsets-10, topic=__consumer_offsets, partition=10, highWatermark=0, lastStableOffset=0, logStartOffset=0, logEndOffset=0) with 1 segments in 12ms (7/18 loaded in /bitnami/kafka/data) (kafka.log.LogManager)
[2021-08-05 11:10:43,736] INFO [Log partition=__consumer_offsets-14, dir=/bitnami/kafka/data] Loading producer state till offset 0 with message format version 2 (kafka.log.Log)
[2021-08-05 11:10:43,740] INFO Completed load of Log(dir=/bitnami/kafka/data/__consumer_offsets-14, topic=__consumer_offsets, partition=14, highWatermark=0, lastStableOffset=0, logStartOffset=0, logEndOffset=0) with 1 segments in 42ms (8/18 loaded in /bitnami/kafka/data) (kafka.log.LogManager)
[2021-08-05 11:10:43,746] INFO [Log partition=__consumer_offsets-6, dir=/bitnami/kafka/data] Loading producer state till offset 0 with message format version 2 (kafka.log.Log)
[2021-08-05 11:10:43,748] INFO Completed load of Log(dir=/bitnami/kafka/data/__consumer_offsets-6, topic=__consumer_offsets, partition=6, highWatermark=0, lastStableOffset=0, logStartOffset=0, logEndOffset=0) with 1 segments in 8ms (9/18 loaded in /bitnami/kafka/data) (kafka.log.LogManager)
[2021-08-05 11:10:43,759] INFO [Log partition=__consumer_offsets-38, dir=/bitnami/kafka/data] Loading producer state till offset 3 with message format version 2 (kafka.log.Log)
[2021-08-05 11:10:43,759] INFO [ProducerStateManager partition=__consumer_offsets-38] Loading producer state from snapshot file 'SnapshotFile(/bitnami/kafka/data/__consumer_offsets-38/00000000000000000003.snapshot,3)' (kafka.log.ProducerStateManager)
[2021-08-05 11:10:43,762] INFO Completed load of Log(dir=/bitnami/kafka/data/__consumer_offsets-38, topic=__consumer_offsets, partition=38, highWatermark=0, lastStableOffset=0, logStartOffset=0, logEndOffset=3) with 1 segments in 13ms (10/18 loaded in /bitnami/kafka/data) (kafka.log.LogManager)
[2021-08-05 11:10:43,772] INFO [Log partition=__consumer_offsets-46, dir=/bitnami/kafka/data] Loading producer state till offset 0 with message format version 2 (kafka.log.Log)
[2021-08-05 11:10:43,775] INFO Completed load of Log(dir=/bitnami/kafka/data/__consumer_offsets-46, topic=__consumer_offsets, partition=46, highWatermark=0, lastStableOffset=0, logStartOffset=0, logEndOffset=0) with 1 segments in 12ms (11/18 loaded in /bitnami/kafka/data) (kafka.log.LogManager)
[2021-08-05 11:10:43,782] INFO [Log partition=kafkajs-2, dir=/bitnami/kafka/data] Loading producer state till offset 168 with message format version 2 (kafka.log.Log)
[2021-08-05 11:10:43,782] INFO [ProducerStateManager partition=kafkajs-2] Loading producer state from snapshot file 'SnapshotFile(/bitnami/kafka/data/kafkajs-2/00000000000000000168.snapshot,168)' (kafka.log.ProducerStateManager)
[2021-08-05 11:10:43,787] INFO Completed load of Log(dir=/bitnami/kafka/data/kafkajs-2, topic=kafkajs, partition=2, highWatermark=0, lastStableOffset=0, logStartOffset=0, logEndOffset=168) with 1 segments in 12ms (12/18 loaded in /bitnami/kafka/data) (kafka.log.LogManager)
[2021-08-05 11:10:43,796] INFO [Log partition=kafkajs-1, dir=/bitnami/kafka/data] Loading producer state till offset 166 with message format version 2 (kafka.log.Log)
[2021-08-05 11:10:43,796] INFO [ProducerStateManager partition=kafkajs-1] Loading producer state from snapshot file 'SnapshotFile(/bitnami/kafka/data/kafkajs-1/00000000000000000166.snapshot,166)' (kafka.log.ProducerStateManager)
[2021-08-05 11:10:43,800] INFO Completed load of Log(dir=/bitnami/kafka/data/kafkajs-1, topic=kafkajs, partition=1, highWatermark=0, lastStableOffset=0, logStartOffset=0, logEndOffset=166) with 1 segments in 13ms (13/18 loaded in /bitnami/kafka/data) (kafka.log.LogManager)
[2021-08-05 11:10:43,811] INFO [Log partition=__consumer_offsets-26, dir=/bitnami/kafka/data] Loading producer state till offset 0 with message format version 2 (kafka.log.Log)
[2021-08-05 11:10:43,815] INFO Completed load of Log(dir=/bitnami/kafka/data/__consumer_offsets-26, topic=__consumer_offsets, partition=26, highWatermark=0, lastStableOffset=0, logStartOffset=0, logEndOffset=0) with 1 segments in 15ms (14/18 loaded in /bitnami/kafka/data) (kafka.log.LogManager)
[2021-08-05 11:10:43,822] INFO [Log partition=kafkajs-6, dir=/bitnami/kafka/data] Loading producer state till offset 187 with message format version 2 (kafka.log.Log)
[2021-08-05 11:10:43,822] INFO [ProducerStateManager partition=kafkajs-6] Loading producer state from snapshot file 'SnapshotFile(/bitnami/kafka/data/kafkajs-6/00000000000000000187.snapshot,187)' (kafka.log.ProducerStateManager)
[2021-08-05 11:10:43,825] INFO Completed load of Log(dir=/bitnami/kafka/data/kafkajs-6, topic=kafkajs, partition=6, highWatermark=0, lastStableOffset=0, logStartOffset=0, logEndOffset=187) with 1 segments in 9ms (15/18 loaded in /bitnami/kafka/data) (kafka.log.LogManager)
[2021-08-05 11:10:43,831] INFO [Log partition=__consumer_offsets-18, dir=/bitnami/kafka/data] Loading producer state till offset 0 with message format version 2 (kafka.log.Log)
[2021-08-05 11:10:43,834] INFO Completed load of Log(dir=/bitnami/kafka/data/__consumer_offsets-18, topic=__consumer_offsets, partition=18, highWatermark=0, lastStableOffset=0, logStartOffset=0, logEndOffset=0) with 1 segments in 9ms (16/18 loaded in /bitnami/kafka/data) (kafka.log.LogManager)
[2021-08-05 11:10:43,840] INFO [Log partition=__consumer_offsets-22, dir=/bitnami/kafka/data] Loading producer state till offset 0 with message format version 2 (kafka.log.Log)
[2021-08-05 11:10:43,842] INFO Completed load of Log(dir=/bitnami/kafka/data/__consumer_offsets-22, topic=__consumer_offsets, partition=22, highWatermark=0, lastStableOffset=0, logStartOffset=0, logEndOffset=0) with 1 segments in 8ms (17/18 loaded in /bitnami/kafka/data) (kafka.log.LogManager)
[2021-08-05 11:10:43,849] INFO [Log partition=kafkajs-4, dir=/bitnami/kafka/data] Loading producer state till offset 167 with message format version 2 (kafka.log.Log)
[2021-08-05 11:10:43,849] INFO [ProducerStateManager partition=kafkajs-4] Loading producer state from snapshot file 'SnapshotFile(/bitnami/kafka/data/kafkajs-4/00000000000000000167.snapshot,167)' (kafka.log.ProducerStateManager)
[2021-08-05 11:10:43,851] INFO Completed load of Log(dir=/bitnami/kafka/data/kafkajs-4, topic=kafkajs, partition=4, highWatermark=0, lastStableOffset=0, logStartOffset=0, logEndOffset=167) with 1 segments in 9ms (18/18 loaded in /bitnami/kafka/data) (kafka.log.LogManager)
[2021-08-05 11:10:43,854] INFO Loaded 18 logs in 411ms. (kafka.log.LogManager)
[2021-08-05 11:10:43,855] INFO Starting log cleanup with a period of 300000 ms. (kafka.log.LogManager)
[2021-08-05 11:10:43,856] INFO Starting log flusher with a default period of 9223372036854775807 ms. (kafka.log.LogManager)
[2021-08-05 11:10:44,508] INFO Updated connection-accept-rate max connection creation rate to 2147483647 (kafka.network.ConnectionQuotas)
[2021-08-05 11:10:44,512] INFO Awaiting socket connections on 0.0.0.0:9093. (kafka.network.Acceptor)
[2021-08-05 11:10:44,561] INFO [SocketServer listenerType=ZK_BROKER, nodeId=1] Created data-plane acceptor and processors for endpoint : ListenerName(INTERNAL) (kafka.network.SocketServer)
[2021-08-05 11:10:44,562] INFO Updated connection-accept-rate max connection creation rate to 2147483647 (kafka.network.ConnectionQuotas)
[2021-08-05 11:10:44,562] INFO Awaiting socket connections on 0.0.0.0:9092. (kafka.network.Acceptor)
[2021-08-05 11:10:44,575] INFO [SocketServer listenerType=ZK_BROKER, nodeId=1] Created data-plane acceptor and processors for endpoint : ListenerName(CLIENT) (kafka.network.SocketServer)
[2021-08-05 11:10:44,625] INFO [broker-1-to-controller-send-thread]: Starting (kafka.server.BrokerToControllerRequestThread)
[2021-08-05 11:10:44,646] INFO [ExpirationReaper-1-Produce]: Starting (kafka.server.DelayedOperationPurgatory$ExpiredOperationReaper)
[2021-08-05 11:10:44,647] INFO [ExpirationReaper-1-Fetch]: Starting (kafka.server.DelayedOperationPurgatory$ExpiredOperationReaper)
[2021-08-05 11:10:44,648] INFO [ExpirationReaper-1-DeleteRecords]: Starting (kafka.server.DelayedOperationPurgatory$ExpiredOperationReaper)
[2021-08-05 11:10:44,649] INFO [ExpirationReaper-1-ElectLeader]: Starting (kafka.server.DelayedOperationPurgatory$ExpiredOperationReaper)
[2021-08-05 11:10:44,668] INFO [LogDirFailureHandler]: Starting (kafka.server.ReplicaManager$LogDirFailureHandler)
[2021-08-05 11:10:44,760] INFO Creating /brokers/ids/1 (is it secure? false) (kafka.zk.KafkaZkClient)
[2021-08-05 11:10:44,786] INFO Stat of the created znode at /brokers/ids/1 is: 4294967989,4294967989,1628161844774,1628161844774,1,0,0,72060955377139716,364,0,4294967989
 (kafka.zk.KafkaZkClient)
[2021-08-05 11:10:44,787] INFO Registered broker 1 at path /brokers/ids/1 with addresses: INTERNAL://kafka-1.kafka-headless.default.svc.cluster.local:9093,CLIENT://kafka-1.kafka-headless.default.svc.cluster.local:9092, czxid (broker epoch): 4294967989 (kafka.zk.KafkaZkClient)
[2021-08-05 11:10:44,887] INFO [ExpirationReaper-1-topic]: Starting (kafka.server.DelayedOperationPurgatory$ExpiredOperationReaper)
[2021-08-05 11:10:44,894] INFO [ExpirationReaper-1-Heartbeat]: Starting (kafka.server.DelayedOperationPurgatory$ExpiredOperationReaper)
[2021-08-05 11:10:44,897] INFO [ExpirationReaper-1-Rebalance]: Starting (kafka.server.DelayedOperationPurgatory$ExpiredOperationReaper)
[2021-08-05 11:10:44,914] INFO [GroupCoordinator 1]: Starting up. (kafka.coordinator.group.GroupCoordinator)
[2021-08-05 11:10:44,936] INFO [GroupCoordinator 1]: Startup complete. (kafka.coordinator.group.GroupCoordinator)
[2021-08-05 11:10:44,973] INFO [ProducerId Manager 1]: Acquired new producerId block (brokerId:1,blockStartProducerId:16000,blockEndProducerId:16999) by writing to Zk with path version 17 (kafka.coordinator.transaction.ProducerIdManager)
[2021-08-05 11:10:44,974] INFO [TransactionCoordinator id=1] Starting up. (kafka.coordinator.transaction.TransactionCoordinator)
[2021-08-05 11:10:44,979] INFO [TransactionCoordinator id=1] Startup complete. (kafka.coordinator.transaction.TransactionCoordinator)
[2021-08-05 11:10:44,980] INFO [Transaction Marker Channel Manager 1]: Starting (kafka.coordinator.transaction.TransactionMarkerChannelManager)
[2021-08-05 11:10:45,010] INFO [ExpirationReaper-1-AlterAcls]: Starting (kafka.server.DelayedOperationPurgatory$ExpiredOperationReaper)
[2021-08-05 11:10:45,036] INFO [/config/changes-event-process-thread]: Starting (kafka.common.ZkNodeChangeNotificationListener$ChangeEventProcessThread)
[2021-08-05 11:10:45,065] INFO [SocketServer listenerType=ZK_BROKER, nodeId=1] Starting socket server acceptors and processors (kafka.network.SocketServer)
[2021-08-05 11:10:45,073] INFO [SocketServer listenerType=ZK_BROKER, nodeId=1] Started data-plane acceptor and processor(s) for endpoint : ListenerName(INTERNAL) (kafka.network.SocketServer)
[2021-08-05 11:10:45,079] INFO [SocketServer listenerType=ZK_BROKER, nodeId=1] Started data-plane acceptor and processor(s) for endpoint : ListenerName(CLIENT) (kafka.network.SocketServer)
[2021-08-05 11:10:45,079] INFO [SocketServer listenerType=ZK_BROKER, nodeId=1] Started socket server acceptors and processors (kafka.network.SocketServer)
[2021-08-05 11:10:45,085] INFO Kafka version: 2.8.0 (org.apache.kafka.common.utils.AppInfoParser)
[2021-08-05 11:10:45,085] INFO Kafka commitId: ebb1d6e21cc92130 (org.apache.kafka.common.utils.AppInfoParser)
[2021-08-05 11:10:45,086] INFO Kafka startTimeMs: 1628161845080 (org.apache.kafka.common.utils.AppInfoParser)
[2021-08-05 11:10:45,087] INFO [KafkaServer id=1] started (kafka.server.KafkaServer)
[2021-08-05 11:10:59,353] INFO [Admin Manager on Broker 1]: Error processing create topic request CreatableTopic(name='kafkajs', numPartitions=10, replicationFactor=3, assignments=[], configs=[]) (kafka.server.ZkAdminManager)
org.apache.kafka.common.errors.InvalidReplicationFactorException: Replication factor: 3 larger than available brokers: 0.
[2021-08-05 11:11:00,326] INFO [Admin Manager on Broker 1]: Error processing create topic request CreatableTopic(name='kafkajs', numPartitions=10, replicationFactor=3, assignments=[], configs=[]) (kafka.server.ZkAdminManager)
org.apache.kafka.common.errors.InvalidReplicationFactorException: Replication factor: 3 larger than available brokers: 0.
[2021-08-05 11:11:00,669] INFO [Admin Manager on Broker 1]: Error processing create topic request CreatableTopic(name='kafkajs', numPartitions=10, replicationFactor=3, assignments=[], configs=[]) (kafka.server.ZkAdminManager)
org.apache.kafka.common.errors.InvalidReplicationFactorException: Replication factor: 3 larger than available brokers: 0.
[2021-08-05 11:11:01,727] INFO [Admin Manager on Broker 1]: Error processing create topic request CreatableTopic(name='kafkajs', numPartitions=10, replicationFactor=3, assignments=[], configs=[]) (kafka.server.ZkAdminManager)
org.apache.kafka.common.errors.InvalidReplicationFactorException: Replication factor: 3 larger than available brokers: 0.
[2021-08-05 11:11:02,125] INFO [Admin Manager on Broker 1]: Error processing create topic request CreatableTopic(name='kafkajs', numPartitions=10, replicationFactor=3, assignments=[], configs=[]) (kafka.server.ZkAdminManager)
org.apache.kafka.common.errors.InvalidReplicationFactorException: Replication factor: 3 larger than available brokers: 0.
[2021-08-05 11:11:02,432] INFO [Admin Manager on Broker 1]: Error processing create topic request CreatableTopic(name='kafkajs', numPartitions=10, replicationFactor=3, assignments=[], configs=[]) (kafka.server.ZkAdminManager)
org.apache.kafka.common.errors.InvalidReplicationFactorException: Replication factor: 3 larger than available brokers: 0.
[2021-08-05 11:11:02,830] INFO [Admin Manager on Broker 1]: Error processing create topic request CreatableTopic(name='kafkajs', numPartitions=10, replicationFactor=3, assignments=[], configs=[]) (kafka.server.ZkAdminManager)
org.apache.kafka.common.errors.InvalidReplicationFactorException: Replication factor: 3 larger than available brokers: 0.
[2021-08-05 11:11:03,233] INFO [Admin Manager on Broker 1]: Error processing create topic request CreatableTopic(name='kafkajs', numPartitions=10, replicationFactor=3, assignments=[], configs=[]) (kafka.server.ZkAdminManager)
org.apache.kafka.common.errors.InvalidReplicationFactorException: Replication factor: 3 larger than available brokers: 0.
[2021-08-05 11:11:04,342] INFO [Admin Manager on Broker 1]: Error processing create topic request CreatableTopic(name='kafkajs', numPartitions=10, replicationFactor=3, assignments=[], configs=[]) (kafka.server.ZkAdminManager)
org.apache.kafka.common.errors.InvalidReplicationFactorException: Replication factor: 3 larger than available brokers: 0.
[2021-08-05 11:11:04,955] INFO [ReplicaFetcherManager on broker 1] Removed fetcher for partitions Set(__consumer_offsets-22, __consumer_offsets-30, __consumer_offsets-46, kafkajs-0, __consumer_offsets-42, __consumer_offsets-18, __consumer_offsets-38, __consumer_offsets-2, __consumer_offsets-6, __consumer_offsets-14, kafkajs-6, __consumer_offsets-26, __consumer_offsets-34, __consumer_offsets-10) (kafka.server.ReplicaFetcherManager)
[2021-08-05 11:11:04,960] INFO [broker-1-to-controller-send-thread]: Recorded new controller, from now on will use broker kafka-2.kafka-headless.default.svc.cluster.local:9093 (id: 2 rack: null) (kafka.server.BrokerToControllerRequestThread)
[2021-08-05 11:11:04,967] INFO [Partition __consumer_offsets-10 broker=1] Log loaded for partition __consumer_offsets-10 with initial high watermark 0 (kafka.cluster.Partition)
[2021-08-05 11:11:04,976] INFO [Partition __consumer_offsets-26 broker=1] Log loaded for partition __consumer_offsets-26 with initial high watermark 0 (kafka.cluster.Partition)
[2021-08-05 11:11:04,980] INFO [Partition __consumer_offsets-42 broker=1] Log loaded for partition __consumer_offsets-42 with initial high watermark 0 (kafka.cluster.Partition)
[2021-08-05 11:11:04,984] INFO [Partition __consumer_offsets-14 broker=1] Log loaded for partition __consumer_offsets-14 with initial high watermark 0 (kafka.cluster.Partition)
[2021-08-05 11:11:04,988] INFO [Partition __consumer_offsets-30 broker=1] Log loaded for partition __consumer_offsets-30 with initial high watermark 0 (kafka.cluster.Partition)
[2021-08-05 11:11:04,993] INFO [Partition __consumer_offsets-46 broker=1] Log loaded for partition __consumer_offsets-46 with initial high watermark 0 (kafka.cluster.Partition)
[2021-08-05 11:11:04,997] INFO [Partition __consumer_offsets-2 broker=1] Log loaded for partition __consumer_offsets-2 with initial high watermark 0 (kafka.cluster.Partition)
[2021-08-05 11:11:05,002] INFO [Partition __consumer_offsets-18 broker=1] Log loaded for partition __consumer_offsets-18 with initial high watermark 0 (kafka.cluster.Partition)
[2021-08-05 11:11:05,006] INFO [Partition __consumer_offsets-34 broker=1] Log loaded for partition __consumer_offsets-34 with initial high watermark 0 (kafka.cluster.Partition)
[2021-08-05 11:11:05,010] INFO [Partition kafkajs-6 broker=1] Log loaded for partition kafkajs-6 with initial high watermark 187 (kafka.cluster.Partition)
[2021-08-05 11:11:05,015] INFO [Partition __consumer_offsets-38 broker=1] Log loaded for partition __consumer_offsets-38 with initial high watermark 3 (kafka.cluster.Partition)
[2021-08-05 11:11:05,018] INFO [Partition __consumer_offsets-6 broker=1] Log loaded for partition __consumer_offsets-6 with initial high watermark 0 (kafka.cluster.Partition)
[2021-08-05 11:11:05,022] INFO [Partition __consumer_offsets-22 broker=1] Log loaded for partition __consumer_offsets-22 with initial high watermark 0 (kafka.cluster.Partition)
[2021-08-05 11:11:05,026] INFO [Partition kafkajs-0 broker=1] Log loaded for partition kafkajs-0 with initial high watermark 185 (kafka.cluster.Partition)
[2021-08-05 11:11:05,067] INFO [Partition kafkajs-7 broker=1] Log loaded for partition kafkajs-7 with initial high watermark 167 (kafka.cluster.Partition)
[2021-08-05 11:11:05,068] INFO [Partition kafkajs-4 broker=1] Log loaded for partition kafkajs-4 with initial high watermark 167 (kafka.cluster.Partition)
[2021-08-05 11:11:05,069] INFO [Partition kafkajs-1 broker=1] Log loaded for partition kafkajs-1 with initial high watermark 166 (kafka.cluster.Partition)
[2021-08-05 11:11:05,070] INFO [Partition kafkajs-2 broker=1] Log loaded for partition kafkajs-2 with initial high watermark 168 (kafka.cluster.Partition)
[2021-08-05 11:11:05,070] INFO [ReplicaFetcherManager on broker 1] Removed fetcher for partitions Set(kafkajs-7, kafkajs-4, kafkajs-2, kafkajs-1) (kafka.server.ReplicaFetcherManager)
[2021-08-05 11:11:05,101] INFO [ReplicaFetcher replicaId=1, leaderId=2, fetcherId=0] Starting (kafka.server.ReplicaFetcherThread)
[2021-08-05 11:11:05,107] INFO [ReplicaFetcherManager on broker 1] Added fetcher to broker 2 for partitions Map(kafkajs-4 -> InitialFetchState(BrokerEndPoint(id=2, host=kafka-2.kafka-headless.default.svc.cluster.local:9093),4,167), kafkajs-2 -> InitialFetchState(BrokerEndPoint(id=2, host=kafka-2.kafka-headless.default.svc.cluster.local:9093),3,168)) (kafka.server.ReplicaFetcherManager)
[2021-08-05 11:11:05,112] INFO [ReplicaFetcherManager on broker 1] Added fetcher to broker 3 for partitions Map(kafkajs-7 -> InitialFetchState(BrokerEndPoint(id=3, host=kafka-3.kafka-headless.default.svc.cluster.local:9093),3,168), kafkajs-1 -> InitialFetchState(BrokerEndPoint(id=3, host=kafka-3.kafka-headless.default.svc.cluster.local:9093),4,166)) (kafka.server.ReplicaFetcherManager)
[2021-08-05 11:11:05,112] INFO [ReplicaFetcher replicaId=1, leaderId=3, fetcherId=0] Starting (kafka.server.ReplicaFetcherThread)
[2021-08-05 11:11:05,120] INFO [GroupCoordinator 1]: Elected as the group coordinator for partition 22 (kafka.coordinator.group.GroupCoordinator)
[2021-08-05 11:11:05,123] INFO [GroupMetadataManager brokerId=1] Scheduling loading of offsets and group metadata from __consumer_offsets-22 (kafka.coordinator.group.GroupMetadataManager)
[2021-08-05 11:11:05,125] INFO [GroupCoordinator 1]: Elected as the group coordinator for partition 34 (kafka.coordinator.group.GroupCoordinator)
[2021-08-05 11:11:05,125] INFO [GroupMetadataManager brokerId=1] Scheduling loading of offsets and group metadata from __consumer_offsets-34 (kafka.coordinator.group.GroupMetadataManager)
[2021-08-05 11:11:05,125] INFO [GroupCoordinator 1]: Elected as the group coordinator for partition 2 (kafka.coordinator.group.GroupCoordinator)
[2021-08-05 11:11:05,125] INFO [GroupMetadataManager brokerId=1] Scheduling loading of offsets and group metadata from __consumer_offsets-2 (kafka.coordinator.group.GroupMetadataManager)
[2021-08-05 11:11:05,126] INFO [GroupCoordinator 1]: Elected as the group coordinator for partition 46 (kafka.coordinator.group.GroupCoordinator)
[2021-08-05 11:11:05,126] INFO [GroupMetadataManager brokerId=1] Scheduling loading of offsets and group metadata from __consumer_offsets-46 (kafka.coordinator.group.GroupMetadataManager)
[2021-08-05 11:11:05,126] INFO [GroupCoordinator 1]: Elected as the group coordinator for partition 14 (kafka.coordinator.group.GroupCoordinator)
[2021-08-05 11:11:05,127] INFO [GroupMetadataManager brokerId=1] Scheduling loading of offsets and group metadata from __consumer_offsets-14 (kafka.coordinator.group.GroupMetadataManager)
[2021-08-05 11:11:05,127] INFO [GroupCoordinator 1]: Elected as the group coordinator for partition 26 (kafka.coordinator.group.GroupCoordinator)
[2021-08-05 11:11:05,127] INFO [GroupMetadataManager brokerId=1] Scheduling loading of offsets and group metadata from __consumer_offsets-26 (kafka.coordinator.group.GroupMetadataManager)
[2021-08-05 11:11:05,127] INFO [GroupCoordinator 1]: Elected as the group coordinator for partition 38 (kafka.coordinator.group.GroupCoordinator)
[2021-08-05 11:11:05,128] INFO [GroupMetadataManager brokerId=1] Scheduling loading of offsets and group metadata from __consumer_offsets-38 (kafka.coordinator.group.GroupMetadataManager)
[2021-08-05 11:11:05,128] INFO [GroupCoordinator 1]: Elected as the group coordinator for partition 6 (kafka.coordinator.group.GroupCoordinator)
[2021-08-05 11:11:05,129] INFO [GroupMetadataManager brokerId=1] Scheduling loading of offsets and group metadata from __consumer_offsets-6 (kafka.coordinator.group.GroupMetadataManager)
[2021-08-05 11:11:05,129] INFO [GroupCoordinator 1]: Elected as the group coordinator for partition 18 (kafka.coordinator.group.GroupCoordinator)
[2021-08-05 11:11:05,129] INFO [GroupMetadataManager brokerId=1] Scheduling loading of offsets and group metadata from __consumer_offsets-18 (kafka.coordinator.group.GroupMetadataManager)
[2021-08-05 11:11:05,129] INFO [GroupCoordinator 1]: Elected as the group coordinator for partition 30 (kafka.coordinator.group.GroupCoordinator)
[2021-08-05 11:11:05,129] INFO [GroupMetadataManager brokerId=1] Scheduling loading of offsets and group metadata from __consumer_offsets-30 (kafka.coordinator.group.GroupMetadataManager)
[2021-08-05 11:11:05,130] INFO [GroupCoordinator 1]: Elected as the group coordinator for partition 42 (kafka.coordinator.group.GroupCoordinator)
[2021-08-05 11:11:05,130] INFO [GroupMetadataManager brokerId=1] Scheduling loading of offsets and group metadata from __consumer_offsets-42 (kafka.coordinator.group.GroupMetadataManager)
[2021-08-05 11:11:05,130] INFO [GroupCoordinator 1]: Elected as the group coordinator for partition 10 (kafka.coordinator.group.GroupCoordinator)
[2021-08-05 11:11:05,131] INFO [GroupMetadataManager brokerId=1] Scheduling loading of offsets and group metadata from __consumer_offsets-10 (kafka.coordinator.group.GroupMetadataManager)
[2021-08-05 11:11:05,139] INFO [GroupMetadataManager brokerId=1] Finished loading offsets and group metadata from __consumer_offsets-22 in 16 milliseconds, of which 2 milliseconds was spent in the scheduler. (kafka.coordinator.group.GroupMetadataManager)
[2021-08-05 11:11:05,150] INFO [GroupMetadataManager brokerId=1] Finished loading offsets and group metadata from __consumer_offsets-34 in 25 milliseconds, of which 25 milliseconds was spent in the scheduler. (kafka.coordinator.group.GroupMetadataManager)
[2021-08-05 11:11:05,157] INFO [GroupMetadataManager brokerId=1] Finished loading offsets and group metadata from __consumer_offsets-2 in 32 milliseconds, of which 32 milliseconds was spent in the scheduler. (kafka.coordinator.group.GroupMetadataManager)
[2021-08-05 11:11:05,158] INFO [GroupMetadataManager brokerId=1] Finished loading offsets and group metadata from __consumer_offsets-46 in 32 milliseconds, of which 31 milliseconds was spent in the scheduler. (kafka.coordinator.group.GroupMetadataManager)
[2021-08-05 11:11:05,158] INFO [GroupMetadataManager brokerId=1] Finished loading offsets and group metadata from __consumer_offsets-14 in 31 milliseconds, of which 31 milliseconds was spent in the scheduler. (kafka.coordinator.group.GroupMetadataManager)
[2021-08-05 11:11:05,159] INFO [GroupMetadataManager brokerId=1] Finished loading offsets and group metadata from __consumer_offsets-26 in 32 milliseconds, of which 31 milliseconds was spent in the scheduler. (kafka.coordinator.group.GroupMetadataManager)
[2021-08-05 11:11:05,203] INFO Loaded member MemberMetadata(memberId=consumer-console-consumer-30176-1-5cffb2a6-6406-4b2c-b0c2-cdbec8b61444, groupInstanceId=None, clientId=consumer-console-consumer-30176-1, clientHost=/172.17.0.13, sessionTimeoutMs=10000, rebalanceTimeoutMs=300000, supportedProtocols=List(range), ) in group console-consumer-30176 with generation 1. (kafka.coordinator.group.GroupMetadata$)
[2021-08-05 11:11:05,208] INFO [GroupMetadataManager brokerId=1] Finished loading offsets and group metadata from __consumer_offsets-38 in 80 milliseconds, of which 31 milliseconds was spent in the scheduler. (kafka.coordinator.group.GroupMetadataManager)
[2021-08-05 11:11:05,209] INFO [GroupMetadataManager brokerId=1] Finished loading offsets and group metadata from __consumer_offsets-6 in 80 milliseconds, of which 80 milliseconds was spent in the scheduler. (kafka.coordinator.group.GroupMetadataManager)
[2021-08-05 11:11:05,209] INFO [GroupMetadataManager brokerId=1] Finished loading offsets and group metadata from __consumer_offsets-18 in 80 milliseconds, of which 80 milliseconds was spent in the scheduler. (kafka.coordinator.group.GroupMetadataManager)
[2021-08-05 11:11:05,210] INFO [GroupMetadataManager brokerId=1] Finished loading offsets and group metadata from __consumer_offsets-30 in 81 milliseconds, of which 80 milliseconds was spent in the scheduler. (kafka.coordinator.group.GroupMetadataManager)
[2021-08-05 11:11:05,210] INFO [GroupMetadataManager brokerId=1] Finished loading offsets and group metadata from __consumer_offsets-42 in 80 milliseconds, of which 80 milliseconds was spent in the scheduler. (kafka.coordinator.group.GroupMetadataManager)
[2021-08-05 11:11:05,210] INFO [GroupMetadataManager brokerId=1] Finished loading offsets and group metadata from __consumer_offsets-10 in 79 milliseconds, of which 79 milliseconds was spent in the scheduler. (kafka.coordinator.group.GroupMetadataManager)
[2021-08-05 11:11:05,930] INFO [Partition kafkajs-0 broker=1] ISR updated to 1,2 and version updated to [5] (kafka.cluster.Partition)
[2021-08-05 11:11:05,949] INFO [Partition kafkajs-6 broker=1] ISR updated to 1,2 and version updated to [5] (kafka.cluster.Partition)
[2021-08-05 11:11:05,960] INFO [Partition kafkajs-0 broker=1] ISR updated to 1,2,3 and version updated to [6] (kafka.cluster.Partition)
[2021-08-05 11:11:06,067] INFO [Partition kafkajs-6 broker=1] ISR updated to 1,2,3 and version updated to [6] (kafka.cluster.Partition)
[2021-08-05 11:15:56,370] INFO [ReplicaFetcherManager on broker 1] Removed fetcher for partitions Set(kafkajs-7) (kafka.server.ReplicaFetcherManager)
[2021-08-05 11:15:56,377] INFO [ReplicaFetcherManager on broker 1] Added fetcher to broker 0 for partitions Map(kafkajs-7 -> InitialFetchState(BrokerEndPoint(id=0, host=kafka-0.kafka-headless.default.svc.cluster.local:9093),4,609)) (kafka.server.ReplicaFetcherManager)
[2021-08-05 11:15:56,378] INFO [ReplicaFetcher replicaId=1, leaderId=0, fetcherId=0] Starting (kafka.server.ReplicaFetcherThread)
```


When we get the first error:

```log
[[11:10:30.462]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:10:30.462Z","logger":"kafkajs","message":"[Producer] Failed to send messages: Connection error: getaddrinfo ENOTFOUND kafka-1.kafka-headless.default.svc.cluster.local","retryCount":0,"retryTime":351}
```

The KafkaJS [code](https://github.com/tulios/kafkajs/blob/6f490be0f9a186539d6e5a3c572bddc3640f58f8/src/producer/sendMessages.js#L154) is supposed to refreshMedata:

```js
// This is necessary in case the metadata is stale and the number of partitions
// for this topic has increased in the meantime
if (
  staleMetadata(e) ||
  e.name === 'KafkaJSMetadataNotLoaded' ||
  e.name === 'KafkaJSConnectionError' ||
  e.name === 'KafkaJSConnectionClosedError' ||
  (e.name === 'KafkaJSProtocolError' && e.retriable)
) {
  logger.error(`Failed to send messages: ${e.message}`, { retryCount, retryTime })
  await cluster.refreshMetadata()
  throw e
}
```

Then it keeps retrying until `11:11:05`:

```log
[[11:11:05.039]] [ERROR] {"level":"ERROR","timestamp":"2021-08-05T11:11:05.039Z","logger":"kafkajs","message":"[Connection] Response Produce(key: 0, version: 7)","broker":"kafka-1.kafka-headless.default.svc.cluster.local:9092","clientId":"my-kafkajs-producer","error":"This server does not host this topic-partition","correlationId":341,"size":55}
```

Which seems to correspond to the time when kafka-1 is up again and leader for the partitions:

```log
[2021-08-05 11:11:05,930] INFO [Partition kafkajs-0 broker=1] ISR updated to 1,2 and version updated to [5] (kafka.cluster.Partition)
[2021-08-05 11:11:05,949] INFO [Partition kafkajs-6 broker=1] ISR updated to 1,2 and version updated to [5] (kafka.cluster.Partition)
[2021-08-05 11:11:05,960] INFO [Partition kafkajs-0 broker=1] ISR updated to 1,2,3 and version updated to [6] (kafka.cluster.Partition)
[2021-08-05 11:11:06,067] INFO [Partition kafkajs-6 broker=1] ISR updated to 1,2,3 and version updated to [6] (kafka.cluster.Partition)
```

Logs are [here](https://github.com/vdesabou/kafka-docker-playground/blob/master/other/client-kafkajs/notes-minikube.zip?raw=true)