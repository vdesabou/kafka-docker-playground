# How to produce Avro records with kafka-avro-console-producer with UNION type

## Objective

With Apache Avro, you can set a field as an UNION of two types. A union datatype is used whenever the field has one or more datatypes. For example, ["null", "string"] declares a schema which may be either a null or string.

Union type can be useful for Optional fields:
```
{
  "type":"record",
  "name":"myrecord",
  "fields":[
    { "name":"id", "type":"int"},
    { "name":"product", "type":"string"},
    { "name":"quantity", "type":"int"},
    {
      "name":"description",
      "type":[
        "null",
        "string"
      ],
      "default":null
    }
  ]
}
```

But it can be also useful for putting several Event Types in the same topic:
```
[
  "io.confluent.examples.avro.Customer",
  "io.confluent.examples.avro.Product",
  "io.confluent.examples.avro.Payment"
]
```

To produce an Avro record to your topic with the kafka-avro-console-producer, you need to specify your type when there is an Union.

For example, if you have a topic with the following Avro schema:
```
[
    "io.confluent.examples.avro.Customer",
    "io.confluent.examples.avro.Product"
]
```
With references to the following schemas:
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
and
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

You will need to specify which type you are using. For example:
```
./bin/kafka-avro-console-producer --broker-list localhost:9092 --topic all-types --property value.schema.id={id} --property auto.register=false --property use.latest.version=true

{ "io.confluent.examples.avro.Product": { "product_id": 1, "product_name" : "rice", "product_price" : 100.00 } }
{ "io.confluent.examples.avro.Customer": { "customer_id": 100, "customer_name": "acme", "customer_email": "acme@google.com", "customer_address": "1 Main St" } }
```

## How to run

Simply run:

```
$ playground run -f start<tab>
```

## Resources
https://avro.apache.org/docs/1.10.2/spec.html#Unions
https://www.confluent.io/blog/multiple-event-types-in-the-same-kafka-topic
https://federico.is/posts/2020/07/30/avro-unions-and-default-values/
