package io.confluent.developer;

import io.confluent.developer.avro.Click;
import org.apache.kafka.clients.admin.AdminClient;
import org.apache.kafka.clients.admin.NewTopic;
import org.apache.kafka.common.serialization.Serdes;
import org.apache.kafka.streams.*;
import org.apache.kafka.streams.kstream.Consumed;

import java.io.FileInputStream;
import java.io.IOException;
import java.time.Duration;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Properties;
import java.util.concurrent.CountDownLatch;

import io.confluent.kafka.serializers.AbstractKafkaAvroSerDeConfig;
import io.confluent.kafka.streams.serdes.avro.SpecificAvroSerde;
import org.apache.kafka.streams.kstream.KeyValueMapper;
import org.apache.kafka.streams.kstream.Produced;
import org.apache.kafka.streams.kstream.Transformer;
import org.apache.kafka.streams.processor.ProcessorContext;
import org.apache.kafka.streams.state.StoreBuilder;
import org.apache.kafka.streams.state.Stores;
import org.apache.kafka.streams.state.WindowStore;
import org.apache.kafka.streams.state.WindowStoreIterator;

public class FindDistinctEvents {

  private static final String storeName = "eventId-store";

  /**
   * Discards duplicate click events from the input stream by ip address
   * <p>
   * Duplicate records are detected based on ip address
   * The transformer remembers known ip addresses within an associated window state
   * store, which automatically purges/expires IPs from the store after a certain amount of
   * time has passed to prevent the store from growing indefinitely.
   * <p>
   * Note: This code is for demonstration purposes and was not tested for production usage.
   */
  private static class DeduplicationTransformer<K, V, E> implements Transformer<K, V, KeyValue<K, V>> {

    private ProcessorContext context;

    /**
     * Key: ip address
     * Value: timestamp (event-time) of the corresponding event when the event ID was seen for the
     * first time
     */
    private WindowStore<E, Long> eventIdStore;

    private final long leftDurationMs;
    private final long rightDurationMs;

    private final KeyValueMapper<K, V, E> idExtractor;

    /**
     * @param maintainDurationPerEventInMs how long to "remember" a known ip address
     *                                     during the time of which any incoming duplicates
     *                                     will be dropped, thereby de-duplicating the
     *                                     input.
     * @param idExtractor                  extracts a unique identifier from a record by which we de-duplicate input
     *                                     records; if it returns null, the record will not be considered for
     *                                     de-duping but forwarded as-is.
     */
    DeduplicationTransformer(final long maintainDurationPerEventInMs, final KeyValueMapper<K, V, E> idExtractor) {
      if (maintainDurationPerEventInMs < 1) {
        throw new IllegalArgumentException("maintain duration per event must be >= 1");
      }
      leftDurationMs = maintainDurationPerEventInMs / 2;
      rightDurationMs = maintainDurationPerEventInMs - leftDurationMs;
      this.idExtractor = idExtractor;
    }

    @Override
    @SuppressWarnings("unchecked")
    public void init(final ProcessorContext context) {
      this.context = context;
      eventIdStore = (WindowStore<E, Long>) context.getStateStore(storeName);
    }

    public KeyValue<K, V> transform(final K key, final V value) {
      final E eventId = idExtractor.apply(key, value);
      if (eventId == null) {
        return KeyValue.pair(key, value);
      } else {
        final KeyValue<K, V> output;
        if (isDuplicate(eventId)) {
          output = null;
          updateTimestampOfExistingEventToPreventExpiry(eventId, context.timestamp());
        } else {
          output = KeyValue.pair(key, value);
          rememberNewEvent(eventId, context.timestamp());
        }
        return output;
      }
    }

    private boolean isDuplicate(final E eventId) {
      final long eventTime = context.timestamp();
      final WindowStoreIterator<Long> timeIterator = eventIdStore.fetch(
              eventId,
              eventTime - leftDurationMs,
              eventTime + rightDurationMs);
      final boolean isDuplicate = timeIterator.hasNext();
      timeIterator.close();
      return isDuplicate;
    }

