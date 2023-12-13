# HTTP Source connector

## ❗ WARNING ❗

This is a Fully Managed connector only. Running it locally is only possible for Confluent employees.

## Objective

Quickly test [HTTP Source](https://docs.confluent.io/cloud/current/connectors/cc-http-source.html) connector using self-managed version.

The HTTP service is using [vdesabou/kafka-connect-http-demo](https://github.com/vdesabou/kafka-connect-http-demo).

## How to run


### No Authentication

```bash
$ playground run -f http-source-no-auth<use tab key to activate fzf completion (see https://kafka-docker-playground.io/#/cli?id=%e2%9a%a1-setup-completion), otherwise use full path, or relative path>
```
