package io.confluent.developer;

import io.confluent.developer.avro.ActingEvent;
import io.confluent.kafka.serializers.AbstractKafkaAvroSerDeConfig;
import io.confluent.kafka.streams.serdes.avro.SpecificAvroSerde;
import org.apache.kafka.clients.admin.AdminClient;
import org.apache.kafka.clients.admin.NewTopic;
import org.apache.kafka.common.serialization.Serdes;
import org.apache.kafka.streams.KafkaStreams;
import org.apache.kafka.streams.StreamsBuilder;
import org.apache.kafka.streams.StreamsConfig;
import org.apache.kafka.streams.Topology;
import org.apache.kafka.streams.kstream.KStream;

import java.io.FileInputStream;
import java.io.IOException;
import java.util.*;
import java.util.concurrent.CountDownLatch;

public class SplitStream {

    public Properties buildStreamsProperties(Properties envProps) {
        Properties props = new Properties();

        props.put(StreamsConfig.APPLICATION_ID_CONFIG, envProps.getProperty("application.id"));
        props.put(StreamsConfig.BOOTSTRAP_SERVERS_CONFIG, envProps.getProperty("bootstrap.servers"));
        props.put(StreamsConfig.DEFAULT_KEY_SERDE_CLASS_CONFIG, Serdes.String().getClass());
        props.put(StreamsConfig.DEFAULT_VALUE_SERDE_CLASS_CONFIG, SpecificAvroSerde.class);
        props.put(AbstractKafkaAvroSerDeConfig.SCHEMA_REGISTRY_URL_CONFIG, envProps.getProperty("schema.registry.url"));

        return props;
    }

    public Topology buildTopology(Properties envProps) {
        final StreamsBuilder builder = new StreamsBuilder();
        final String inputTopic = envProps.getProperty("input.topic.name");

        KStream<String, ActingEvent>[] branches = builder.<String, ActingEvent>stream(inputTopic)
                .branch((key, appearance) -> "drama".equals(appearance.getGenre()),
                        (key, appearance) -> "fantasy".equals(appearance.getGenre()),
                        (key, appearance) -> true);

        branches[0].to(envProps.getProperty("output.drama.topic.name"));
        branches[1].to(envProps.getProperty("output.fantasy.topic.name"));
        branches[2].to(envProps.getProperty("output.other.topic.name"));

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
                envProps.getProperty("output.drama.topic.name"),
                Integer.parseInt(envProps.getProperty("output.drama.topic.partitions")),
                Short.parseShort(envProps.getProperty("output.drama.topic.replication.factor"))));

        topics.add(new NewTopic(
                envProps.getProperty("output.fantasy.topic.name"),
                Integer.parseInt(envProps.getProperty("output.fantasy.topic.partitions")),
                Short.parseShort(envProps.getProperty("output.fantasy.topic.replication.factor"))));

        topics.add(new NewTopic(
                envProps.getProperty("output.other.topic.name"),
                Integer.parseInt(envProps.getProperty("output.other.topic.partitions")),
                Short.parseShort(envProps.getProperty("output.other.topic.replication.factor"))));

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

    public static void main(String[] args) throws Exception {
        if (args.length < 1) {
            throw new IllegalArgumentException("This program takes one argument: the path to an environment configuration file.");
        }

        SplitStream ss = new SplitStream();
        Properties envProps = ss.loadEnvProperties(args[0]);
        Properties streamProps = ss.buildStreamsProperties(envProps);
        Topology topology = ss.buildTopology(envProps);

        ss.createTopics(envProps);

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