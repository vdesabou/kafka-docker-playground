# Using cp-ansible playground with Confluent Cloud ![CI](https://github.com/vdesabou/cp-ansible-playground/workflows/CI/badge.svg?branch=master)


## Pre-requisites

* `git` is installed
* `ansible` and `ansible-playbook` installed

## Description

See [this link](../../other/cp-ansible-playground/cp-ansible/README.md) for details about `cp-ansible-playground`

Here we're deploying the following containers connected to Confluent Cloud using Confluent [cp-ansible](https://docs.confluent.io/current/installation/installing_cp/cp-ansible.html) Ansible playbooks:

* 1 connect (`connect`)
* 1 ksql (`ksql-server`)
* 1 control-center (`control-center`)

## Tags

Available tags are `6.0.0`

## How to run

1. 

2. Then you just need to run:

```
$ playground run -f start<use tab key to activate fzf completion (see https://kafka-docker-playground.io/#/cli?id=%e2%9a%a1-setup-completion), otherwise use full path, or relative path>
```

`hosts-ccloud` host file is automatically generated with your confluent cloud details from `$HOME/.confluent/config`


N.B: Control Center is reachable at [http://127.0.0.1:9021](http://127.0.0.1:9021])