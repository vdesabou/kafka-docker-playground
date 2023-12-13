# Kerberos

## Description

This is a deployment with no SSL encryption, and Kerberos GSSAPI authentication:

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
$ playground run -f start<use tab key to activate fzf completion (see https://kafka-docker-playground.io/#/cli?id=%e2%9a%a1-setup-completion), otherwise use full path, or relative path>
```

## Credits

All credits to [Dabz/kafka-security-playbook](https://github.com/Dabz/kafka-security-playbook/tree/master/kerberos)