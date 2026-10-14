# Test Confluent for Kubernetes with Confluent Cloud

## Objective

Quickly test [Confluent for Kubernetes](https://docs.confluent.io/operator/current/co-quickstart.html#co-long-quickstart) with Confluent Cloud: Connect, ksqlDB and Control Center run in Minikube and use the Confluent Cloud Kafka cluster and Schema Registry.

Based on [hybrid/ccloud-integration](https://github.com/confluentinc/confluent-kubernetes-examples/tree/master/hybrid/ccloud-integration).

## Prerequisites

See [Confluent Cloud examples](https://kafka-docker-playground.io/#/how-to-use?id=%f0%9f%8c%a4%ef%b8%8f-confluent-cloud-examples).

`kubectl`, `minikube` and `helm` must be installed. Minikube is started with 8 CPUs and 16 GB of memory.

## How to run

```bash
playground run -f start.sh
```

| Script | Description |
| --- | --- |
| `start.sh` | Confluent for Kubernetes on Minikube, connected to Confluent Cloud |

## What the script does

1. Bootstraps the Confluent Cloud environment.
2. Deletes any existing Minikube cluster, starts a new one and launches the Minikube dashboard.
3. Creates namespace `confluent` and installs the Confluent for Kubernetes operator with Helm.
4. Generates a CA pair and creates the `ca-pair-sslcerts` TLS secret.
5. Creates the `cloud-plain`, `cloud-sr-access` and `control-center-user` secrets from the Confluent Cloud and Schema Registry credentials.
6. Generates `confluent-platform.yaml` (Connect, ksqlDB, Control Center) from `confluent-platform-template.yaml`, applies it and waits up to 900 seconds for all pods to be ready.
7. Port-forwards Control Center to [http://127.0.0.1:9021](http://127.0.0.1:9021).
