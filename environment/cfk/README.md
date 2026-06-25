# CFK On Minikube

## Description

- starts minikube
- installs CFK via Helm

This is a deployment with no security:

* 1 zookeeper
* 1 broker
* 1 connect
* 1 schema-registry
* 1 ksqldb-server
* 1 ksqldb-cli
* 1 control-center


## How to run

Simply run:

```
$ just use <playground run> command and search for start.sh in this folder
```