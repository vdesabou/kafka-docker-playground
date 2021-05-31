# LDAP auth SASL PLAIN

## Description

This is a deployment with no encryption but with [Client Authentication with LDAP](https://docs.confluent.io/platform/current/kafka/authentication_sasl/client-authentication-ldap.html#configuring-client-authentication-with-ldap):

* 1 zookeeper
* 1 broker
* 1 connect
* 1 schema-registry
* 1 control-center

## How to run

Simply run:

```
$ ./start.sh
```