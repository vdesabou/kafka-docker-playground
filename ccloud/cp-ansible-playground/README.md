# Using cp-ansible playground with Confluent Cloud [![Build Status](https://travis-ci.com/vdesabou/cp-ansible-playground.svg?branch=master)](https://travis-ci.com/vdesabou/cp-ansible-playground)


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

1. Create `$HOME/.ccloud/config`

On the host from which you are running Docker, ensure that you have properly initialized Confluent Cloud CLI and have a valid configuration file at `$HOME/.ccloud/config`.

Example:

```bash
$ cat $HOME/.ccloud/config
bootstrap.servers=<BROKER ENDPOINT>
ssl.endpoint.identification.algorithm=https
security.protocol=SASL_SSL
sasl.mechanism=PLAIN
sasl.jaas.config=org.apache.kafka.common.security.plain.PlainLoginModule required username\="<API KEY>" password\="<API SECRET>";

// Schema Registry specific settings
basic.auth.credentials.source=USER_INFO
schema.registry.basic.auth.user.info=<SR_API_KEY>:<SR_API_SECRET>
schema.registry.url=<SR ENDPOINT>

// license
confluent.license=<YOUR LICENSE>

// ccloud login password
ccloud.user=<ccloud login>
ccloud.password=<ccloud password>
```

2. Then you just need to run:

```
$ ./start.sh
```

`hosts-ccloud` host file is automatically generated with your confluent cloud details from `$HOME/.ccloud/config`


N.B: Control Center is reachable at [http://127.0.0.1:9021](http://127.0.0.1:9021])