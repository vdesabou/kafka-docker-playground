package io.confluent.developer;

import org.apache.kafka.clients.admin.AdminClient;
import org.apache.kafka.clients.admin.NewTopic;
import org.apache.kafka.common.serialization.Serdes;
import org.apache.kafka.streams.KafkaStreams;
import org.apache.kafka.streams.StreamsBuilder;
import org.apache.kafka.streams.StreamsConfig;
import org.apache.kafka.streams.Topology;
import org.apache.kafka.streams.kstream.Consumed;
import org.apache.kafka.streams.kstream.Produced;

import java.io.FileInputStream;
import java.io.IOException;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Properties;
import java.util.concurrent.CountDownLatch;

import io.confluent.developer.avro.Publication;
import io.confluent.kafka.serializers.AbstractKafkaAvroSerDeConfig;
import io.confluent.kafka.streams.serdes.avro.SpecificAvroSerde;

public class FilterEvents {

  public Properties buildStreamsProperties(Properties envProps) {
    Properties props = new Properties();

    props.put(StreamsConfig.APPLICATION_ID_CONFIG, envProps.getProperty("application.id"));
    props.put(StreamsConfig.BOOTSTRAP_SERVERS_CONFIG, envProps.getProperty("bootstrap.servers"));
    props.put(StreamsConfig.DEFAULT_KEY_SERDE_CLASS_CONFIG, Serdes.String().getClass());
    props.put(StreamsConfig.DEFAULT_VALUE_SERDE_CLASS_CONFIG, Serdes.String().getClass());
    props.put(AbstractKafkaAvroSerDeConfig.SCHEMA_REGISTRY_URL_CONFIG, envProps.getProperty("schema.registry.url"));
    props.put(StreamsConfig.CACHE_MAX_BYTES_BUFFERING_CONFIG, 0);

    return props;
  }

  private SpecificAvroSerde<Publication> publicationSerde(final Properties envProps) {
    final SpecificAvroSerde<Publication> serde = new SpecificAvroSerde<>();
    Map<String, String> config = new HashMap<>();
    config.put(AbstractKafkaAvroSerDeConfig.SCHEMA_REGISTRY_URL_CONFIG, envProps.getProperty("schema.registry.url"));
    serde.configure(config, false);
    return serde;
  }

  public Topology buildTopology(Properties envProps,
                                final SpecificAvroSerde<Publication> publicationSerde) {
    final StreamsBuilder builder = new StreamsBuilder();

    final String inputTopic = envProps.getProperty("input.topic.name");
    final String outputTopic = envProps.getProperty("output.topic.name");

    builder.stream(inputTopic, Consumed.with(Serdes.String(), publicationSerde))
        .filter((name, publication) -> "George R. R. Martin".equals(publication.getName()))
        .to(outputTopic, Produced.with(Serdes.String(), publicationSerde));

    return builder.build();
  }

  public void createTopics(Properties envProps) {
    Map<String, Object> config = new HashMap<>();
    config.put("bootstrap.servers", envProps.getProperty("bootstrap.servers"));
    AdminClient client = AdminClient.create(config);

    List<NewTopic> topics = new ArrayList<>();
    topics.add(new NewTopic(
        envProps.getProperty("input.topic.name"),
        Integer.parseInt(envProps.getProperty("input.topic.partitions")),
        Short.parseShort(envProps.getProperty("input.topic.replication.factor"))));
    topics.add(new NewTopic(
        envProps.getProperty("output.topic.name"),
        Integer.parseInt(envProps.getProperty("output.topic.partitions")),
        Short.parseShort(envProps.getProperty("output.topic.replication.factor"))));

    client.createTopics(topics);
    client.close();
  }

  public Properties loadEnvProperties(String fileName) throws IOException {
    Properties envProps = new Properties();
    FileInputStream input = new FileInputStream(fileName);
    envProps.load(input);
    input.close();

    return envProps;
  }

  public static void main(String[] args) throws IOException {
    if (args.length < 1) {
      throw new IllegalArgumentException(
          "This program takes one argument: the path to an environment configuration file.");
    }

    new FilterEvents().runRecipe(args[0]);
  }

  private void runRecipe(final String configPath) throws IOException {
    Properties envProps = this.loadEnvProperties(configPath);
    Properties streamProps = this.buildStreamsProperties(envProps);

    Topology topology = this.buildTopology(envProps, this.publicationSerde(envProps));
    this.createTopics(envProps);

    final KafkaStreams streams = new KafkaStreams(topology, streamProps);
    final CountDownLatch latch = new CountDownLatch(1);

    // Attach shutdown handler to catch Control-C.
    Runtime.getRuntime().addShutdownHook(new Thread("streams-shutdown-hook") {
      @Override
      public void run() {
        streams.close();
        latch.countDown();
      }
    });

    try {
      streams.start();
      latch.await();
    } catch (Throwable e) {
      System.exit(1);
    }
    System.exit(0);

  }
}