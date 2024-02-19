# .NET client (producer/consumer) (using Confluent Cloud)

## Objective

Quickly test [.NET example](https://github.com/confluentinc/examples/tree/5.4.0-post/clients/cloud/csharp) client using Confluent Cloud

## Prerequisites

All you have to do is to be already logged in with [confluent CLI](https://docs.confluent.io/confluent-cli/current/overview.html#confluent-cli-overview).

By default, a new Confluent Cloud environment with a Cluster will be created.

You can configure the cluster by setting environment variables:

* `CLUSTER_CLOUD`: The Cloud provider (possible values: `aws`, `gcp` and `azure`, default `aws`)
* `CLUSTER_REGION`: The Cloud region (use `confluent kafka region list` to get the list, default `eu-west-2`)
* `CLUSTER_TYPE`: The type of cluster (possible values: `basic`, `standard` and `dedicated`, default `basic`)
* `ENVIRONMENT` (optional): The environment id where want your new cluster (example: `env-xxxxx`) 

In case you want to use your own existing cluster, you need to setup these environment variables:

* `ENVIRONMENT`: The environment id where your cluster is located (example: `env-xxxxx`) 
* `CLUSTER_NAME`: The cluster name
* `CLUSTER_CLOUD`: The Cloud provider (possible values: `aws`, `gcp` and `azure`)
* `CLUSTER_REGION`: The Cloud region (example `us-east-2`)
* `CLUSTER_CREDS`: The Kafka api key and secret to use, it should be separated with colon (example: `<API_KEY>:<API_KEY_SECRET>`)
* `SCHEMA_REGISTRY_CREDS` (optional, if not set, new one will be created): The Schema Registry api key and secret to use, it should be separated with colon (example: `<SR_API_KEY>:<SR_API_KEY_SECRET>`)

## How to run

1. Create `$HOME/.confluent/config`

On the host from which you are running Docker, ensure that you have properly initialized Confluent Cloud CLI and have a valid configuration file at `$HOME/.confluent/config`.

Example:

```bash
$ cat $HOME/.confluent/config
bootstrap.servers=<BROKER ENDPOINT>
ssl.endpoint.identification.algorithm=https
security.protocol=SASL_SSL
sasl.mechanism=PLAIN
sasl.jaas.config=org.apache.kafka.common.security.plain.PlainLoginModule required username="<API KEY>" password="<API SECRET>";
```

2. Simply run:

```
$ playground run -f start<use tab key to activate fzf completion (see https://kafka-docker-playground.io/#/cli?id=%e2%9a%a1-setup-completion), otherwise use full path, or correct relative path> <2.2 or 3.1> (Core .NET version, default is 2.1)
```

## Details of what the script is doing

Building docker image

```bash
$ docker build --build-arg CORE_RUNTIME_TAG=$CORE_RUNTIME_TAG --build-arg CORE_SDK_TAG=$CORE_SDK_TAG --build-arg CSPROJ_FILE=$CSPROJ_FILE -t vdesabou/dotnet-ccloud-example-docker .
```

Starting producer

```bash
$ docker run --name dotnet-ccloud-producer --sysctl net.ipv4.tcp_keepalive_time=60 --sysctl net.ipv4.tcp_keepalive_intvl=30 -v ${DIR}/librdkafka.config:/tmp/librdkafka.config -e TAG=$TAG vdesabou/dotnet-ccloud-example-docker produce client_dotnet_$TAG /tmp/librdkafka.config
```

Note: `librdkafka.config`is generated from your `$HOME/.confluent/config`

Starting consumer. Logs are in /tmp/result.log

```bash
$ docker run --name dotnet-ccloud-consumer --sysctl net.ipv4.tcp_keepalive_time=60 --sysctl net.ipv4.tcp_keepalive_intvl=30 -v ${DIR}/librdkafka.config:/tmp/librdkafka.config -e TAG=$TAG vdesabou/dotnet-ccloud-example-docker consume client_dotnet_$TAG /tmp/librdkafka.config > /tmp/result.log 2>&1 &
```

## Notes on using Minikube with unsafe systctls

Run Minikube:

```bash
$ minikube start --cpus 4 --memory=8G --extra-config="kubelet.allowed-unsafe-sysctls=net.ipv4.tcp_keepalive_time,net.ipv4.tcp_keepalive_intvl"
$ minikube dashboard
```

Notice the config `kubelet.allowed-unsafe-sysctls`to allow unsafe sysctls.

Build Docker image within minikube (explanations [here](https://dzone.com/articles/running-local-docker-images-in-kubernetes-1)):


```bash
$ eval $(minikube docker-env)

$ CORE_RUNTIME_TAG="3.1.2-bionic"
$ CORE_SDK_TAG="3.1.102-bionic"
$ CSPROJ_FILE="CCloud3.1.csproj"

$ docker build --build-arg CORE_RUNTIME_TAG=$CORE_RUNTIME_TAG --build-arg CORE_SDK_TAG=$CORE_SDK_TAG --build-arg CSPROJ_FILE=$CSPROJ_FILE -t vdesabou/dotnet-ccloud-example-docker -f Dockerfile-Minikube .
```

Create namespace:

```bash
$ kubectl create namespace dotnet-ccloud-example-docker
```

Run pod:

```bash
$ kubectl apply -f pod.yml --namespace=dotnet-ccloud-example-docker
```

## Notes on using Minikube with initContainers

Run Minikube:

```bash
$ minikube start --cpus 4 --memory=8G
$ minikube dashboard
```

Build Docker image within minikube (explanations [here](https://dzone.com/articles/running-local-docker-images-in-kubernetes-1)):


```bash
$ eval $(minikube docker-env)

$ CORE_RUNTIME_TAG="3.1.2-bionic"
$ CORE_SDK_TAG="3.1.102-bionic"
$ CSPROJ_FILE="CCloud3.1.csproj"

$ docker build --build-arg CORE_RUNTIME_TAG=$CORE_RUNTIME_TAG --build-arg CORE_SDK_TAG=$CORE_SDK_TAG --build-arg CSPROJ_FILE=$CSPROJ_FILE -t vdesabou/dotnet-ccloud-example-docker -f Dockerfile-Minikube .
```

Create namespace:

```bash
$ kubectl create namespace dotnet-ccloud-example-docker
```

Run pod:

```bash
$ kubectl apply -f pod_initContainers.yml --namespace=dotnet-ccloud-example-docker
```