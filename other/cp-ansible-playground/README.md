# Using cp-ansible playground ![CI](https://github.com/vdesabou/cp-ansible-playground/workflows/CI/badge.svg?branch=master)



## Pre-requisites

* `git` is installed
* `ansible` and `ansible-playbook` installed

## Description

Some plaintext Docker images (based on Ubuntu 18.04) are built daily using [vdesabou/cp-ansible-playground](https://github.com/vdesabou/cp-ansible-playground) repository.

Those images can then be used to easily test different configurations by providing updated host inventory yaml file.

This is deploying the following containers using Confluent [cp-ansible](https://docs.confluent.io/current/installation/installing_cp/cp-ansible.html) Ansible playbooks:

* 1 zookeeper (`zookeeper1`)
* 3 broker (`broker1`, `broker2` and `broker3`)
* 1 connect (`connect`)
* 1 schema-registry (`schema-registry`)
* 1 ksql (`ksql-server`)
* 1 rest-proxy (`rest-proxy`)
* 1 control-center (`control-center`)

## Tags

Available tags are listed [here](https://github.com/vdesabou/cp-ansible-playground/blob/master/.github/workflows/run-regression.yml) (check `tag` list).

## How to run

```
$ ./start.sh <host yml file>
```

`hosts-plaintext.yml` host file should be used as the base file, then you can modify it to include your changes:

```bash
$ cp hosts-plaintext.yml hosts-custom.yml

# modify hosts-custom.yml as you want, for example uncomment:

ssl_enabled: true
sasl_protocol: plain

# run the script
$ ./start.sh hosts-custom.yml
```

Once the script has been run, you will have all the docker container running with your changes.

If you want to test additional modifications, you can update your `hosts-custom.yml` file and apply the changes:

```bash
$ ansible-playbook -i hosts-custom.yml all.yml
```

or if ansible version > 2.11:

```bash
$ ansible-playbook -i hosts-custom.yml confluent.platform.all
```

Or use ansible tags as explain in [Confluent docs](https://docs.confluent.io/current/installation/cp-ansible/ansible-install.html#installing-cp):

```bash
$ ansible-playbook -i hosts-custom.yml all.yml --tags=zookeeper
$ ansible-playbook -i hosts-custom.yml all.yml --tags=kafka_broker
$ ansible-playbook -i hosts-custom.yml all.yml --tags=schema_registry
$ ansible-playbook -i hosts-custom.yml all.yml --tags=kafka_rest
$ ansible-playbook -i hosts-custom.yml all.yml --tags=kafka_connect
$ ansible-playbook -i hosts-custom.yml all.yml --tags=ksql
$ ansible-playbook -i hosts-custom.yml all.yml --tags=control_center
```

or if ansible version > 2.11:

```bash
$ ansible-playbook -i hosts-custom.yml confluent.platform.all --tags=zookeeper
$ ansible-playbook -i hosts-custom.yml confluent.platform.all --tags=kafka_broker
$ ansible-playbook -i hosts-custom.yml confluent.platform.all --tags=schema_registry
$ ansible-playbook -i hosts-custom.yml confluent.platform.all --tags=kafka_rest
$ ansible-playbook -i hosts-custom.yml confluent.platform.all --tags=kafka_connect
$ ansible-playbook -i hosts-custom.yml confluent.platform.all --tags=ksql
$ ansible-playbook -i hosts-custom.yml confluent.platform.all --tags=control_center
```


You can also limit to one particular host using `--limit` option:

Example:

```bash
$ ansible-playbook -i hosts-custom.yml all.yml --limit=broker1
```

or if ansible version > 2.11:

```bash
$ ansible-playbook -i hosts-custom.yml confluent.platform.all --limit=broker1
```


N.B: Control Center is reachable at [http://127.0.0.1:9021](http://127.0.0.1:9021])