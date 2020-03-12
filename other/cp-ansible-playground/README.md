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

The plaintext Docker images (based on Ubuntu 18.04) are build daily using [vdesabou/cp-ansible-playground](https://github.com/vdesabou/cp-ansible-playground) repository.

## How to run

To start an environment (using plaintext):

```
$ ./start-plaintext.sh
```

Then you can do your modifications and run `ansible-playbook -i hosts.yml all.yml` to apply your changes.$

N.B: Control Center is reachable at [http://127.0.0.1:9021](http://127.0.0.1:9021])