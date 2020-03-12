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

## How to run

To start an environment (using plaintext):

```
$ ./start-plaintext.sh
```

Then you can do your modifications and run `ansible-playbook -i hosts.yml all.yml` to apply your changes.

N.B: Control Center is reachable at [http://127.0.0.1:9021](http://127.0.0.1:9021])