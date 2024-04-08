# .NET client (producer/consumer) (using Confluent Cloud)

## Objective

Quickly test [.NET example](https://github.com/confluentinc/examples/tree/5.4.0-post/clients/cloud/csharp) client using Confluent Cloud

## Prerequisites

See [here](https://kafka-docker-playground.io/#/how-to-use?id=%f0%9f%8c%a4%ef%b8%8f-confluent-cloud-examples)

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
$ just use <playground run> command and search for start<use tab key to activate fzf completion (see https://kafka-docker-playground.io/#/cli?id=%e2%9a%a1-setup-completion), otherwise use full path, or correct relative path> .sh in this folder
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