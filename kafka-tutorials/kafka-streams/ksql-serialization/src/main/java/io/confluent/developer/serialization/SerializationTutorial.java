package io.confluent.developer.serialization;

import org.apache.kafka.clients.admin.AdminClient;
import org.apache.kafka.clients.admin.NewTopic;
import org.apache.kafka.streams.KafkaStreams;
import org.apache.kafka.streams.StreamsBuilder;
import org.apache.kafka.streams.StreamsConfig;
import org.apache.kafka.streams.Topology;
import org.apache.kafka.streams.kstream.Consumed;
import org.apache.kafka.streams.kstream.KStream;
import org.apache.kafka.streams.kstream.Produced;

import java.io.FileInputStream;
import java.io.IOException;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Properties;
import java.util.concurrent.CountDownLatch;

import io.confluent.developer.avro.Movie;
import io.confluent.developer.serialization.serde.MovieJsonSerde;
import io.confluent.kafka.serializers.AbstractKafkaAvroSerDeConfig;
import io.confluent.kafka.streams.serdes.avro.SpecificAvroSerde;

import static java.lang.Integer.parseInt;
import static java.lang.Short.parseShort;
import static org.apache.kafka.common.serialization.Serdes.Long;
import static org.apache.kafka.common.serialization.Serdes.String;

public class SerializationTutorial {

  protected Properties buildStreamsProperties(Properties envProps) {
    Properties props = new Properties();

    props.put(StreamsConfig.APPLICATION_ID_CONFIG, envProps.getProperty("application.id"));
    props.put(StreamsConfig.BOOTSTRAP_SERVERS_CONFIG, envProps.getProperty("bootstrap.servers"));
    props.put(StreamsConfig.DEFAULT_KEY_SERDE_CLASS_CONFIG, String().getClass());
    props.put(StreamsConfig.DEFAULT_VALUE_SERDE_CLASS_CONFIG, String().getClass());
    props.put(AbstractKafkaAvroSerDeConfig.SCHEMA_REGISTRY_URL_CONFIG, envProps.getProperty("schema.registry.url"));

    return props;
  }

  private void createTopics(Properties envProps) {
    Map<String, Object> config = new HashMap<>();

    config.put("bootstrap.servers", envProps.getProperty("bootstrap.servers"));
    AdminClient client = AdminClient.create(config);

    List<NewTopic> topics = new ArrayList<>();

    topics.add(new NewTopic(
        envProps.getProperty("input.json.movies.topic.name"),
        parseInt(envProps.getProperty("input.json.movies.topic.partitions")),
        parseShort(envProps.getProperty("input.json.movies.topic.replication.factor"))));

    topics.add(new NewTopic(
        envProps.getProperty("output.avro.movies.topic.name"),
        parseInt(envProps.getProperty("output.avro.movies.topic.partitions")),
        parseShort(envProps.getProperty("output.avro.movies.topic.replication.factor"))));

    client.createTopics(topics);
    client.close();
  }

  private SpecificAvroSerde<Movie> movieAvroSerde(Properties envProps) {
    SpecificAvroSerde<Movie> movieAvroSerde = new SpecificAvroSerde<>();

    final HashMap<String, String> serdeConfig = new HashMap<>();
    serdeConfig.put(AbstractKafkaAvroSerDeConfig.SCHEMA_REGISTRY_URL_CONFIG,
                    envProps.getProperty("schema.registry.url"));

    movieAvroSerde.configure(serdeConfig, false);
    return movieAvroSerde;
  }

  protected Topology buildTopology(Properties envProps, final SpecificAvroSerde<Movie> movieSpecificAvroSerde) {
    final String inputJsonTopicName = envProps.getProperty("input.json.movies.topic.name");
    final String outAvroTopicName = envProps.getProperty("output.avro.movies.topic.name");

    final StreamsBuilder builder = new StreamsBuilder();

    // topic contains values in json format
    final KStream<Long, Movie> jsonMovieStream =
        builder.stream(inputJsonTopicName, Consumed.with(Long(), new MovieJsonSerde()));

    // write movie data in avro format
    jsonMovieStream.to(outAvroTopicName, Produced.with(Long(), movieSpecificAvroSerde));

    return builder.build();
  }

  protected Properties loadEnvProperties(String fileName) throws IOException {
    Properties envProps = new Properties();
    FileInputStream input = new FileInputStream(fileName);
    envProps.load(input);
    input.close();
    return envProps;
  }

  private void runTutorial(String configPath) throws IOException {
    Properties envProps = this.loadEnvProperties(configPath);
    Properties streamProps = this.buildStreamsProperties(envProps);
    Topology topology = this.buildTopology(envProps, this.movieAvroSerde(envProps));

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

  public static void main(String[] args) throws IOException {
    if (args.length < 1) {
      throw new IllegalArgumentException(
          "This program takes one argument: the path to an environment configuration file.");
    }

    new SerializationTutorial().runTutorial(args[0]);
  }
}