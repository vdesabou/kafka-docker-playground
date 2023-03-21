# KRAFT (without Zookeeper) PLAINTEXT

KRaft is in early access and should be used in development only. It is not suitable for production.

## Description

This is a deployment with no security:

* 1 broker
* 1 connect
* 1 schema-registry
* 1 ksqldb-server
* 1 ksqldb-cli
* 1 control-center

Using ksqlDB using CLI:

```bash
$ docker exec -i ksqldb-cli ksql http://ksqldb-server:8088
```

## How to run

Simply run:

```
$ ./start.sh
```