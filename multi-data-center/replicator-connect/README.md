# Using Confluent Replicator as connector

## Description

This is the very good example from [MDC and single views 🌍](https://github.com/framiere/mdc-with-replicator-and-regexrouter)

We have 2 regions: `US` and `EUROPE` each have a topic with sales that happened regionaly.
We want on each region to have a way to see **all** sales in **all** regions.

## How to run

With no security in place (PLAINTEXT):

```
$ playground run -f connect-plaintext<use tab key to activate [fzf completion](https://kafka-docker-playground.io/#/cli?id=%e2%9a%a1-setup-completion) (otherwise use full path, i.e *not relative path*>
```

With no SSL encryption, SASL/PLAIN authentication:

```
$ playground run -f connect-sasl-plain<use tab key to activate [fzf completion](https://kafka-docker-playground.io/#/cli?id=%e2%9a%a1-setup-completion) (otherwise use full path, i.e *not relative path*>
```

With no SSL encryption, Kerberos GSSAPI authentication:

```
$ playground run -f connect-kerberos<use tab key to activate [fzf completion](https://kafka-docker-playground.io/#/cli?id=%e2%9a%a1-setup-completion) (otherwise use full path, i.e *not relative path*>
```
