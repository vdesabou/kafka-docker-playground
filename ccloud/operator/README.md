# Confluent Operator with Confluent Cloud

## Objective

Quickly test [Confluent Operator](https://docs.confluent.io/operator/current/overview.html) with Confluent Cloud and Minikube.

It starts:

* Connect
* Control Center
* KSQL

**IMPORTANT**: it requires tweaks to helm templates file, see tweaks [here](https://github.com/vdesabou/kafka-docker-playground/blob/7ec0c4b512efda45de1f8bd73719d9c90d0cca70/ccloud/operator/start.sh#L53)

It also showcases a connector example (SpoolDir) and Prometheus/Grafana example.

## How to run

Create `$HOME/.confluent/config`

On the host from which you are running Docker, ensure that you have properly initialized Confluent Cloud CLI and have a valid configuration file at `$HOME/.confluent/config`.

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

Simply run:

```
$ ./start.sh
```
