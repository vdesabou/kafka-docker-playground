// .NET producer and consumer of kafka-docker-playground, with the Confluent .NET client (Confluent.Kafka, built on
// librdkafka) and its Avro serializer for Schema Registry (Confluent.SchemaRegistry.Serdes.Avro).
//
// usage: dotnet ClientDotnet.dll produce|consume|produce-avro|consume-avro <topic> <config file> [<number of messages>]
//
// The config file has one librdkafka property per line (key=value, # for comments): bootstrap.servers,
// security.protocol, sasl.*, ssl.*… The keys starting with schema.registry. (schema.registry.url,
// schema.registry.basic.auth.user.info…) go to the Schema Registry client.
//
// produce / produce-avro send <number of messages> records (10 by default), key "alice", and wait for every
// acknowledgement. consume / consume-avro read from the beginning of the topic with group <topic>-group (unless the
// config file sets group.id), commit, and exit with code 1 if fewer than <number of messages> records arrive within
// 60 seconds.

using Avro;
using Avro.Generic;
using Confluent.Kafka;
using Confluent.Kafka.SyncOverAsync;
using Confluent.SchemaRegistry;
using Confluent.SchemaRegistry.Serdes;

const string AvroSchema = @"{
  ""type"": ""record"",
  ""name"": ""User"",
  ""namespace"": ""io.confluent.playground"",
  ""fields"": [
    { ""name"": ""name"", ""type"": ""string"" },
    { ""name"": ""count"", ""type"": ""int"" }
  ]
}";
const int ConsumeTimeoutSeconds = 60;

if (args.Length < 3 || args.Length > 4)
{
    Console.Error.WriteLine("usage: dotnet ClientDotnet.dll produce|consume|produce-avro|consume-avro <topic> <config file> [<number of messages>]");
    return 1;
}

var mode = args[0];
var topic = args[1];
var nbMessages = args.Length == 4 ? int.Parse(args[3]) : 10;
var (clientProps, schemaRegistryProps) = LoadConfig(args[2]);

try
{
    switch (mode)
    {
        case "produce":
            return await ProduceStrings(topic, clientProps, nbMessages);
        case "consume":
            return ConsumeStrings(topic, clientProps, nbMessages);
        case "produce-avro":
            return await ProduceAvro(topic, clientProps, schemaRegistryProps, nbMessages);
        case "consume-avro":
            return ConsumeAvro(topic, clientProps, schemaRegistryProps, nbMessages);
        default:
            Console.Error.WriteLine($"unknown mode {mode}: produce, consume, produce-avro or consume-avro");
            return 1;
    }
}
catch (Exception e)
{
    Console.Error.WriteLine($"❌ {mode} failed: {e.GetType().Name}: {e.Message}");
    return 1;
}

// librdkafka properties and Schema Registry properties (schema.registry.*) of a key=value file
static (Dictionary<string, string>, Dictionary<string, string>) LoadConfig(string path)
{
    var client = new Dictionary<string, string>();
    var schemaRegistry = new Dictionary<string, string>();
    foreach (var raw in File.ReadAllLines(path))
    {
        var line = raw.Trim();
        var eq = line.IndexOf('=');
        if (line.Length == 0 || line.StartsWith('#') || eq <= 0)
        {
            continue;
        }
        var key = line[..eq].Trim();
        var value = line[(eq + 1)..].Trim();
        (key.StartsWith("schema.registry.") ? schemaRegistry : client)[key] = value;
    }
    return (client, schemaRegistry);
}

static ConsumerConfig ConsumerConfigOf(Dictionary<string, string> props, string topic)
{
    var config = new ConsumerConfig(new Dictionary<string, string>(props));
    config.GroupId ??= $"{topic}-group";
    config.AutoOffsetReset ??= AutoOffsetReset.Earliest;
    config.EnableAutoCommit ??= false;
    return config;
}

static CachedSchemaRegistryClient SchemaRegistryClientOf(Dictionary<string, string> props)
{
    if (!props.ContainsKey("schema.registry.url"))
    {
        throw new ArgumentException("schema.registry.url is missing in the config file");
    }
    return new CachedSchemaRegistryClient(props);
}

