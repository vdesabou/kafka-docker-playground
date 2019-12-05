package io.confluent.developer;

import io.confluent.developer.avro.Rating;
import org.apache.kafka.clients.consumer.ConsumerRecord;
import org.apache.kafka.streams.processor.TimestampExtractor;

import java.text.ParseException;
import java.text.SimpleDateFormat;

public class RatingTimestampExtractor implements TimestampExtractor {
    @Override
    public long extract(ConsumerRecord<Object, Object> record, long previousTimestamp) {
        final SimpleDateFormat sdf = new SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ssZ");

        String eventTime = ((Rating)record.value()).getTimestamp();

        try {
            return sdf.parse(eventTime).getTime();
        } catch(ParseException e) {
            return 0;
        }
    }
}