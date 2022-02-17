# Replicator (using Confluent Cloud)

## OnPrem to Cloud examples with ByteArrayConverter

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

### How to run

With Connect:

```
$ ./connect-onprem-to-cloud.sh
```

With Replicator executable:

```
$ ./executable-onprem-to-cloud.sh
```
## OnPrem to Cloud examples with AvroConverter

The two example above are using default `value.converter`=`io.confluent.connect.replicator.util.ByteArrayConverter` which does not preserve the schemas.

There are two scripts ending with `avro.sh` that are using `value.converter`=`io.confluent.connect.avro.AvroConverter` that preserve schemas.

This is documented [here](https://docs.confluent.io/platform/current/multi-dc-deployments/replicator/index.html#replicating-messages-with-schemas)

### How to run

With Connect:

```
$ ./connect-onprem-to-cloud-avro.sh
```

With Replicator executable:

```
$ ./executable-onprem-to-cloud-avro.sh
```

N.B: Control Center is reachable at [http://127.0.0.1:9021](http://127.0.0.1:9021])