static async Task<int> ProduceStrings(string topic, Dictionary<string, string> props, int nbMessages)
{
    using var producer = new ProducerBuilder<string, string>(new ProducerConfig(new Dictionary<string, string>(props)))
        .SetErrorHandler((_, e) => Console.WriteLine($"Error: {e.Reason}"))
        .Build();
    for (var i = 0; i < nbMessages; i++)
    {
        var value = $"{{\"name\":\"alice\",\"count\":{i}}}";
        // throws a ProduceException when the record is not acknowledged
        var report = await producer.ProduceAsync(topic, new Message<string, string> { Key = "alice", Value = value });
        Console.WriteLine($"Produced record alice {value} to {report.TopicPartitionOffset}");
    }
    Console.WriteLine($"✅ {nbMessages} record(s) produced to topic {topic}");
    return 0;
}

static async Task<int> ProduceAvro(string topic, Dictionary<string, string> props, Dictionary<string, string> schemaRegistryProps,
                                   int nbMessages)
{
    var schema = (RecordSchema)Avro.Schema.Parse(AvroSchema);
    using var schemaRegistry = SchemaRegistryClientOf(schemaRegistryProps);
    // registers the schema under the subject <topic>-value (TopicNameStrategy) with the first record
    using var producer = new ProducerBuilder<string, GenericRecord>(new ProducerConfig(new Dictionary<string, string>(props)))
        .SetValueSerializer(new AvroSerializer<GenericRecord>(schemaRegistry))
        .SetErrorHandler((_, e) => Console.WriteLine($"Error: {e.Reason}"))
        .Build();
    for (var i = 0; i < nbMessages; i++)
    {
        var record = new GenericRecord(schema);
        record.Add("name", "alice");
        record.Add("count", i);
        var report = await producer.ProduceAsync(topic, new Message<string, GenericRecord> { Key = "alice", Value = record });
        Console.WriteLine($"Produced Avro record alice {{name=alice, count={i}}} to {report.TopicPartitionOffset}");
    }
    Console.WriteLine($"✅ {nbMessages} Avro record(s) produced to topic {topic}");
    return 0;
}

static int ConsumeStrings(string topic, Dictionary<string, string> props, int nbMessages)
{
    using var consumer = new ConsumerBuilder<string, string>(ConsumerConfigOf(props, topic))
        .SetErrorHandler((_, e) => Console.WriteLine($"Error: {e.Reason}"))
        .Build();
    return ConsumeLoop(consumer, topic, nbMessages, value => value);
}

static int ConsumeAvro(string topic, Dictionary<string, string> props, Dictionary<string, string> schemaRegistryProps, int nbMessages)
{
    using var schemaRegistry = SchemaRegistryClientOf(schemaRegistryProps);
    using var consumer = new ConsumerBuilder<string, GenericRecord>(ConsumerConfigOf(props, topic))
        .SetValueDeserializer(new AvroDeserializer<GenericRecord>(schemaRegistry).AsSyncOverAsync())
        .SetErrorHandler((_, e) => Console.WriteLine($"Error: {e.Reason}"))
        .Build();
    return ConsumeLoop(consumer, topic, nbMessages, value => $"{{name={value["name"]}, count={value["count"]}}}");
}

static int ConsumeLoop<TValue>(IConsumer<string, TValue> consumer, string topic, int nbMessages, Func<TValue, string> show)
{
    consumer.Subscribe(topic);
    var deadline = DateTime.UtcNow.AddSeconds(ConsumeTimeoutSeconds);
    var consumed = 0;
    try
    {
        while (consumed < nbMessages && DateTime.UtcNow < deadline)
        {
            var result = consumer.Consume(TimeSpan.FromSeconds(1));
            if (result == null || result.IsPartitionEOF)
            {
                continue;
            }
            consumed++;
            Console.WriteLine($"Consumed record with key {result.Message.Key} and value {show(result.Message.Value)} from {result.TopicPartitionOffset}");
        }
        if (consumed > 0)
        {
            // commits the offsets of the records consumed (enable.auto.commit=false)
            consumer.Commit();
        }
    }
    finally
    {
        consumer.Close();
    }
    if (consumed < nbMessages)
    {
        Console.Error.WriteLine($"❌ only {consumed} record(s) out of {nbMessages} consumed from topic {topic} in {ConsumeTimeoutSeconds} seconds");
        return 1;
    }
    Console.WriteLine($"✅ {consumed} record(s) consumed from topic {topic}");
    return 0;
}
