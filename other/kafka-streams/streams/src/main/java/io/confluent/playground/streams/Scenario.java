package io.confluent.playground.streams;

import java.util.Collections;
import java.util.Map;
import java.util.Properties;

import org.apache.kafka.streams.Topology;

/** A topology and the topics it reads, selected with TOPOLOGY. */
public interface Scenario {

    /** Source topics to create before starting, with their number of partitions. */
    Map<String, Integer> topics();

    Topology topology(Properties streamsProps);

    /** Applications started next to the main one, by application id suffix, expected to fail to show an error. */
    default Map<String, Demo> demos() {
        return Collections.emptyMap();
    }

    final class Demo {
        final Topology topology;
        final Properties overrides;

        Demo(Topology topology, Properties overrides) {
            this.topology = topology;
            this.overrides = overrides;
        }
    }

    static Scenario of(String name, Properties appProps) {
        switch (name) {
            case "count":
                return new CountScenario("streams-input", "streams-output", appProps);
            case "eos":
                // same topology, processing.guarantee=exactly_once_v2 in config/eos.properties
                return new CountScenario("eos-input", "eos-output", appProps);
            case "windowed":
                return new WindowedScenario(appProps);
            case "join":
                return new JoinScenario(appProps);
            case "serde-errors":
                return new SerdeErrorsScenario(appProps);
            default:
                throw new IllegalArgumentException("Unknown TOPOLOGY " + name + ": count, windowed, join, eos or serde-errors");
        }
    }

    static long longProp(Properties appProps, String name, long defaultValue) {
        String value = appProps.getProperty(name);
        return value == null || value.isEmpty() ? defaultValue : Long.parseLong(value.trim());
    }
}
