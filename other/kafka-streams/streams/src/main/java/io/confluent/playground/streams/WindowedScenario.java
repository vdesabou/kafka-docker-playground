package io.confluent.playground.streams;

import java.time.Duration;
import java.time.Instant;
import java.util.Map;
import java.util.Properties;

import org.apache.kafka.clients.consumer.ConsumerRecord;
import org.apache.kafka.common.serialization.Serdes;
import org.apache.kafka.common.utils.Bytes;
import org.apache.kafka.streams.KeyValue;
import org.apache.kafka.streams.StreamsBuilder;
import org.apache.kafka.streams.Topology;
import org.apache.kafka.streams.kstream.Consumed;
import org.apache.kafka.streams.kstream.Grouped;
import org.apache.kafka.streams.kstream.Materialized;
import org.apache.kafka.streams.kstream.Produced;
import org.apache.kafka.streams.kstream.Suppressed;
import org.apache.kafka.streams.kstream.TimeWindows;
import org.apache.kafka.streams.processor.TimestampExtractor;
import org.apache.kafka.streams.state.WindowStore;

/**
 * windowed: counts the records per key in tumbling windows (app.window.size.ms, 1 minute) with a grace period
 * (app.window.grace.ms, 30 seconds), and only emits the final count of each window once it closes (suppress).
 *
 * The event time is the "ts" field of the JSON value (epoch milliseconds), so that out-of-order and late records can be
 * produced on purpose. A record later than the grace period is dropped (dropped-records-total). app.suppress.max.records
 * bounds the suppression buffer: the application shuts down when it is full (shutDownWhenFull), instead of an unbounded
 * buffer in memory.
 */
class WindowedScenario implements Scenario {

    private final long sizeMs;
    private final long graceMs;
    private final long retentionMs;
    private final long suppressMaxRecords;

    WindowedScenario(Properties appProps) {
        this.sizeMs = Scenario.longProp(appProps, "window.size.ms", 60_000);
        this.graceMs = Scenario.longProp(appProps, "window.grace.ms", 30_000);
        this.retentionMs = Scenario.longProp(appProps, "window.retention.ms", 0);
        this.suppressMaxRecords = Scenario.longProp(appProps, "suppress.max.records", 0);
    }

    @Override
    public Map<String, Integer> topics() {
        return Map.of("windowed-input", 3);
    }

    @Override
    public Topology topology(Properties streamsProps) {
        Materialized<String, Long, WindowStore<Bytes, byte[]>> store = Materialized.as("windowed-counts-store");
        if (retentionMs > 0) {
            // must be at least window size + grace period
            store = store.withRetention(Duration.ofMillis(retentionMs));
        }
        Suppressed.StrictBufferConfig buffer = suppressMaxRecords > 0
                ? Suppressed.BufferConfig.maxRecords(suppressMaxRecords).shutDownWhenFull()
                : Suppressed.BufferConfig.unbounded();

        StreamsBuilder builder = new StreamsBuilder();
        builder.stream("windowed-input", Consumed.with(Serdes.String(), Serdes.String()).withTimestampExtractor(new JsonTimestampExtractor()))
                .groupByKey(Grouped.with(Serdes.String(), Serdes.String()))
                .windowedBy(TimeWindows.ofSizeAndGrace(Duration.ofMillis(sizeMs), Duration.ofMillis(graceMs)))
                .count(store)
                .suppress(Suppressed.untilWindowCloses(buffer))
                .toStream()
                .map((windowedKey, count) -> KeyValue.pair(windowedKey.key() + "@" + Instant.ofEpochMilli(windowedKey.window().start()), String.valueOf(count)))
                .to("windowed-output", Produced.with(Serdes.String(), Serdes.String()));
        return builder.build();
    }

    /** The "ts" field of the JSON value, the record timestamp otherwise. */
    static class JsonTimestampExtractor implements TimestampExtractor {
        @Override
        public long extract(ConsumerRecord<Object, Object> record, long partitionTime) {
            String ts = record.value() == null ? null : Json.field(record.value().toString(), "ts");
            return ts == null ? record.timestamp() : Long.parseLong(ts);
        }
    }
}
