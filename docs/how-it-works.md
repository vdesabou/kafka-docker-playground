
# 🎓️ How it works

Before learning how to create your own examples/reproduction models, here are some explanations on how the playground works internally...

## 📁 Folder structure

The main categories like `ccloud`, `connect`, `environment` are in root folder:

```
├── 3rdparty
├── ccloud
├── cloudformation
├── connect
├── docs
├── environment
├── images
├── ksqldb
├── operator
├── other
├── replicator
├── scripts
├── tools
└── troubleshooting
```

All the tests are and **must** be at second level.

Example with `connect`folder:

```
connect
├── connect-active-mq-sink
├── connect-active-mq-source
├── connect-amps-source
├── connect-appdynamics-metrics-sink
├── connect-aws-cloudwatch-logs-source
├── connect-aws-cloudwatch-metrics-sink
<snip>

131 directories
```

This is important because each test is sourcing [`scripts/utils.sh`](https://github.com/vdesabou/kafka-docker-playground/blob/master/scripts/utils.sh) like this:

```bash
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh
```

## 🐳 Docker override

The playground makes extensive use of docker-compose [override](https://docs.docker.com/compose/extends/) (i.e `docker-compose -f docker-compose1.yml -f docker-compose2.yml ...`).

Each test is built based on an [environment](#/content?id=%F0%9F%94%90-environments), [PLAINTEXT](https://github.com/vdesabou/kafka-docker-playground/tree/master/environment/plaintext) being the most common one.

> [!TIP]
> Check **[📝 See properties file](/how-to-use?id=📝-see-properties-file)** section, in order to see the end result properties file.

Let's have a look at some examples to understand how it works:

### 🔓 Connector using PLAINTEXT

Example with ([active-mq-sink.sh](https://github.com/vdesabou/kafka-docker-playground/blob/master/connect/connect-active-mq-sink/active-mq-sink.sh)):

At the beginning of the script, we have:

```shell
${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"
```

The *local* [`${PWD}/docker-compose.plaintext.yml`](https://github.com/vdesabou/kafka-docker-playground/blob/master/connect/connect-active-mq-sink/docker-compose.plaintext.yml) file is only composed of:

```yml
---
version: '3.5'
services:
  activemq:
    image: rmohr/activemq:5.15.9
    hostname: activemq
    container_name: activemq
    ports:
      - '61616:61616'
      - '8161:8161'

  connect:
    environment:
      CONNECT_PLUGIN_PATH: /usr/share/confluent-hub-components/confluentinc-kafka-connect-activemq-sink
```

It contains:

* `activemq` which is a container required for the test.
* `connect` container, which overrides value `CONNECT_PLUGIN_PATH` from [`environment/plaintext/docker-compose.yml`](https://github.com/vdesabou/kafka-docker-playground/blob/master/environment/plaintext/docker-compose.yml)

PLAINTEXT environment is used thanks to the call to [`${DIR}/../../environment/plaintext/start.sh`](https://github.com/vdesabou/kafka-docker-playground/blob/master/environment/plaintext/start.sh), which invokes the docker-compose command in the end like this:

```bash
docker-compose -f ../../environment/plaintext/docker-compose.yml -f ${PWD}/docker-compose.plaintext.yml up -d
```


> [!WARNING]
> The *local* docker-compose file should be named docker-compose.%environment%[.%optional'%].yml 
> 
> Example: 
> 
> `docker-compose.plaintext.yml` or `docker-compose.plaintext.mtls.yml`
> 
> This is required for [stop.sh](https://github.com/vdesabou/kafka-docker-playground/blob/master/connect/connect-active-mq-sink/stop.sh) script to work properly.


### 🔐 Environment SASL/SSL 

Environments are also overriding [PLAINTEXT](https://github.com/vdesabou/kafka-docker-playground/tree/master/environment/plaintext), so for example [SASL/SSL](https://github.com/vdesabou/kafka-docker-playground/tree/master/environment/sasl-ssl) has a [docker-compose.yml](https://github.com/vdesabou/kafka-docker-playground/blob/master/environment/sasl-ssl/docker-compose.yml) file like this:

```yml
  ####
  #
  # This file overrides values from environment/plaintext/docker-compose.yml
  #
  ####

  zookeeper:
    environment:
      KAFKA_OPTS: -Djava.security.auth.login.config=/etc/kafka/secrets/zookeeper_jaas.conf
                  -Dzookeeper.authProvider.1=org.apache.zookeeper.server.auth.SASLAuthenticationProvider
                  -DrequireClientAuthScheme=sasl
                  -Dzookeeper.allowSaslFailedClients=false
    volumes:
      - ../../environment/sasl-ssl/security:/etc/kafka/secrets

  broker:
    volumes:
      - ../../environment/sasl-ssl/security:/etc/kafka/secrets
    environment:
      KAFKA_INTER_BROKER_LISTENER_NAME: SASL_SSL
      KAFKA_LISTENER_SECURITY_PROTOCOL_MAP: SASL_SSL:SASL_SSL
      KAFKA_ADVERTISED_LISTENERS: SASL_SSL://broker:9092
      KAFKA_LISTENERS: SASL_SSL://:9092
      CONFLUENT_METRICS_REPORTER_SECURITY_PROTOCOL: SASL_SSL
      CONFLUENT_METRICS_REPORTER_SASL_JAAS_CONFIG: "org.apache.kafka.common.security.plain.PlainLoginModule required \
        username=\"client\" \
        password=\"client-secret\";"
      CONFLUENT_METRICS_REPORTER_SASL_MECHANISM: PLAIN
      CONFLUENT_METRICS_REPORTER_SSL_TRUSTSTORE_LOCATION: /etc/kafka/secrets/kafka.client.truststore.jks
      CONFLUENT_METRICS_REPORTER_SSL_TRUSTSTORE_PASSWORD: confluent
      CONFLUENT_METRICS_REPORTER_SSL_KEYSTORE_LOCATION: /etc/kafka/secrets/kafka.client.keystore.jks
      CONFLUENT_METRICS_REPORTER_SSL_KEYSTORE_PASSWORD: confluent
      CONFLUENT_METRICS_REPORTER_SSL_KEY_PASSWORD: confluent
      KAFKA_SASL_ENABLED_MECHANISMS: PLAIN
      KAFKA_SASL_MECHANISM_INTER_BROKER_PROTOCOL: PLAIN
      KAFKA_SSL_KEYSTORE_FILENAME: kafka.broker.keystore.jks
      KAFKA_SSL_KEYSTORE_CREDENTIALS: broker_keystore_creds
      KAFKA_SSL_KEY_CREDENTIALS: broker_sslkey_creds
      KAFKA_SSL_TRUSTSTORE_FILENAME: kafka.broker.truststore.jks
      KAFKA_SSL_TRUSTSTORE_CREDENTIALS: broker_truststore_creds
      # enables 2-way authentication
      KAFKA_SSL_CLIENT_AUTH: "required"
      KAFKA_SSL_ENDPOINT_IDENTIFICATION_ALGORITHM: "HTTPS"
      KAFKA_OPTS: -Djava.security.auth.login.config=/etc/kafka/secrets/broker_jaas.conf
      KAFKA_SSL_PRINCIPAL_MAPPING_RULES: RULE:^CN=(.*?),OU=TEST.*$$/$$1/,DEFAULT

      <snip>
```

As you can see, it only contains what is required to add SASL/SSL to a PLAINTEXT environment 💫 !

### 🔏 Connector using SASL/SSL

Example with ([gcs-sink-sasl-ssl.sh](https://github.com/vdesabou/kafka-docker-playground/blob/master/connect/connect-gcp-gcs-sink/gcs-sink-sasl-ssl.sh)):

```shell
${DIR}/../../environment/sasl-ssl/start.sh "${PWD}/docker-compose.sasl-ssl.yml""
```

The *local* [`${PWD}/docker-compose.sasl-ssl.yml`](https://github.com/vdesabou/kafka-docker-playground/blob/master/connect/connect-gcp-gcs-sink/docker-compose.sasl-ssl.yml) is only composed of:

```yml
version: '3.5'
services:
  connect:
    volumes:
        - ../../connect/connect-gcp-gcs-sink/keyfile.json:/tmp/keyfile.json:ro
        - ../../environment/sasl-ssl/security:/etc/kafka/secrets
    environment:
      CONNECT_PLUGIN_PATH: /usr/share/confluent-hub-components/confluentinc-kafka-connect-gcs
```

> [!TIP]
> If you're looking for a connector example with different environments, [GCS sink](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-gcp-gcs-sink) contains various examples:
> * [SASL/SSL](https://github.com/vdesabou/kafka-docker-playground/blob/master/connect/connect-gcp-gcs-sink/gcs-sink-sasl-ssl.sh)
> * [2WAY/SSL](https://github.com/vdesabou/kafka-docker-playground/blob/master/connect/connect-gcp-gcs-sink/gcs-sink-2way-ssl.sh)
> * [KERBEROS](https://github.com/vdesabou/kafka-docker-playground/blob/master/connect/connect-gcp-gcs-sink/gcs-sink-kerberos.sh)
> * [LDAP Authentication with SASL/PLAIN](https://github.com/vdesabou/kafka-docker-playground/blob/master/connect/connect-gcp-gcs-sink/gcs-sink-ldap-authorizer-sasl-plain.sh)
> * [RBAC with SASL/PLAIN](https://github.com/vdesabou/kafka-docker-playground/blob/master/connect/connect-gcp-gcs-sink/gcs-sink-rbac-sasl-plain.sh)

## 🔗 Connect image used

The Kafka Connect image [used](https://github.com/vdesabou/kafka-docker-playground/blob/714b36289981f9fe8f699ae3eab9a508127b625e/environment/plaintext/docker-compose.yml#L80) in the playground is `vdesabou/kafka-docker-playground-connect`

It is built [everyday](https://github.com/vdesabou/kafka-docker-playground-connect/actions) using the repository [vdesabou/kafka-docker-playground-connect](https://github.com/vdesabou/kafka-docker-playground-connect).

It is either based on [`cp-server-connect-base`](https://hub.docker.com/r/confluentinc/cp-server-connect-base) for version greater than `5.3.0` or [`cp-kafka-connect-base`](https://hub.docker.com/r/confluentinc/cp-kafka-connect-base) otherwise.

Several tools are [installed](https://github.com/vdesabou/kafka-docker-playground-connect/blob/00f29069be566162a5be84d64637b3e1f9920f95/Dockerfile#L11-L15) on this image such as `openssl`, `tcpdump`, `iptables`, `netcat`, etc..

If you're missing a tool, you can install it at runtime, some examples:

```bash
# directly with rpm
docker exec -i --user root connect bash -c "curl http://mirror.centos.org/centos/7/os/x86_64/Packages/tree-1.6.0-10.el7.x86_64.rpm -o tree-1.6.0-10.el7.x86_64.rpm && rpm -Uvh tree-1.6.0-10.el7.x86_64.rpm"
# using yum
docker exec -i --user root connect bash -c "yum update -y --disablerepo='Confluent*' && yum install findutils -y"
```

See the [Dockerfile](https://github.com/vdesabou/kafka-docker-playground-connect/blob/master/Dockerfile) used to build the images.

> [!NOTE]
> In the past, the image used to have all latest connectors included, but this is no more the case since [#1426](https://github.com/vdesabou/kafka-docker-playground/issues/1426)


## 🤖 How CI works

[Everyday](https://github.com/vdesabou/kafka-docker-playground/blob/4a96c0f78e7eb93477d483584ecbc97abec50e0c/.github/workflows/ci.yml#L8), regression tests are executed using [Github Actions](https://github.com/features/actions). 

The workflow runs and logs are available [here](https://github.com/vdesabou/kafka-docker-playground/actions).

The CI is defined using [`.github/workflows/ci.yml`](https://github.com/vdesabou/kafka-docker-playground/blob/master/.github/workflows/ci.yml) file (see the list of tests executed [here](https://github.com/vdesabou/kafka-docker-playground/blob/4a96c0f78e7eb93477d483584ecbc97abec50e0c/.github/workflows/ci.yml#L63))

> [!NOTE]
> CI is executed on Ubuntu 20.04 on Azure, see [documentation](https://docs.github.com/en/actions/using-github-hosted-runners/about-github-hosted-runners#supported-runners-and-hardware-resources)

> [!NOTE]
> A test is executed if:
> 
> * It was failing in the last run
> * A change has been made in the test directory
> * CP and/or connector version(s) has/have changed
> * Last execution was more than 14 days ago

If a test is failing 🔥, a Github issue will be automatically opened or updated with results for each CP version.

*Example:*

Issue [#1401](https://github.com/vdesabou/kafka-docker-playground/issues/1401):

![github_issue](./images/github_issue.jpg)

The Github issue will be automatically closed when all results for a test are ok:

![github_issue_closed](./images/github_issue_closed.jpg)

CI results are displayed in **[Content](/content.md)** section:

![ci_results](./images/ci_results.jpg)

> [!TIP]
> * When the test is successful, the badge looks like [![CI ok](https://img.shields.io/badge/6/6-ok!-green)](https://github.com/vdesabou/kafka-docker-playground/runs/3875670630) and clicking on it brings you to the CI run.
> 
> * When the test is failing for **all** tested CP versions, the badge looks like [![CI fail](https://img.shields.io/badge/16/24-fail!-red)](https://github.com/vdesabou/kafka-docker-playground/issues/935) and clicking on it brings you to the corresponding Github issue.
> 
> * When the test is failing for **just some** tested CP versions, the badge looks like [![issue 778](https://img.shields.io/badge/6/12-CP%206.2.1-red)](https://github.com/vdesabou/kafka-docker-playground/issues/778) (which includes CP version) and clicking on it brings you to the corresponding Github issue.
> 
> * When a test cannot be tested in CI, the badge ![not tested](https://img.shields.io/badge/CI-not%20tested!-violet) is set (without any associated link).
> 
> * When a test is skipped, the badge looks like [![CP 5.4.5](https://img.shields.io/badge/skipped-CP%205.4.5-lightgrey)](https://github.com/vdesabou/kafka-docker-playground/runs/4223957685?check_suite_focus=true) and clicking on it brings you to the CI run.
> 
> * When there is a known issue, the badge looks like [![CP 6.2.1](https://img.shields.io/badge/known%20issue-CP%206.2.1-orange)](https://github.com/vdesabou/kafka-docker-playground/issues/907) and clicking on it brings you to the corresponding Github issue.

> [!TIP]
> * Clicking on the connector version badge [![version](https://img.shields.io/badge/v-1.2.2-pink)](https://docs.confluent.io/kafka-connect-aws-dynamodb/current/index.html) brings you to the corresponding documentation page
