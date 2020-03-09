# .NET client (producer/consumer) (using Confluent Cloud)

## Objective

Quickly test [.NET example](https://github.com/confluentinc/examples/tree/5.4.0-post/clients/cloud/csharp) client using Confluent Cloud



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
```

2. Simply run:

```
$ ./start.sh <2.2 or 3.1> (Core .NET version, default is 2.1)
```

## Details of what the script is doing

Building docker image

```bash
$ docker build --build-arg CORE_RUNTIME_TAG=$CORE_RUNTIME_TAG --build-arg CORE_SDK_TAG=$CORE_SDK_TAG --build-arg CSPROJ_FILE=$CSPROJ_FILE -t vdesabou/dotnet-ccloud-example-docker .
```

Starting producer

```bash
$ docker run -v ${DIR}/librdkafka.config:/tmp/librdkafka.config vdesabou/dotnet-example-docker produce test1 /tmp/librdkafka.config
```

Note: `librdkafka.config`is generated from your `$HOME/.ccloud/config`

Starting consumer

```bash
$ docker run -v ${DIR}/librdkafka.config:/tmp/librdkafka.config vdesabou/dotnet-example-docker consume test1 /tmp/librdkafka.config
```