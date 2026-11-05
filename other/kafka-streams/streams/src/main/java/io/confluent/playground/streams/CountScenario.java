package io.confluent.playground.streams;

import java.util.Map;
import java.util.Properties;

import org.apache.kafka.common.serialization.Serdes;
import org.apache.kafka.common.utils.Bytes;
import org.apache.kafka.streams.StreamsBuilder;
import org.apache.kafka.streams.Topology;
import org.apache.kafka.streams.kstream.Consumed;
import org.apache.kafka.streams.kstream.Grouped;
import org.apache.kafka.streams.kstream.Materialized;
import org.apache.kafka.streams.kstream.Produced;
import org.apache.kafka.streams.state.KeyValueStore;

/**
 * count and eos: counts the records per bucket (groupBy, so a repartition topic, then count, so a state store and its
 * changelog topic) and writes the running counts to the output topic.
 */
class CountScenario implements Scenario {

    private final String input;
    private final String output;
    private final int partitions;
    private final int buckets;

    CountScenario(String input, String output, Properties appProps) {
        this.input = input;
        this.output = output;
        this.partitions = (int) Scenario.longProp(appProps, "input.partitions", 6);
        this.buckets = (int) Scenario.longProp(appProps, "buckets", 10);
    }

    @Override
    public Map<String, Integer> topics() {
        return Map.of(input, partitions);
    }

    @Override
    public Topology topology(Properties streamsProps) {
        StreamsBuilder builder = new StreamsBuilder();
        builder.stream(input, Consumed.with(Serdes.String(), Serdes.String()))
                .groupBy((key, value) -> "bucket-" + Math.floorMod(value.hashCode(), buckets),
                        Grouped.with("by-bucket", Serdes.String(), Serdes.String()))
                .count(Materialized.<String, Long, KeyValueStore<Bytes, byte[]>>as("counts-store"))
                .toStream()
                .mapValues(count -> String.valueOf(count))
                .to(output, Produced.with(Serdes.String(), Serdes.String()));
        return builder.build();
    }
}
