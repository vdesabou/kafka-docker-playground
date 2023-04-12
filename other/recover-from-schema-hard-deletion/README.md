# Recovery from schema hard deletion

## Context

When created schemas are created they got assigned a unique, monotonically increasing id.
This id is stored in the record payload when produced to Kafka.
On the consumer side, the consumer will be using this id to retrieve the schema from the schema registry to deserialize the payload.

When a schema is hard-deleted, it is not possible to recover it.
By not being able to retrieve the schema matching the id, the consumer will not be able to deserialize the payload.

Even if the deleted schema is recreated, the id will be different and the consumer will still not be able to deserialize the payload.

In most cases, the customers are storing a local a copy of the schema.
This repository is exploring how to deserialize a record with a local copy of the schema rather than relying on the Schema Registry.
Once the data is deserialized, the data can be produced again in Kafka using the re-registered schema thus used the new id.

## Solutions

### Mock the Schema Registry HTTP Server

The Schema Registry is an HTTP server serving schemas under the `/schemas/ids/{id}` endpoint.
One can mock this endpoint to return whatever schema.

[`WireMock`](https://wiremock.org/) is a tool to mock and stub HTTP servers.
WireMock will be serving whatver is hosted in the `__files` as is.
For example if a file exists `__files/schemas/ids/1` it'll be served as `http://<host>:<port>/schemas/ids/1` which match the Schema Registry API.

_Note: Wiremock proposes also a stubbing feature not detailled in this example._

#### How to run

Simplly run
```
$ ./start.sh
```
When done run the stop script to tears everything down
```
$ ./stop.sh
```

### Use a custom `SchemaRegistryClient` implementation

When deserializing the data, the `KavaAvroDeserializer` will be using the `SchemaRegistryClient`.
The default `SchemaRegistryClient` implementation force to connect to the Schema Registry to retrieve the schema.

One can provide a custom implementation of the `SchemaRegistryClient` to retrieve the schema from a local copy.

[./custom-schemaregistryclient-using-local-schemas] has a unit test named `CustomSchemaRegistryClientUsingLocalSchemasTest` showing how to provide a custom `SchemaRegistryClient` to the `KavaAvroDeserializer` to deserialize the payload into a `GenericRecord`. This custom implementation will served a fixed schema. Interestingly, the Schema Registry Client method invoked to retrieve the schema is `getSchemaBySubjectAndId` which require both the schema ID AND the subject (one could expect to just require the id and invoke the `getSchemaById` method.)


The test also explores the deserialization behavior when the provided schema does not match the record's one:
* The provided schema has less fields than the one used to serialized the message: The deserialization works and only fields defined in the provided schema are populated (ie. some fields from the record are ignore).
* The provided schema has more fields than the one used to serialized the message: The deserialization *does not* and generate a `SerializationException `and only fields defined in the provided schema are populated (ie. some fields from the record are ignore).
