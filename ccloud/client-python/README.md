# Python client (producer/consumer) (using Confluent Cloud)

## Objective

Quickly test [python example](https://docs.confluent.io/platform/current/tutorials/examples/clients/docs/python.html#run-all-the-code-in-docker) client using Confluent Cloud

## Prerequisites

All you have to do is to be already logged in with [confluent CLI](https://docs.confluent.io/confluent-cli/current/overview.html#confluent-cli-overview).

By default, a new Confluent Cloud environment with a Cluster will be created.

You can configure the cluster by setting environment variables:

* `CLUSTER_CLOUD`: The Cloud provider (possible values: `aws`, `gcp` and `azure`, default `aws`)
* `CLUSTER_REGION`: The Cloud region (use `confluent kafka region list` to get the list, default `eu-west-2`)
* `CLUSTER_TYPE`: The type of cluster (possible values: `basic`, `standard` and `dedicated`, default `basic`)
* `ENVIRONMENT` (optional): The environment id where want your new cluster (example: `env-xxxxx`) 

In case you want to use your own existing cluster, you need to setup these environment variables:

* `ENVIRONMENT`: The environment id where your cluster is located (example: `env-xxxxx`) 
* `CLUSTER_NAME`: The cluster name
* `CLUSTER_CLOUD`: The Cloud provider (possible values: `aws`, `gcp` and `azure`)
* `CLUSTER_REGION`: The Cloud region (example `us-east-2`)
* `CLUSTER_CREDS`: The Kafka api key and secret to use, it should be separated with semi-colon (example: `<API_KEY>:<API_KEY_SECRET>`)
* `SCHEMA_REGISTRY_CREDS` (optional, if not set, new one will be created): The Schema Registry api key and secret to use, it should be separated with semi-colon (example: `<SR_API_KEY>:<SR_API_KEY_SECRET>`)

## How to run

1. Create `$HOME/.confluent/config`

On the host from which you are running Docker, ensure that you have properly initialized Confluent Cloud CLI and have a valid configuration file at `$HOME/.confluent/config`.

Example:

```bash
$ cat $HOME/.confluent/config
bootstrap.servers=<BROKER ENDPOINT>
ssl.endpoint.identification.alpythonrithm=https
security.protocol=SASL_SSL
sasl.mechanism=PLAIN
sasl.jaas.config=org.apache.kafka.common.security.plain.PlainLoginModule required username="<API KEY>" password="<API SECRET>";
```

2. Simply run:

```
$ playground run -f start<tab>
```

## Details of what the script is doing

Building docker image

```bash
$ docker build -t vdesabou/python-ccloud-example-docker .
```

Starting producer

```bash
$ docker run --rm -v ${DIR}/librdkafka.config:/tmp/librdkafka.config vdesabou/python-ccloud-example-docker ./producer.py -f /tmp/librdkafka.config -t testpython
```

Note: `librdkafka.config`is generated from your `$HOME/.confluent/config`

Starting consumer

```bash
$ docker run --rm -it -v ${DIR}/librdkafka.config:/tmp/librdkafka.config vdesabou/python-ccloud-example-docker ./consumer.py -f /tmp/librdkafka.config -t testpython
```

Starting AVRO producer

```bash
$ docker run --rm -v ${DIR}/librdkafka.config:/tmp/librdkafka.config vdesabou/python-ccloud-example-docker ./producer.py -f /tmp/librdkafka.config -t testpythonavro
```

Starting AVRO consumer

```bash
$ docker run --rm -it -v ${DIR}/librdkafka.config:/tmp/librdkafka.config vdesabou/python-ccloud-example-docker ./consumer.py -f /tmp/librdkafka.config -t testpythonavro
```