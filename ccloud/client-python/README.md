# Python client (producer/consumer) (using Confluent Cloud)

## Objective

Quickly test [python example](https://docs.confluent.io/platform/current/tutorials/examples/clients/docs/python.html#run-all-the-code-in-docker) client using Confluent Cloud

## Prerequisites

See [here](https://kafka-docker-playground.io/#/how-to-use?id=%f0%9f%8c%a4%ef%b8%8f-confluent-cloud-examples)

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
$ just use <playground run> command and search for start.sh in this folder
```

## Details of what the script is doing

Building docker image

```bash
$ docker build -t vdesabou/python-ccloud-example-docker .
```

Starting producer

```bash
$ docker run --quiet --rm -v ${DIR}/librdkafka.config:/tmp/librdkafka.config vdesabou/python-ccloud-example-docker ./producer.py -f /tmp/librdkafka.config -t testpython
```

Note: `librdkafka.config`is generated from your `$HOME/.confluent/config`

Starting consumer

```bash
$ docker run --quiet --rm -it -v ${DIR}/librdkafka.config:/tmp/librdkafka.config vdesabou/python-ccloud-example-docker ./consumer.py -f /tmp/librdkafka.config -t testpython
```

Starting AVRO producer

```bash
$ docker run --quiet --rm -v ${DIR}/librdkafka.config:/tmp/librdkafka.config vdesabou/python-ccloud-example-docker ./producer.py -f /tmp/librdkafka.config -t testpythonavro
```

Starting AVRO consumer

```bash
$ docker run --quiet --rm -it -v ${DIR}/librdkafka.config:/tmp/librdkafka.config vdesabou/python-ccloud-example-docker ./consumer.py -f /tmp/librdkafka.config -t testpythonavro
```