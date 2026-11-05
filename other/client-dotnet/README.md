# .NET client (producer/consumer)

## Objective

Quickly test the [Confluent .NET Client for Apache Kafka](https://docs.confluent.io/kafka-clients/dotnet/current/overview.html) (NuGet [`Confluent.Kafka`](https://www.nuget.org/packages/Confluent.Kafka), built on librdkafka) and its Avro serializer for Schema Registry ([`Confluent.SchemaRegistry.Serdes.Avro`](https://www.nuget.org/packages/Confluent.SchemaRegistry.Serdes.Avro)) against a local Confluent Platform cluster.

## How to run

```bash
playground run -f start.sh
```

| Script | Description |
| --- | --- |
| `start.sh` | .NET producer and consumer, string and Avro records, in the `client-dotnet` container, against the plaintext broker and Schema Registry |

## What the script does

1. Starts only the `client-dotnet` container and what it depends on (broker, Schema Registry), with `playground start-environment --service client-dotnet`. The image is built from the `Dockerfile` (.NET 10 SDK, `dotnet publish` of [`Program.cs`](Program.cs) with `Confluent.Kafka` and `Confluent.SchemaRegistry.Serdes.Avro` 2.16.0 from [`ClientDotnet.csproj`](ClientDotnet.csproj)). The first build takes a minute or two. The client reads its configuration from [`client.properties`](client.properties), mounted in `/tmp/client.properties`: one librdkafka property per line, plus the `schema.registry.*` properties of the Schema Registry client.
2. Creates topics `dotnet-string` and `dotnet-avro` with 3 partitions.
3. Produces 10 string records (key `alice`, value `{"name":"alice","count":<i>}`) and waits for every acknowledgement, then consumes them with group `dotnet-string-group`. The consumer exits with an error if fewer than 10 records arrive within 60 seconds:

   ```bash
   playground container exec -c client-dotnet --command "dotnet ClientDotnet.dll produce dotnet-string /tmp/client.properties 10"
   playground container exec -c client-dotnet --command "dotnet ClientDotnet.dll consume dotnet-string /tmp/client.properties 10"
   ```

4. Same with Avro records (`GenericRecord` of schema `io.confluent.playground.User` with fields `name` and `count`): `AvroSerializer` registers the schema under subject `dotnet-avro-value`, `AvroDeserializer` reads it back:

   ```bash
   playground container exec -c client-dotnet --command "dotnet ClientDotnet.dll produce-avro dotnet-avro /tmp/client.properties 10"
   playground container exec -c client-dotnet --command "dotnet ClientDotnet.dll consume-avro dotnet-avro /tmp/client.properties 10"
   ```

5. Shows the schema registered under subject `dotnet-avro-value` with `playground schema get`, and the committed offsets of both groups with `playground consumer-group describe`.

To try your own client code or configuration, edit `Program.cs` (rebuild with `playground container recreate`) or `client.properties` (read at each run, no rebuild needed).

## Use another client version

Set `CLIENT_VERSION` to build the image with another Confluent.Kafka and Confluent.SchemaRegistry.Serdes.Avro version than the default, the version of `ClientDotnet.csproj`:

```bash
CLIENT_VERSION=2.10.1 playground run -f start.sh
playground run -f start.sh --client-version 2.10.1   # the same, also offered by the interactive menu
```

Empty or unset: the default version. The client prints its version when it starts, check it in the output. It is passed as a build argument by `docker-compose.plaintext.yml`. An old version may not support everything the example uses (the Avro serializer API changed over time).
