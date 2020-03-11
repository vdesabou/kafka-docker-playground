package io.confluent.developer;

import io.confluent.developer.avro.MovieTicketSales;
import io.confluent.developer.avro.YearlyMovieFigures;
import org.apache.kafka.clients.admin.AdminClient;
import org.apache.kafka.clients.admin.NewTopic;
import org.apache.kafka.common.serialization.Serdes;
import org.apache.kafka.streams.*;
import org.apache.kafka.streams.kstream.*;

import java.io.FileInputStream;
import java.io.IOException;
import java.util.*;
import java.util.concurrent.CountDownLatch;
import java.time.Duration;

import io.confluent.kafka.serializers.AbstractKafkaAvroSerDeConfig;
import io.confluent.kafka.streams.serdes.avro.SpecificAvroSerde;

public class AggregatingMinMax {

  public static Properties loadPropertiesFromConfigFile(String fileName) throws IOException {
    Properties envProps = new Properties();
    try (FileInputStream fileStream = new FileInputStream(fileName)) {
      envProps.load(fileStream);
    }
    return envProps;
  }
  public static Properties buildStreamsProperties(Properties envProps) {
    Properties props = new Properties();

    props.put(StreamsConfig.APPLICATION_ID_CONFIG, envProps.getProperty("application.id"));
    props.put(StreamsConfig.BOOTSTRAP_SERVERS_CONFIG, envProps.getProperty("bootstrap.servers"));
    props.put(AbstractKafkaAvroSerDeConfig.SCHEMA_REGISTRY_URL_CONFIG, envProps.getProperty("schema.registry.url"));
    props.put(StreamsConfig.CACHE_MAX_BYTES_BUFFERING_CONFIG, 0);

    return props;
  }
  public static SpecificAvroSerde<MovieTicketSales> ticketSaleSerde(final Properties envProps) {
    final SpecificAvroSerde<MovieTicketSales> serde = new SpecificAvroSerde<>();
    serde.configure(Collections.singletonMap(
            AbstractKafkaAvroSerDeConfig.SCHEMA_REGISTRY_URL_CONFIG,
            envProps.getProperty("schema.registry.url")), false);
    return serde;
  }
  public static SpecificAvroSerde<YearlyMovieFigures> movieFiguresSerde(final Properties envProps) {
    final SpecificAvroSerde<YearlyMovieFigures> serde = new SpecificAvroSerde<>();
    serde.configure(Collections.singletonMap(
      AbstractKafkaAvroSerDeConfig.SCHEMA_REGISTRY_URL_CONFIG, envProps.getProperty("schema.registry.url")
    ), false);
    return serde;
  }

  private static void createKafkaTopicsInCluster(final AdminClient adminClient, final Properties envProps) {
    adminClient.createTopics(Arrays.asList(
            new NewTopic(
                    envProps.getProperty("input.topic.name"),
                    Integer.parseInt(envProps.getProperty("input.topic.partitions")),
                    Short.parseShort(envProps.getProperty("input.topic.replication.factor"))),
            new NewTopic(
                    envProps.getProperty("output.topic.name"),
                    Integer.parseInt(envProps.getProperty("output.topic.partitions")),
                    Short.parseShort(envProps.getProperty("output.topic.replication.factor")))));
  }

  public static void runRecipe(final String configPath) throws IOException {

    Properties envProps = AggregatingMinMax.loadPropertiesFromConfigFile(configPath);

    try ( AdminClient client = AdminClient.create(
            Collections.singletonMap("bootstrap.servers", envProps.getProperty("bootstrap.servers")))) {
      createKafkaTopicsInCluster(client, envProps);
    }

    Topology topology = AggregatingMinMax.buildTopology(
            new StreamsBuilder(),
            envProps,
            AggregatingMinMax.ticketSaleSerde(envProps),
            AggregatingMinMax.movieFiguresSerde(envProps));

    final KafkaStreams streams = new KafkaStreams(
            topology,
            AggregatingMinMax.buildStreamsProperties(envProps));
    final CountDownLatch latch = new CountDownLatch(1);

    // Attach shutdown handler to catch Control-C.
    Runtime.getRuntime().addShutdownHook(new Thread("streams-shutdown-hook") {
      @Override
      public void run() {
				streams.close(Duration.ofSeconds(5));
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

  public static Topology buildTopology(final StreamsBuilder builder,
                                final Properties envProps,
                                final SpecificAvroSerde<MovieTicketSales> ticketSaleSerde,
                                final SpecificAvroSerde<YearlyMovieFigures> movieFiguresSerde) {

    final String inputTopic = envProps.getProperty("input.topic.name");
    final String outputTopic = envProps.getProperty("output.topic.name");

    builder.stream(inputTopic, Consumed.with(Serdes.String(), ticketSaleSerde))
         .groupBy(
                 (k, v) -> v.getReleaseYear(),
                 Grouped.with(Serdes.Integer(), ticketSaleSerde))
         .aggregate(
                 () -> new YearlyMovieFigures(0, Integer.MAX_VALUE, Integer.MIN_VALUE),
                 ((key, value, aggregate) ->
                         new YearlyMovieFigures(key,
                                 Math.min(value.getTotalSales(), aggregate.getMinTotalSales()),
                                 Math.max(value.getTotalSales(), aggregate.getMaxTotalSales()))),
                 Materialized.with(Serdes.Integer(), movieFiguresSerde))
         .toStream()
         .to(outputTopic, Produced.with(Serdes.Integer(), movieFiguresSerde));

    return builder.build();
  }

  public static void main(String[] args) throws IOException {
    if (args.length < 1) {
      throw new IllegalArgumentException(
          "This program takes one argument: the path to an environment configuration file.");
    }

    new AggregatingMinMax().runRecipe(args[0]);
  }

}