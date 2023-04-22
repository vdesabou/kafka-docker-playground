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
$ playground run -f start<tab>
```

## Credits

All credits to [Dabz/kafka-security-playbook](https://github.com/Dabz/kafka-security-playbook/tree/master/kerberos)