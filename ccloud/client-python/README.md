# Python client (producer/consumer) (using Confluent Cloud)

## Objective

Quickly test [python example](https://docs.confluent.io/platform/current/tutorials/examples/clients/docs/python.html#run-all-the-code-in-docker) client using Confluent Cloud

## Prerequisites

* Properly initialized Confluent Cloud CLI

You must be already logged in with confluent CLI which needs to be setup with correct environment, cluster and api key to use:

Typical commands to run:

```bash
$ confluent login --save

Use environment $ENVIRONMENT_ID:
$ confluent environment use $ENVIRONMENT_ID

Use cluster $CLUSTER_ID:
$ confluent kafka cluster use $CLUSTER_ID

Store api key $API_KEY:
$ confluent api-key store $API_KEY $API_SECRET --resource $CLUSTER_ID --force

Use api key $API_KEY:
$ confluent api-key use $API_KEY --resource $CLUSTER_ID
```

* Create a file `$HOME/.confluent/config`

You should have a valid configuration file at `$HOME/.confluent/config`.

Example:

```bash
$ cat $HOME/.confluent/config
bootstrap.servers=<BROKER ENDPOINT>
ssl.endpoint.identification.algorithm=https
security.protocol=SASL_SSL
sasl.mechanism=PLAIN
sasl.jaas.config=org.apache.kafka.common.security.plain.PlainLoginModule required username="<API KEY>" password="<API SECRET>";

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
$ ./start.sh
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