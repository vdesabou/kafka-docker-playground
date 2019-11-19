# JSON Producer Example

This example code publishes randomly generated airport weather reports to a
Kafka topic in JSON format (without schema). Make sure any sink connectors
subscribed to the topic are configured with the following properties:

    key.converter=org.apache.kafka.connect.storage.StringConverter
    value.converter=org.apache.kafka.connect.json.JsonConverter
    value.converter.schemas.enable=false

These properties may be applied as global defaults in the connect worker config,
and may be overridden on a per-connector basis in the connect plugin config.


## Configurability (Lack Thereof)

This example assumes there is a Kafka broker running on localhost, listening
on the default port. The topic name is hard-coded. Feel free to edit the
source code if you want to change any of these settings.


## Running the Example

From this directory, run the producer with the Maven command:

    mvn compile exec:java

The producer will publish some random messages, then terminate.


## What About Avro?

Kafka Connect Couchbase works with Avro, too! Just configure the
`key.converter` and `value.converter` properties to match
the format of the Kafka messages. The Confluent team have some
[very nice examples](https://github.com/confluentinc/examples)
showing how to produce Kafka messages in Avro format.
