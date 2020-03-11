package io.confluent.developer;


import com.typesafe.config.Config;
import com.typesafe.config.ConfigFactory;
import io.confluent.developer.avro.PressureAlert;
import io.confluent.kafka.streams.serdes.avro.SpecificAvroSerde;
import org.apache.kafka.clients.consumer.ConsumerConfig;
import org.apache.kafka.common.serialization.Serdes;
import org.apache.kafka.common.serialization.Serdes.StringSerde;
import org.apache.kafka.streams.KafkaStreams;
import org.apache.kafka.streams.StreamsBuilder;
import org.apache.kafka.streams.StreamsConfig;
import org.apache.kafka.streams.Topology;
import org.apache.kafka.streams.kstream.*;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.util.Map;
import java.util.Properties;

import static io.confluent.kafka.serializers.AbstractKafkaAvroSerDeConfig.SCHEMA_REGISTRY_URL_CONFIG;
import static java.util.Collections.singletonMap;
import static org.apache.kafka.streams.kstream.Suppressed.BufferConfig.unbounded;
import static org.apache.kafka.streams.kstream.WindowedSerdes.timeWindowedSerdeFrom;

public class WindowFinalResult {

    private static Logger logger = LoggerFactory.getLogger(WindowFinalResult.class);

    public static Properties buildProperties(Config config) {
        Properties properties = new Properties();

        properties.put(StreamsConfig.BOOTSTRAP_SERVERS_CONFIG, config.getString("bootstrap.servers"));
        properties.put(StreamsConfig.APPLICATION_ID_CONFIG, config.getString("application.id"));
        properties.put(StreamsConfig.DEFAULT_VALUE_SERDE_CLASS_CONFIG, StringSerde.class);
        properties.put(StreamsConfig.DEFAULT_KEY_SERDE_CLASS_CONFIG, StringSerde.class);
        properties.put(ConsumerConfig.AUTO_OFFSET_RESET_CONFIG, "latest");
        properties.put(StreamsConfig.CACHE_MAX_BYTES_BUFFERING_CONFIG, 0);

        return properties;
    }

    public static Topology buildTopology(Config config,
                                         TimeWindows windows,
                                         SpecificAvroSerde<PressureAlert> pressureSerde) {

        StreamsBuilder builder = new StreamsBuilder();

        String inputTopic = config.getString("input.topic.name");
        String outputTopic = config.getString("output.topic.name");

        Produced<Windowed<String>, Long> producedCount = Produced
                .with(timeWindowedSerdeFrom(String.class), Serdes.Long());

        Consumed<String, PressureAlert> consumedPressure = Consumed
                .with(Serdes.String(), pressureSerde)
                .withTimestampExtractor(new PressureDatetimeExtractor(config));

        Grouped<String, PressureAlert> groupedPressure = Grouped.with(Serdes.String(), pressureSerde);

        builder

                .stream(inputTopic, consumedPressure)

                .selectKey((key, value) -> value.getId())

                .groupByKey(groupedPressure)

                .windowedBy(windows)

                .count()

                .suppress(Suppressed.untilWindowCloses(unbounded()))

                .toStream()

                .to(outputTopic, producedCount);

        return builder.build();
    }

    public static void main(String[] args) {

        final Config config = ConfigFactory.load();

        final Properties properties = buildProperties(config);

        Map<String, Object> serdeConfig =
                singletonMap(SCHEMA_REGISTRY_URL_CONFIG, config.getString("schema.registry.url"));

        SpecificAvroSerde<PressureAlert> pressureSerde = new SpecificAvroSerde<>();

        pressureSerde.configure(serdeConfig, false);

        TimeWindows windows = TimeWindows

                .of(config.getDuration("window.size"))

                .advanceBy(config.getDuration("window.size"))

                .grace(config.getDuration("window.grace.period"));

        Topology topology = buildTopology(config, windows, pressureSerde);

        logger.debug(topology.describe().toString());

        final KafkaStreams streams = new KafkaStreams(topology, properties);

        Runtime.getRuntime().addShutdownHook(new Thread(streams::close));

        streams.cleanUp();
        streams.start();
    }
}