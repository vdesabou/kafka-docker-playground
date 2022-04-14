# Replicator (using Confluent Cloud)

## OnPrem to Cloud examples with ByteArrayConverter

## Prerequisites

All you have to do is to be already logged in with [confluent CLI](https://docs.confluent.io/confluent-cli/current/overview.html#confluent-cli-overview).

By default, a new Confluent Cloud environment with a Cluster will be created.

You can configure the cluster by setting environment variables:

* `CLUSTER_CLOUD`: The Cloud provider (possible values: `aws`, `gcp` and `azure`, default `aws`)
* `CLUSTER_REGION`: The Cloud region (use `confluent kafka region list` to get the list, default `eu-west-2`)
* `ENVIRONMENT` (optional): The environment id where want your new cluster (example: `env-xxxxx`) 

In case you want to use your own existing cluster, you need to setup these environment variables:

* `ENVIRONMENT`: The environment id where your cluster is located (example: `env-xxxxx`) 
* `CLUSTER_NAME`: The cluster name
* `CLUSTER_CLOUD`: The Cloud provider (possible values: `aws`, `gcp` and `azure`)
* `CLUSTER_REGION`: The Cloud region (example `us-east-2`)
* `CLUSTER_CREDS`: The Kafka api key and secret to use, it should be separated with semi-colon (example: `<API_KEY>:<API_KEY_SECRET>`)
* `SCHEMA_REGISTRY_CREDS` (optional, if not set, new one will be created): The Schema Registry api key and secret to use, it should be separated with semi-colon (example: `<SR_API_KEY>:<SR_API_KEY_SECRET>`)

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
