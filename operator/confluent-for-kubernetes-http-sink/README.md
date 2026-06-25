# CFK HTTP Sink On Minikube

This example reproduces the flow from `connect/connect-http-sink/http_no_auth.sh` with Confluent for Kubernetes on minikube, including the mock HTTP server.

## Run

```bash
cd operator/confluent-for-kubernetes-http-sink
chmod +x start.sh stop.sh
./start.sh
```

## What it does

- starts minikube
- installs CFK via Helm
- builds a custom Connect image with HTTP Sink connector plugin
- builds and deploys the same HTTP mock server used by the Docker example
- creates `http-sink` connector against `http://httpserver:9006`
- verifies 10 records in `success-responses`

## Stop

```bash
./stop.sh
```
