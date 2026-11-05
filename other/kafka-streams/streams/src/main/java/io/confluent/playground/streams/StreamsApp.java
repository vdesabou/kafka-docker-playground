package io.confluent.playground.streams;

import java.io.InputStream;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.Properties;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ExecutionException;
import java.util.stream.Collectors;

import org.apache.kafka.clients.admin.Admin;
import org.apache.kafka.clients.admin.NewTopic;
import org.apache.kafka.common.Metric;
import org.apache.kafka.common.TopicPartition;
import org.apache.kafka.common.errors.TopicExistsException;
import org.apache.kafka.streams.KafkaStreams;
import org.apache.kafka.streams.StreamsConfig;
import org.apache.kafka.streams.Topology;
import org.apache.kafka.streams.errors.StreamsUncaughtExceptionHandler;
import org.apache.kafka.streams.processor.StateRestoreListener;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

/**
 * Kafka Streams application for support reproductions. TOPOLOGY selects the scenario (count, windowed, join, eos,
 * serde-errors), the StreamsConfig is read from a properties file (drop the customer's one in): the keys starting with
 * "app." configure the scenario itself and are not passed to Kafka Streams.
 *
 * The application logs what matters in a support case: state transitions, task assignment per thread, restoration of
 * the state stores, uncaught exceptions with their causes, and the dropped-records-total metric when it changes. Some
 * scenarios also start a "demo" application in the same JVM (its own application.id) that is expected to fail, to show
 * an error without stopping the main application.
 *
 * It only uses APIs available since Kafka Streams 3.0.0 and not removed in 4.x, so that it compiles with the
 * customer's version.
 */
public class StreamsApp {

    private static final Logger log = LoggerFactory.getLogger(StreamsApp.class);

    public static void main(String[] args) throws Exception {
        Properties props = new Properties();
        loadProperties(props, env("STREAMS_CONFIG_FILE", "/etc/kafka-streams/streams.properties"), true);
        // optional: client security settings (sasl, ssl) kept apart from the customer's StreamsConfig
        loadProperties(props, env("STREAMS_EXTRA_CONFIG_FILE", "/etc/kafka-streams/extra.properties"), false);
        if (System.getenv("STREAMS_BOOTSTRAP_SERVERS") != null) {
            props.put(StreamsConfig.BOOTSTRAP_SERVERS_CONFIG, System.getenv("STREAMS_BOOTSTRAP_SERVERS"));
        }
        // "app." keys configure the scenario, not Kafka Streams
        Properties appProps = new Properties();
        for (String key : new ArrayList<>(props.stringPropertyNames())) {
            if (key.startsWith("app.")) {
                appProps.put(key.substring("app.".length()), props.getProperty(key));
                props.remove(key);
            }
        }
        String topologyName = env("TOPOLOGY", "count");
        props.putIfAbsent(StreamsConfig.APPLICATION_ID_CONFIG, "streams-" + topologyName);

        Scenario scenario = Scenario.of(topologyName, appProps);
        // a missing source topic stops the application: create them before starting
        createTopics(props, scenario.topics());

        log.info("⚙️ StreamsConfig: {}", props.stringPropertyNames().stream().sorted()
                .filter(k -> !k.contains("password") && !k.contains("jaas"))
                .map(k -> k + "=" + props.getProperty(k)).collect(Collectors.joining(", ")));
        log.info("🎛️ Scenario {} settings (app.*): {}", topologyName, appProps);

        List<KafkaStreams> all = new ArrayList<>();
        all.add(start(scenario.topology(props), props, false));
        for (Map.Entry<String, Scenario.Demo> demo : scenario.demos().entrySet()) {
            Properties demoProps = new Properties();
            demoProps.putAll(props);
            demoProps.putAll(demo.getValue().overrides);
            demoProps.put(StreamsConfig.APPLICATION_ID_CONFIG, props.getProperty(StreamsConfig.APPLICATION_ID_CONFIG) + "-" + demo.getKey());
            all.add(start(demo.getValue().topology, demoProps, true));
        }
        startDroppedRecordsLogger(all);

        CountDownLatch latch = new CountDownLatch(1);
        Runtime.getRuntime().addShutdownHook(new Thread(() -> {
            log.info("🛑 Closing the application");
            all.forEach(KafkaStreams::close);
            latch.countDown();
        }));
        latch.await();
    }

