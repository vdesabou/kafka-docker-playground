# Migrate Schemas to Confluent Cloud

## Objective

Quickly test [Migrate Schemas to Confluent Cloud](https://docs.confluent.io/current/schema-registry/installation/migrate.html#quick-start) which is using Replicator Schema Registry migration, which is available since CP 5.2.0.

## Prerequisites

See [here](https://kafka-docker-playground.io/#/how-to-use?id=%f0%9f%8c%a4%ef%b8%8f-confluent-cloud-examples)
## How to run

Simply run:

```
$ just use <playground run> command and search for start.sh in this folder
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
$ docker exec -i connect kafka-avro-console-producer --bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic executable-products --property value.schema='{"type":"record","name":"myrecord","fields":[{"name":"name","type":"string"},
{"name":"price", "type": "float"}, {"name":"quantity", "type": "int"}]}' << EOF
{"name": "scissors", "price": 2.75, "quantity": 3}
{"name": "tape", "price": 0.99, "quantity": 10}
{"name": "notebooks", "price": 1.99, "quantity": 5}
EOF
```

Starting replicator executable (logs are in /tmp/replicator.log):

```bash
# run in detach mode -d
docker exec -d connect bash -c 'export CLASSPATH=/etc/kafka-connect/jars/replicator-rest-extension-*.jar; replicator --consumer.config /etc/kafka/executable-onprem-to-cloud-consumer.properties --producer.config /etc/kafka/executable-onprem-to-cloud-producer.properties  --replication.config /etc/kafka/executable-onprem-to-cloud-replicator.properties  --cluster.id executable-onprem-to-cloud --include _schemas > /tmp/replicator.log 2>&1'
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
