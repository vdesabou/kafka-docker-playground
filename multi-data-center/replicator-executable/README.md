# Using Confluent Replicator as executable



## Objective

[Run Replicator as an Executable](https://docs.confluent.io/current/multi-dc-replicator/replicator-run.html#run-crep-as-an-executable)

## Description

We have 2 regions: `US` and `EUROPE` each have a topic with sales that happened regionaly.
We want on each region to have a way to see **all** sales in **all** regions.

## How to run

With no security in place (PLAINTEXT):

```
$ playground run -f executable-plaintext<use tab key to activate fzf completion (see https://kafka-docker-playground.io/#/cli?id=%e2%9a%a1-setup-completion), otherwise use full path, or correct relative path>
```

With no SSL encryption, SASL/PLAIN authentication:

```
$ playground run -f executable-sasl-plain<use tab key to activate fzf completion (see https://kafka-docker-playground.io/#/cli?id=%e2%9a%a1-setup-completion), otherwise use full path, or correct relative path>
```

With no SSL encryption, Kerberos GSSAPI authentication:

```
$ playground run -f executable-kerberos<use tab key to activate fzf completion (see https://kafka-docker-playground.io/#/cli?id=%e2%9a%a1-setup-completion), otherwise use full path, or correct relative path>
```
