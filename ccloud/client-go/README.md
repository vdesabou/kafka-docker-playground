# GO client (producer/consumer) (using Confluent Cloud)

## Objective

Quickly test [GO example](https://github.com/confluentinc/examples/tree/5.4.1-post/clients/cloud/go) client using Confluent Cloud



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
sasl.jaas.config=org.apache.kafka.common.security.plain.PlainLoginModule required username="<API KEY>" password="<API SECRET>";
```

2. Simply run:

```
$ ./start.sh
```

## Details of what the script is doing

Building docker image

```bash
$ docker build -t vdesabou/go-ccloud-example-docker .
```

Starting producer

```bash
$ docker run -v ${DIR}/librdkafka.config:/tmp/librdkafka.config vdesabou/go-ccloud-example-docker ./producer -f /tmp/librdkafka.config -t testgo
```

Note: `librdkafka.config`is generated from your `$HOME/.ccloud/config`

Starting consumer

```bash
$ docker run -v ${DIR}/librdkafka.config:/tmp/librdkafka.config vdesabou/go-ccloud-example-docker ./consumer -f /tmp/librdkafka.config -t testgo
```