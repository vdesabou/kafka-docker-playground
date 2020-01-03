# cp-ansible playground

## Description

This is a deployment using Confluent [cp-ansible](https://docs.confluent.io/current/installation/installing_cp/cp-ansible.html) Ansible playbooks:

* 1 zookeeper
* 2 broker
* 1 connect
* 1 schema-registry
* 1 ksql
* 1 rest-proxy
* 1 control-center

It using Ubuntu 18.04

## How to run

Simply run:

```
$ ./start.sh
```

It takes about 50 minutes to run.

N.B: Control Center is reachable at [http://127.0.0.1:9021](http://127.0.0.1:9021])