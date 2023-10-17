# Putting Several Event Types in the Same Topic with Schema Registry API

## Objective

We register a first Avro schema for Product:
```
{
    "type": "record",
    "namespace": "io.confluent.examples.avro",
    "name": "Product",
        "fields": [
      {"name": "product_id", "type": "int"},
      {"name": "product_name", "type": "string"},
      {"name": "product_price", "type": "double"}
    ]
}
```
and the schema for Customer:
```
{
    "type": "record",
    "namespace": "io.confluent.examples.avro",
    "name": "Customer",
    "fields": [
        { "name": "customer_id", "type": "int" },
        { "name": "customer_name", "type": "string" },
        { "name": "customer_email", "type": "string" },
        { "name": "customer_address", "type": "string" }
    ]
}
```
Then we can register a new schema for topic alltypes with Schema References to these two schemas:
```
curl -s -H "Content-Type: application/vnd.schemaregistry.v1+json" \
  -X POST http://schema-registry:8081/subjects/alltypes-value/versions \
  --data '{"schema":"[\"io.confluent.examples.avro.Customer\",\"io.confluent.examples.avro.Product\"]","schemaType":"AVRO","references":[{"name":"io.confluent.examples.avro.Customer","subject":"customer-value","version":1},{"name":"io.confluent.examples.avro.Product","subject":"product-value","version":1}]}'
```


To learn more about Schema Reference, see the example given below in [Multiple event types in the same topic](https://docs.confluent.io/platform/current/schema-registry/fundamentals/serdes-develop/serdes-avro.html#multiple-event-types-same-topic-avro), the associated [blog post](https://www.confluent.io/blog/multiple-event-types-in-the-same-kafka-topic/), and the API example for how to register (create) a new schema in [POST /subjects/(string: subject)/versions](https://docs.confluent.io/platform/7.5/schema-registry/develop/api.html#api-example-avro-schema-references)

## How to run

Simply run:

```
$ playground run -f start<tab>
```

## Resources
https://www.confluent.io/blog/multiple-event-types-in-the-same-kafka-topic