    private void updateTimestampOfExistingEventToPreventExpiry(final E eventId, final long newTimestamp) {
      eventIdStore.put(eventId, newTimestamp, newTimestamp);
    }

    private void rememberNewEvent(final E eventId, final long timestamp) {
      eventIdStore.put(eventId, timestamp, timestamp);
    }

    @Override
    public void close() {
      // Note: The store should NOT be closed manually here via `eventIdStore.close()`!
      // The Kafka Streams API will automatically close stores when necessary.
    }

  }

  private SpecificAvroSerde<Click> buildClicksSerde(final Properties envProps) {
    final SpecificAvroSerde<Click> serde = new SpecificAvroSerde<>();
    Map<String, String> config = new HashMap<>();
    config.put(AbstractKafkaAvroSerDeConfig.SCHEMA_REGISTRY_URL_CONFIG, envProps.getProperty("schema.registry.url"));
    serde.configure(config, false);
    return serde;
  }

  public Topology buildTopology(Properties envProps,
                                final SpecificAvroSerde<Click> clicksSerde) {
    final StreamsBuilder builder = new StreamsBuilder();

    final String inputTopic = envProps.getProperty("input.topic.name");
    final String outputTopic = envProps.getProperty("output.topic.name");

    // How long we "remember" an event.  During this time, any incoming duplicates of the event
    // will be, well, dropped, thereby de-duplicating the input data.
    //
    // The actual value depends on your use case.  To reduce memory and disk usage, you could
    // decrease the size to purge old windows more frequently at the cost of potentially missing out
    // on de-duplicating late-arriving records.
    final Duration windowSize = Duration.ofMinutes(2);

    // retention period must be at least window size -- for this use case, we don't need a longer retention period
    // and thus just use the window size as retention time
    final Duration retentionPeriod = windowSize;

    final StoreBuilder<WindowStore<String, Long>> dedupStoreBuilder = Stores.windowStoreBuilder(
            Stores.persistentWindowStore(storeName,
                    retentionPeriod,
                    windowSize,
                    false
            ),
            Serdes.String(),
            Serdes.Long());

    builder.addStateStore(dedupStoreBuilder);

    builder
      .stream(inputTopic, Consumed.with(Serdes.String(), clicksSerde))
      .transform( () -> new DeduplicationTransformer<>(windowSize.toMillis(), (key, value) -> value.getIp()), storeName)
      .to(outputTopic, Produced.with(Serdes.String(), clicksSerde));

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

  public static Properties buildStreamsProperties(Properties envProps) {
    Properties props = new Properties();

    props.put(StreamsConfig.APPLICATION_ID_CONFIG, envProps.getProperty("application.id"));
    props.put(StreamsConfig.BOOTSTRAP_SERVERS_CONFIG, envProps.getProperty("bootstrap.servers"));
    props.put(StreamsConfig.DEFAULT_KEY_SERDE_CLASS_CONFIG, Serdes.String().getClass());
    props.put(StreamsConfig.DEFAULT_VALUE_SERDE_CLASS_CONFIG, Serdes.String().getClass());
    props.put(AbstractKafkaAvroSerDeConfig.SCHEMA_REGISTRY_URL_CONFIG, envProps.getProperty("schema.registry.url"));
    props.put(StreamsConfig.CACHE_MAX_BYTES_BUFFERING_CONFIG, 0);

    return props;
  }
  public static Properties loadEnvProperties(String fileName) throws IOException {
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

    new FindDistinctEvents().runRecipe(args[0]);
  }

  private void runRecipe(final String configPath) throws IOException {
    Properties envProps = this.loadEnvProperties(configPath);
    Properties streamProps = this.buildStreamsProperties(envProps);

    Topology topology = this.buildTopology(envProps, this.buildClicksSerde(envProps));
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