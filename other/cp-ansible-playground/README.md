# cp-ansible playground [![Build Status](https://travis-ci.com/vdesabou/cp-ansible-playground.svg?branch=master)](https://travis-ci.com/vdesabou/cp-ansible-playground)

## Pre-requisites

* `git` is installed
* `ansible` and `ansible-playbook` installed

## Description

This is a deployment using Confluent [cp-ansible](https://docs.confluent.io/current/installation/installing_cp/cp-ansible.html) Ansible playbooks:

* 1 zookeeper (`zookeeper1`)
* 3 broker (`broker1`, `broker2` and `broker3`)
* 1 connect (`connect`)
* 1 schema-registry (`schema-registry`)
* 1 ksql (`ksql-server`)
* 1 rest-proxy (`rest-proxy`)
* 1 control-center (`control-center`)

The plaintext Docker images (based on Ubuntu 18.04) are build daily using [vdesabou/cp-ansible-playground](https://github.com/vdesabou/cp-ansible-playground) repository.

## Tags

Available tags are `5.3.1`, `5.4.0` and `5.4.1`

## How to run

```
$ ./start.sh <host yml file>
```

Example: to start an environment using plaintext:

```bash
$ ./start.sh hosts-plaintext.yml
```

Then you can do your modifications and run `ansible-playbook -i <host yml file> all.yml` to apply your changes.

You can also use ansible tags as explain in [Confluent docs](https://docs.confluent.io/current/installation/cp-ansible/ansible-install.html#installing-cp):

```bash
$ ansible-playbook -i <host yml file> all.yml --tags=zookeeper
$ ansible-playbook -i <host yml file> all.yml --tags=kafka_broker
$ ansible-playbook -i <host yml file> all.yml --tags=schema_registry
$ ansible-playbook -i <host yml file> all.yml --tags=kafka_rest
$ ansible-playbook -i <host yml file> all.yml --tags=kafka_connect
$ ansible-playbook -i <host yml file> all.yml --tags=ksql
$ ansible-playbook -i <host yml file> all.yml --tags=control_center
```

## Upgrade test

An upgrade test from `5.3.1` to `5.4.1` is available using `upgrade-test.sh`script


N.B: Control Center is reachable at [http://127.0.0.1:9021](http://127.0.0.1:9021])