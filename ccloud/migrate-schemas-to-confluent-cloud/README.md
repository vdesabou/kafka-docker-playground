# Migrate Schemas to Confluent Cloud

## Objective

Quickly test [Migrate Schemas to Confluent Cloud](https://docs.confluent.io/current/schema-registry/installation/migrate.html#quick-start) which is using Replicator Schema Registry migration, which is available since CP 5.2.0.

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
* `CLUSTER_CREDS`: The Kafka api key and secret to use, it should be separated with colon (example: `<API_KEY>:<API_KEY_SECRET>`)
* `SCHEMA_REGISTRY_CREDS` (optional, if not set, new one will be created): The Schema Registry api key and secret to use, it should be separated with colon (example: `<SR_API_KEY>:<SR_API_KEY_SECRET>`)
## How to run

Simply run:

```
$ playground run -f start<use tab key to activate fzf completion (see https://kafka-docker-playground.io/#/cli?id=%e2%9a%a1-setup-completion), otherwise use full path, or correct relative path>
```

## Details of what the script is doing

Verify there is no subject defined on destination SR: WARNING: output should be empty []:

```bash
$ curl -u $SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO $SCHEMA_REGISTRY_URL/subjects
```

Set the destination Schema Registry to IMPORT mode:

```bash
$ curl -u $SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO -X PUT -H "Content-Type: application/json" "$SCHEMA_REGISTRY_URL/mode" --data '{"mode": "IMPORT"}'
```

Sending messages to topic executable-products on source OnPREM cluster:

```bash
$ docker exec -i connect kafka-avro-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic executable-products --property value.schema='{"type":"record","name":"myrecord","fields":[{"name":"name","type":"string"},
{"name":"price", "type": "float"}, {"name":"quantity", "type": "int"}]}' << EOF
{"name": "scissors", "price": 2.75, "quantity": 3}
{"name": "tape", "price": 0.99, "quantity": 10}
{"name": "notebooks", "price": 1.99, "quantity": 5}
EOF
```

Starting replicator executable (logs are in /tmp/replicator.log):

```bash
# run in detach mode -d
docker exec -d connect bash -c 'export CLASSPATH=/etc/kafka-connect/jars/replicator-rest-extension-*.jar; replicator --consumer.config /etc/kafka/executable-onprem-to-cloud-consumer.properties --producer.config /etc/kafka/executable-onprem-to-cloud-producer.properties  --replication.config /etc/kafka/executable-onprem-to-cloud-replicator.properties  --cluster.id executable-onprem-to-cloud --whitelist _schemas > /tmp/replicator.log 2>&1'
```

Verify we have the schema:

```bash
$ curl -u $SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO $SCHEMA_REGISTRY_URL/subjects

["executable-products-value"]
````

Set the source Schema Registry to READONLY mode

```bash
$ curl -X PUT -H "Content-Type: application/json" "http://localhost:8081/mode" --data '{"mode": "READONLY"}'
```

Set the destination Schema Registry to READWRITE mode

```bash
$ curl -u $SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO -X PUT -H "Content-Type: application/json" "$SCHEMA_REGISTRY_URL/mode" --data '{"mode": "READWRITE"}'
```
