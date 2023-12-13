# Multi Data Center PLAINTEXT

## Description

This is a deployment with no security, it has 2 clusters: `europe` and `us`:

For each cluster, we have:

* 1 zookeeper
* 1 broker
* 1 connect


control-center is monitoring the two clusters

N.B: we have dedicated zookepper and broker for metrics.

## How to run

Simply run:

```
$ playground run -f start<use tab key to activate [fzf completion](https://kafka-docker-playground.io/#/cli?id=%e2%9a%a1-setup-completion) (otherwise use full path, i.e *not relative path*>
```

## Credits

All credits to @framiere with repository [MDC and single views](https://github.com/framiere/mdc-with-replicator-and-regexrouter)