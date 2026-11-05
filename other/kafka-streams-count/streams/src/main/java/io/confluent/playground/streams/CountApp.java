package io.confluent.playground.streams;

import java.io.InputStream;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.Collections;
import java.util.Properties;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ExecutionException;
import java.util.stream.Collectors;

import org.apache.kafka.clients.admin.Admin;
import org.apache.kafka.clients.admin.NewTopic;
import org.apache.kafka.common.TopicPartition;
import org.apache.kafka.common.errors.TopicExistsException;
import org.apache.kafka.common.serialization.Serdes;
import org.apache.kafka.common.utils.Bytes;
import org.apache.kafka.streams.KafkaStreams;
import org.apache.kafka.streams.StreamsBuilder;
import org.apache.kafka.streams.StreamsConfig;
import org.apache.kafka.streams.Topology;
import org.apache.kafka.streams.errors.StreamsUncaughtExceptionHandler;
import org.apache.kafka.streams.kstream.Consumed;
import org.apache.kafka.streams.kstream.Grouped;
import org.apache.kafka.streams.kstream.Materialized;
import org.apache.kafka.streams.kstream.Produced;
import org.apache.kafka.streams.processor.StateRestoreListener;
import org.apache.kafka.streams.state.KeyValueStore;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

/**
 * Stateful Kafka Streams application for support reproductions: counts the records of the input topic per bucket
 * (groupBy, so a repartition topic, then count, so a changelog topic) and writes the running counts to the output
 * topic.
 *
 * The StreamsConfig is read from a properties file (the customer's one can be dropped in), and the application logs
 * what matters in a support case: state transitions, task assignment per thread, and restoration of the state store.
 * It only uses APIs available since Kafka Streams 3.0.0 (metadataForLocalThreads), so that it compiles with the
 * customer's version.
 */
public class CountApp {

    private static final Logger log = LoggerFactory.getLogger(CountApp.class);

    public static void main(String[] args) throws Exception {
        Properties props = new Properties();
        loadProperties(props, env("STREAMS_CONFIG_FILE", "/etc/kafka-streams/streams.properties"), true);
        // optional: client security settings (sasl, ssl) kept apart from the customer's StreamsConfig
        loadProperties(props, env("STREAMS_EXTRA_CONFIG_FILE", "/etc/kafka-streams/extra.properties"), false);
        if (System.getenv("STREAMS_BOOTSTRAP_SERVERS") != null) {
            props.put(StreamsConfig.BOOTSTRAP_SERVERS_CONFIG, System.getenv("STREAMS_BOOTSTRAP_SERVERS"));
        }
        props.putIfAbsent(StreamsConfig.APPLICATION_ID_CONFIG, "streams-count");

        String inputTopic = env("INPUT_TOPIC", "streams-input");
        String outputTopic = env("OUTPUT_TOPIC", "streams-output");
        int partitions = Integer.parseInt(env("INPUT_PARTITIONS", "6"));
        int buckets = Integer.parseInt(env("BUCKETS", "10"));

        // a missing source topic stops the application: create it before starting
        createTopic(props, inputTopic, partitions);

        StreamsBuilder builder = new StreamsBuilder();
        builder.stream(inputTopic, Consumed.with(Serdes.String(), Serdes.String()))
                .groupBy((key, value) -> "bucket-" + Math.floorMod(value.hashCode(), buckets),
                        Grouped.with("by-bucket", Serdes.String(), Serdes.String()))
                .count(Materialized.<String, Long, KeyValueStore<Bytes, byte[]>>as("counts-store"))
                .toStream()
                .mapValues(count -> String.valueOf(count))
                .to(outputTopic, Produced.with(Serdes.String(), Serdes.String()));
        Topology topology = builder.build();
        log.info("🧩 Topology:\n{}", topology.describe());
        log.info("⚙️ StreamsConfig: {}", props.stringPropertyNames().stream().sorted()
                .filter(k -> !k.contains("password") && !k.contains("jaas"))
                .map(k -> k + "=" + props.getProperty(k)).collect(Collectors.joining(", ")));

        KafkaStreams streams = new KafkaStreams(topology, props);
        streams.setStateListener((newState, oldState) -> {
            log.info("🔀 Application state transition from {} to {}", oldState, newState);
            if (newState == KafkaStreams.State.RUNNING) {
                logAssignment(streams);
            }
        });
        streams.setGlobalStateRestoreListener(new StateRestoreListener() {
            @Override
            public void onRestoreStart(TopicPartition partition, String store, long startOffset, long endOffset) {
                log.info("♻️ Restore started for store {} from {}: offsets {} to {}", store, partition, startOffset, endOffset);
            }

            @Override
            public void onBatchRestored(TopicPartition partition, String store, long batchEndOffset, long numRestored) {
            }

            @Override
            public void onRestoreEnd(TopicPartition partition, String store, long totalRestored) {
                log.info("✅ Restore completed for store {} from {}: {} records restored", store, partition, totalRestored);
            }
        });
        streams.setUncaughtExceptionHandler(exception -> {
            log.error("💀 Uncaught exception in a stream thread, shutting down the client", exception);
            return StreamsUncaughtExceptionHandler.StreamThreadExceptionResponse.SHUTDOWN_CLIENT;
        });

        CountDownLatch latch = new CountDownLatch(1);
        Runtime.getRuntime().addShutdownHook(new Thread(() -> {
            log.info("🛑 Closing the application");
            streams.close();
            latch.countDown();
        }));
        streams.start();
        latch.await();
    }

