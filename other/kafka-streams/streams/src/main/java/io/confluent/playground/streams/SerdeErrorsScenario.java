package io.confluent.playground.streams;

import java.util.Map;
import java.util.Properties;

import org.apache.avro.generic.GenericRecord;
import org.apache.kafka.common.serialization.Serdes;
import org.apache.kafka.streams.StreamsBuilder;
import org.apache.kafka.streams.Topology;
import org.apache.kafka.streams.kstream.Consumed;
import org.apache.kafka.streams.kstream.Produced;

import io.confluent.kafka.streams.serdes.avro.GenericAvroSerde;

/**
 * serde-errors: reads Avro payments (Schema Registry, app.schema.registry.url) and writes them as JSON to
 * payments-processed.
 *
 * - a record that is not Avro (a poison pill) fails deserialization: default.deserialization.exception.handler decides
 *   (LogAndContinueExceptionHandler in config/serde-errors.properties: logged, skipped, dropped-records-total)
 * - a payment with id "inflate" is turned into a value larger than producer.max.request.size: the producer fails with
 *   RecordTooLargeException and default.production.exception.handler decides (ContinueOnRecordTooLargeHandler: logged,
 *   skipped)
 * - schema evolution: the records of a newer compatible schema are read with their own (writer) schema
 *
 * Demo "fail-on-poison-pill": the same topology with LogAndFailExceptionHandler, the default, which stops the
 * application on the poison pill.
 */
class SerdeErrorsScenario implements Scenario {

    private final String schemaRegistryUrl;

    SerdeErrorsScenario(Properties appProps) {
        this.schemaRegistryUrl = appProps.getProperty("schema.registry.url", "http://schema-registry:8081");
    }

    @Override
    public Map<String, Integer> topics() {
        return Map.of("payments", 3);
    }

    @Override
    public Topology topology(Properties streamsProps) {
        return build("payments-processed");
    }

    private Topology build(String output) {
        GenericAvroSerde valueSerde = new GenericAvroSerde();
        valueSerde.configure(Map.of("schema.registry.url", schemaRegistryUrl), false);
        StreamsBuilder builder = new StreamsBuilder();
        builder.stream("payments", Consumed.with(Serdes.String(), valueSerde))
                .mapValues(SerdeErrorsScenario::render)
                .to(output, Produced.with(Serdes.String(), Serdes.String()));
        return builder.build();
    }

    private static String render(GenericRecord payment) {
        if ("inflate".equals(String.valueOf(payment.get("id")))) {
            return payment + " " + "x".repeat(10_000);
        }
        return payment.toString();
    }

    @Override
    public Map<String, Demo> demos() {
        Properties overrides = new Properties();
        overrides.put("default.deserialization.exception.handler", "org.apache.kafka.streams.errors.LogAndFailExceptionHandler");
        return Map.of("fail-on-poison-pill", new Demo(build("payments-processed-fail-demo"), overrides));
    }
}
