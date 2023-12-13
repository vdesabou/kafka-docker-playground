# SASL/SCRAM-SHA-256

## Description

This is a deployment with no encryption but with SASL/SCRAM-SHA-256 authentication:

* 1 zookeeper
* 1 broker
* 1 connect
* 1 schema-registry
* 1 control-center

## How to run

Simply run:

```
$ playground run -f start<use tab key to activate [fzf completion](https://kafka-docker-playground.io/#/cli?id=%e2%9a%a1-setup-completion) (otherwise use full path, i.e *not relative path*>
```
