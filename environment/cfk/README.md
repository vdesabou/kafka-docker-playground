# CFK on k3d

## Description

- starts (or reuses) the k3d cluster `playground-cfk`
- installs Confluent for Kubernetes (CFK) with Helm (`CFK_VERSION`, default 3.3.0), kept between runs
- deploys the custom resources of [confluent-platform.yaml](confluent-platform.yaml) in namespace `confluent`

This is a deployment with no security (see [cfk-rbac](../cfk-rbac/) for the same deployment with RBAC):

* 1 KRaft controller
* 1 broker
* 1 connect
* 1 schema-registry
* optionally: control-center (`--enable-control-center`), ksqldb-server (`--enable-ksqldb`), rest-proxy (`--enable-rest-proxy`)

See the deep dive [Confluent for Kubernetes](https://kafka-docker-playground.io/#/deep-dive-cfk): how the example's
compose override is translated, what each `playground` command does on Kubernetes, support bundles.

## How to run

Run a connector example on it:

```bash
playground run -f connect/connect-filestream-sink/filestream-sink.sh --environment cfk
```

or start it without an example:

```bash
playground start-environment --environment cfk
```