    private static void logAssignment(KafkaStreams streams) {
        streams.metadataForLocalThreads().forEach(thread -> log.info("📋 Assignment of {}: active tasks [{}], standby tasks [{}]",
                thread.threadName(),
                thread.activeTasks().stream().map(t -> String.valueOf(t.taskId())).sorted().collect(Collectors.joining(", ")),
                thread.standbyTasks().stream().map(t -> String.valueOf(t.taskId())).sorted().collect(Collectors.joining(", "))));
    }

    private static void createTopic(Properties streamsProps, String topic, int partitions) throws InterruptedException {
        Properties adminProps = new Properties();
        for (String key : streamsProps.stringPropertyNames()) {
            if (key.equals(StreamsConfig.BOOTSTRAP_SERVERS_CONFIG) || key.startsWith("security.")
                    || key.startsWith("sasl.") || key.startsWith("ssl.")) {
                adminProps.put(key, streamsProps.getProperty(key));
            }
        }
        for (int attempt = 1; attempt <= 60; attempt++) {
            try (Admin admin = Admin.create(adminProps)) {
                admin.createTopics(Collections.singletonList(new NewTopic(topic, partitions, (short) -1))).all().get();
                log.info("📝 Topic {} created with {} partitions", topic, partitions);
                return;
            } catch (ExecutionException e) {
                if (e.getCause() instanceof TopicExistsException) {
                    log.info("📝 Topic {} already exists", topic);
                    return;
                }
                log.warn("⏳ Cannot create topic {} yet (attempt {}/60): {}", topic, attempt, e.getCause().toString());
            }
            Thread.sleep(2000);
        }
        throw new IllegalStateException("Cannot create topic " + topic);
    }

    private static void loadProperties(Properties props, String file, boolean required) throws Exception {
        Path path = Paths.get(file);
        if (!Files.exists(path)) {
            if (required) {
                throw new IllegalArgumentException("StreamsConfig file " + file + " not found");
            }
            return;
        }
        try (InputStream in = Files.newInputStream(path)) {
            props.load(in);
        }
    }

    private static String env(String name, String defaultValue) {
        String value = System.getenv(name);
        return value == null || value.isEmpty() ? defaultValue : value;
    }
}
