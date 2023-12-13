# Multiple Event Types in the Same Topic

## Objective

Quickly test [Multiple Event Types in the Same Topic](https://docs.confluent.io/platform/current/schema-registry/serdes-develop/index.html#multiple-event-types-in-the-same-topic).

Using this blog [post](https://www.confluent.io/blog/multiple-event-types-in-the-same-kafka-topic).

Note: This can only be run with version greater than 5.5

## How to run

Simply run:

```
$ playground run -f start<use tab key to activate fzf completion (see https://kafka-docker-playground.io/#/cli?id=%e2%9a%a1-setup-completion), otherwise use full path, or correct relative path>
```

## Details of what the script is doing

Register schema for customer

```bash
$ curl -X POST http://localhost:8081/subjects/customer/versions \
  --header 'Content-Type: application/vnd.schemaregistry.v1+json' \
  --data '
{
    "schema": "{\"fields\":[{\"name\":\"customer_id\",\"type\":\"int\"},{\"name\":\"customer_name\",\"type\":\"string\"},{\"name\":\"customer_email\",\"type\":\"string\"},{\"name\":\"customer_address\",\"type\":\"string\"}],\"name\":\"Customer\",\"namespace\":\"io.confluent.examples.avro\",\"type\":\"record\"}"

}'
```

Register schema for product

```bash
$ curl -X POST http://localhost:8081/subjects/product/versions \
  --header 'Content-Type: application/vnd.schemaregistry.v1+json' \
  --data '
{
    "schema": "{\"fields\":[{\"name\":\"product_id\",\"type\":\"int\"},{\"name\":\"product_name\",\"type\":\"string\"},{\"name\":\"product_price\",\"type\":\"double\"}],\"name\":\"Product\",\"namespace\":\"io.confluent.examples.avro\",\"type\":\"record\"}"
}'
```

Register schema for all-types

```bash
$ curl -X POST http://localhost:8081/subjects/all-types-value/versions \
  --header 'Content-Type: application/vnd.schemaregistry.v1+json' \
  --data '
{
    "schema": "[\"io.confluent.examples.avro.Customer\",\"io.confluent.examples.avro.Product\"]",
    "references": [
      {
        "name": "io.confluent.examples.avro.Customer",
        "subject":  "customer",
        "version": 1
      },
      {
        "name": "io.confluent.examples.avro.Product",
        "subject":  "product",
        "version": 1
      }
    ]
}'
```

Get schema id for all-types

```bash
id=$(curl http://localhost:8081/subjects/customer/versions/1/referencedby | tr -d '[' | tr -d ']')
```

Produce some Customer and Product data in topic all-types

```bash
$ docker exec -i connect kafka-avro-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic all-types --property value.schema.id=$id --property auto.register.schemas=false --property use.latest.version=true << EOF
{ "io.confluent.examples.avro.Product": { "product_id": 1, "product_name" : "rice", "product_price" : 100.00 } }
{ "io.confluent.examples.avro.Customer": { "customer_id": 100, "customer_name": "acme", "customer_email": "acme@google.com", "customer_address": "1 Main St" } }
EOF
```

Check that data is there

```bash
playground topic consume --topic all-types --min-expected-messages 2 --timeout 60
```
