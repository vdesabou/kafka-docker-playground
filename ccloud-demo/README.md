# ccloud-demo

## Objective

Confluent Cloud project based on [cp-all-in-one-cloud](https://github.com/confluentinc/examples/tree/5.3.x/cp-all-in-one-cloud), just adding a few simple components on top of it:

* Java Producer/Consumer
* Kafka Streams
* Grafana dashboard

## Pre-requisites

* `docker-compose` (example `brew cask install docker`)
* [Confluent Cloud CLI](https://docs.confluent.io/current/cloud-quickstart.html#step-2-install-ccloud-cli)
* [An initialized Confluent Cloud cluster used for development only](https://confluent.cloud)

### Step 1

On the host from which you are running Docker, ensure that you have properly initialized Confluent Cloud CLI and have a valid configuration file at `$HOME/.ccloud/config`.

Example:

```
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

```

### Step 2

By default, the demo uses Confluent Schema Registry running in a local Docker container. If you prefer to use Confluent Cloud Schema Registry instead, you need to first set it up:

   a. [Enable](http://docs.confluent.io/current/quickstart/cloud-quickstart.html#step-3-configure-sr-ccloud) Confluent Cloud Schema Registry prior to running the demo

   b. Validate your credentials to Confluent Cloud Schema Registry

   ```bash
   $ curl -u $(grep "^schema.registry.basic.auth.user.info" $HOME/.ccloud/config | cut -d'=' -f2) $(grep "^schema.registry.url" $HOME/.ccloud/config | cut -d'=' -f2)/subjects
   ```

### Step 3

* Run with local Docker Schema Registry

```
./start.sh
```
or
```
./start.sh SCHEMA_REGISTRY_DOCKER
```

* Run with Confluent Cloud Schema Registry 

```
./start.sh SCHEMA_REGISTRY_CONFLUENT_CLOUD
```


### How to use ksql-cli:

```bash
docker-compose exec ksql-cli bash -c \
'echo -e "\n\n⏳ Waiting for KSQL to be available before launching CLI\n"; while [ $(curl -s -o /dev/null -w %{http_code} http://ksql-server:8089/) -eq 000 ] ; do echo -e $(date) "KSQL Server HTTP state: " $(curl -s -o /dev/null -w %{http_code} http:/ksql-server:8089/) " (waiting for 200)" ; sleep 5 ; done; ksql http://ksql-server:8089'
```

## Using Confluent CLI with Avro And Confluent Cloud Schema Registry

See [link](https://github.com/confluentinc/examples/tree/5.3.1-post/clients/cloud/confluent-cli#example-2-avro-and-confluent-cloud-schema-registry) or use `confluent-cli-ccsr-example.sh` in this repo.

## Other clients example

See [link](https://github.com/confluentinc/examples/blob/5.3.1-post/clients/cloud/README.md)

## ACLs in cloud

See [link](https://github.com/confluentinc/examples/blob/5.3.1-post/security/acls/acl.sh)

## Grafana

Open a brower and visit http://localhost:3000 (grafana). 
Login/password is admin/admin (only Producer and Consumer dashboards are available as it is Confluent Cloud)
