# .NET client (producer/consumer) (using Confluent Cloud)

## Objective

Quickly test the [.NET example](https://github.com/confluentinc/examples/tree/5.4.0-post/clients/cloud/csharp) client using Confluent Cloud.

## Prerequisites

See [Confluent Cloud examples](https://kafka-docker-playground.io/#/how-to-use?id=%f0%9f%8c%a4%ef%b8%8f-confluent-cloud-examples).

## How to run

```bash
playground run -f start.sh
```

| Script | Description |
| --- | --- |
| `start.sh` | .NET producer and consumer running in Docker containers against Confluent Cloud |

The script uses .NET Core 3.1 by default (`CCloud3.1.csproj`). Set `CORE_DOT_VERSION` to any other value (for example `export CORE_DOT_VERSION=2.2`) to switch to .NET Core 2.2 (`CCloud2.2.csproj`).

## What the script does

1. Bootstraps the Confluent Cloud environment and generates `librdkafka.config` from `librdkafka.config.template` with the cluster bootstrap servers and API key.
2. Recreates topic `client_dotnet_<TAG>` with `playground topic delete` / `playground topic create`.
3. Builds the `vdesabou/dotnet-ccloud-example-docker` image.
4. Runs the producer container `dotnet-ccloud-producer` (with `net.ipv4.tcp_keepalive_time=60` and `net.ipv4.tcp_keepalive_intvl=30` sysctls).
5. Runs the consumer container `dotnet-ccloud-consumer` in the background, with logs in `/tmp/result.log`, and checks that the consumed records contain `alice`.

## Notes on using Minikube with unsafe sysctls

Run Minikube, with `kubelet.allowed-unsafe-sysctls` to allow unsafe sysctls:

```bash
minikube start --cpus 4 --memory=8G --extra-config="kubelet.allowed-unsafe-sysctls=net.ipv4.tcp_keepalive_time,net.ipv4.tcp_keepalive_intvl"
minikube dashboard
```

Build the Docker image within Minikube (explanations [here](https://dzone.com/articles/running-local-docker-images-in-kubernetes-1)):

```bash
eval $(minikube docker-env)

CORE_RUNTIME_TAG="3.1.2-bionic"
CORE_SDK_TAG="3.1.102-bionic"
CSPROJ_FILE="CCloud3.1.csproj"

docker build --build-arg CORE_RUNTIME_TAG=$CORE_RUNTIME_TAG --build-arg CORE_SDK_TAG=$CORE_SDK_TAG --build-arg CSPROJ_FILE=$CSPROJ_FILE -t vdesabou/dotnet-ccloud-example-docker -f Dockerfile-Minikube .
```

Create the namespace and run the pod:

```bash
kubectl create namespace dotnet-ccloud-example-docker
kubectl apply -f pod.yml --namespace=dotnet-ccloud-example-docker
```

## Notes on using Minikube with initContainers

Run Minikube:

```bash
minikube start --cpus 4 --memory=8G
minikube dashboard
```

Build the Docker image within Minikube as above (`Dockerfile-Minikube`), then create the namespace and run the pod:

```bash
kubectl create namespace dotnet-ccloud-example-docker
kubectl apply -f pod_initContainers.yml --namespace=dotnet-ccloud-example-docker
```
