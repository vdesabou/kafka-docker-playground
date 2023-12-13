# Forward Compatibility, Specific Avro and reprocessing

This example showcase how the forward compatibility and the usage of specific Avro prevent data reprocessing.

TL;DR: Existing data reprocessing should be considered in your data compatibility strategy.

# Show me the code
You can find a full reproducer at [start.sh](./start.sh) and you can run it by runnng:
```
$ playground run -f start<use tab key to activate [fzf completion](https://kafka-docker-playground.io/#/cli?id=%e2%9a%a1-setup-completion) (otherwise use full path, i.e *not relative path*>
```

# Initial Situation

1. The Schema Registry is configured to use the [`FORWARD` compatibility mode](https://docs.confluent.io/platform/current/schema-registry/avro.html#forward-compatibility)
2. The initial version of Producer (`producer-v1`) and Consumer (`consumer-v1`) use the same `Customer v1` Avro schema.
2. The consumer enables the [`SPECIFIC_AVRO_READER_CONFIG` property](https://docs.confluent.io/platform/current/schema-registry/schema_registry_onprem_tutorial.html#example-consumer-code#:~:text=SPECIFIC_AVRO_READER_CONFIG) to use the Avro generated record as a classic POJO.
3. All parties auto-register schemas

# To Reproduce

1. The Producer decides to upgrade the schema and add a new mandatory field named `country`.
2. The Producer generates a new `Customer` POJO based on the Avro file, updates the code and release a new version named `producer-v2`
3. The Consumer retrieves the new Avro from a SCM or as an artefact from a content repository (Nexus, Artifactory, etc).
4. The Consumer generates a new `Customer` POJO based on the Avro file, updates the code and release a new version named `consumer-v2`.
5. Both applications are deployed, and `consumer-v2` consumes perfectly `Customer v2` record produced by `producer-v2`.
6. At some point, it is decided to reset the `customer-v2` offset in order to reprocess old message (ie. `Customer v1` messages).
7. The `consumer-v2` application crashes.

# StackTrace
```
Caused by: org.apache.kafka.common.errors.SerializationException: Error deserializing Avro message for id 1
Caused by: org.apache.avro.AvroTypeException: Found com.github.vdesabou.Customer, expecting com.github.vdesabou.Customer, missing required field country
    at org.apache.avro.io.ResolvingDecoder.doAction(ResolvingDecoder.java:309)
    at org.apache.avro.io.parsing.Parser.advance(Parser.java:86)
    at org.apache.avro.io.ResolvingDecoder.readFieldOrder(ResolvingDecoder.java:128)
    at org.apache.avro.generic.GenericDatumReader.readRecord(GenericDatumReader.java:239)
    at org.apache.avro.specific.SpecificDatumReader.readRecord(SpecificDatumReader.java:123)
    at org.apache.avro.generic.GenericDatumReader.readWithoutConversion(GenericDatumReader.java:179)
    at org.apache.avro.generic.GenericDatumReader.read(GenericDatumReader.java:160)
    at org.apache.avro.generic.GenericDatumReader.read(GenericDatumReader.java:153)
    at io.confluent.kafka.serializers.AbstractKafkaAvroDeserializer$DeserializationContext.read(AbstractKafkaAvroDeserializer.java:356)
    at io.confluent.kafka.serializers.AbstractKafkaAvroDeserializer.deserialize(AbstractKafkaAvroDeserializer.java:100)
    at io.confluent.kafka.serializers.AbstractKafkaAvroDeserializer.deserialize(AbstractKafkaAvroDeserializer.java:79)
    at io.confluent.kafka.serializers.KafkaAvroDeserializer.deserialize(KafkaAvroDeserializer.java:55)
    at org.apache.kafka.common.serialization.Deserializer.deserialize(Deserializer.java:60)
    at org.apache.kafka.clients.consumer.internals.Fetcher.parseRecord(Fetcher.java:1387)
    at org.apache.kafka.clients.consumer.internals.Fetcher.access$3400(Fetcher.java:133)
    at org.apache.kafka.clients.consumer.internals.Fetcher$CompletedFetch.fetchRecords(Fetcher.java:1618)
    at org.apache.kafka.clients.consumer.internals.Fetcher$CompletedFetch.access$1700(Fetcher.java:1454)
    at org.apache.kafka.clients.consumer.internals.Fetcher.fetchRecords(Fetcher.java:687)
    at org.apache.kafka.clients.consumer.internals.Fetcher.fetchedRecords(Fetcher.java:638)
    at org.apache.kafka.clients.consumer.KafkaConsumer.pollForFetches(KafkaConsumer.java:1299)
    at org.apache.kafka.clients.consumer.KafkaConsumer.poll(KafkaConsumer.java:1233)
    at org.apache.kafka.clients.consumer.KafkaConsumer.poll(KafkaConsumer.java:1206)
    at com.github.vdesabou.SimpleConsumer.start(SimpleConsumer.java:50)
    at com.github.vdesabou.SimpleConsumer.main(SimpleConsumer.java:28)
```
# What is happening

The usage of the `FORWARD` compatibility express the need to anticipate upcoming changes, be future proof.
In this scenario, the need to reprocess the past data isn't conceptually compatible with the `FORWARD` requirement expressed.

Avro proposes 2 data structures (https://docs.confluent.io/platform/current/streams/developer-guide/datatypes.html#avro):
* `GenericRecord`: The record is deserialized into a dictionnary structure (ie. a list of key,value pairs) like `java.util.Map`. In order, to get the data from the record, the developer ends up with `record.get("myFieldName")`, that means the schema contract isn't enforced by default. Very flexible from a structure stand point but not convenient to use in a business oriented processing.

* `SpecificRecord`: The record is deserialized into a POJO (ie. a clasic Java class with properties). The developer can use the classic `record.getMyFieldName()` to retrieve the information. More static but strong typing enforces the structure and generally speaking way more natural for developers.

In our case
- The Schema Regsistry enable the `FORWARD` comptaibility the producer can perfectly add a new mandatory field.
- The Consumer use a `SPECIFIC_RECORD`, thus uses an explicit `Customer v2` POJO with the `country` field.
- When the Consumer tries to reproccess the old messages, it tries to deserialize a `Customer v1` record and map it to a `Customer v2` POJO. Since the `v1` message has not the `country` mandatory field, the deserialization failed and the application crashes.

**Note on Kafka Stream**

While the repoducer is using a basic producer/consumer, the rationale works for Kafka Stream too.
Keep in mind that Kafka Streams uses topics under the hood for a lot of things (repartition, changelog, etc.) 

KStream defines an explicit [`SpecificAvroSerde`](https://docs.confluent.io/platform/current/streams/developer-guide/datatypes.html#avro) (ie. no need to set the `SPECIFIC_AVRO_READER_CONFIG`).

You should raise an alert as soon as you see the combo:
1. Old data persisted
2. Schema changes with mandatory fields addition or removal
3. Specific Avro records
4. Need of reprocessing

# How to fix

1. Use `GenericRecord` instead. Not recommended because you loose strong typing!
2. Only care about new data. 
3. Put the field optional (by adding null in the list of possible values), as such the Consumer would have been able to read existing messages OR new messages.
4. If you really want to enforce the new model you should think about migrating existing data (create a new topic for the new schema, tranform and migrate the old data to the new topic . Depending on the context, may be overkill.
