package io.confluent.playground.streams;

import java.util.Map;

import org.apache.kafka.clients.producer.ProducerRecord;
import org.apache.kafka.common.errors.RecordTooLargeException;
import org.apache.kafka.streams.errors.ProductionExceptionHandler;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

/**
 * default.production.exception.handler of the serde-errors scenario: skips a record the producer refuses because it is
 * too large (RecordTooLargeException), fails on anything else. The classic example of the Kafka Streams docs.
 *
 * Implements the handle(ProducerRecord, Exception) method, deprecated in 3.9 but still called by the default methods of
 * 4.x, so that it compiles with every Kafka Streams version since 3.0.
 */
public class ContinueOnRecordTooLargeHandler implements ProductionExceptionHandler {

    private static final Logger log = LoggerFactory.getLogger(ContinueOnRecordTooLargeHandler.class);

    @Override
    @SuppressWarnings("deprecation")
    public ProductionExceptionHandlerResponse handle(ProducerRecord<byte[], byte[]> record, Exception exception) {
        if (exception instanceof RecordTooLargeException) {
            log.warn("📦 Production exception handler: skipping a record of {} bytes for topic {}: {}",
                    record.value() == null ? 0 : record.value().length, record.topic(), exception.toString());
            return ProductionExceptionHandlerResponse.CONTINUE;
        }
        log.error("📦 Production exception handler: failing on {}", exception.toString());
        return ProductionExceptionHandlerResponse.FAIL;
    }

    @Override
    public void configure(Map<String, ?> configs) {
    }
}