    private static KafkaStreams start(Topology topology, Properties props, boolean demo) {
        String appId = props.getProperty(StreamsConfig.APPLICATION_ID_CONFIG);
        // the main application keeps the messages the example scripts wait for
        String who = demo ? "Demo application " + appId : "Application";
        log.info("🧩 Topology of {}:\n{}", appId, topology.describe());
        KafkaStreams streams = new KafkaStreams(topology, props);
        streams.setStateListener((newState, oldState) -> {
            log.info("🔀 {} state transition from {} to {}", who, oldState, newState);
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
            log.error("💀 Uncaught exception in a stream thread of {}, shutting down the client: {}", appId, causes(exception), exception);
            return StreamsUncaughtExceptionHandler.StreamThreadExceptionResponse.SHUTDOWN_CLIENT;
        });
        streams.start();
        return streams;
    }

    /** The exception and its causes on one line, to grep the logs. */
    static String causes(Throwable exception) {
        List<String> parts = new ArrayList<>();
        for (Throwable t = exception; t != null && parts.size() < 10; t = t.getCause()) {
            parts.add(t.getClass().getName() + ": " + t.getMessage());
            if (t.getCause() == t) {
                break;
            }
        }
        return String.join(" <- caused by ", parts);
    }

    private static void logAssignment(KafkaStreams streams) {
        streams.metadataForLocalThreads().forEach(thread -> log.info("📋 Assignment of {}: active tasks [{}], standby tasks [{}]",
                thread.threadName(),
                thread.activeTasks().stream().map(t -> String.valueOf(t.taskId())).sorted().collect(Collectors.joining(", ")),
                thread.standbyTasks().stream().map(t -> String.valueOf(t.taskId())).sorted().collect(Collectors.joining(", "))));
    }

    /** Logs the dropped-records-total metric (late records, deserialization errors skipped…) of each application when it changes. */
    private static void startDroppedRecordsLogger(List<KafkaStreams> all) {
        Thread thread = new Thread(() -> {
            double[] last = new double[all.size()];
            while (true) {
                try {
                    Thread.sleep(5000);
                } catch (InterruptedException e) {
                    return;
                }
                for (int i = 0; i < all.size(); i++) {
                    double total = 0;
                    for (Metric metric : all.get(i).metrics().values()) {
                        if (metric.metricName().name().equals("dropped-records-total") && metric.metricValue() instanceof Number) {
                            total += ((Number) metric.metricValue()).doubleValue();
                        }
                    }
                    if (total != last[i]) {
                        log.info("🗑️ dropped-records-total of application #{}: {}", i, (long) total);
                        last[i] = total;
                    }
                }
            }
        }, "dropped-records-logger");
        thread.setDaemon(true);
        thread.start();
    }

    private static void createTopics(Properties streamsProps, Map<String, Integer> topics) throws InterruptedException {
        Properties adminProps = new Properties();
        for (String key : streamsProps.stringPropertyNames()) {
            if (key.equals(StreamsConfig.BOOTSTRAP_SERVERS_CONFIG) || key.startsWith("security.")
                    || key.startsWith("sasl.") || key.startsWith("ssl.")) {
                adminProps.put(key, streamsProps.getProperty(key));
            }
        }
        for (Map.Entry<String, Integer> topic : topics.entrySet()) {
            createTopic(adminProps, topic.getKey(), topic.getValue());
        }
    }

    private static void createTopic(Properties adminProps, String topic, int partitions) throws InterruptedException {
        for (int attempt = 1; attempt <= 60; attempt++) {
            try (Admin admin = Admin.create(adminProps)) {
                admin.createTopics(List.of(new NewTopic(topic, partitions, (short) -1))).all().get();
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

    static String env(String name, String defaultValue) {
        String value = System.getenv(name);
        return value == null || value.isEmpty() ? defaultValue : value;
    }
}
