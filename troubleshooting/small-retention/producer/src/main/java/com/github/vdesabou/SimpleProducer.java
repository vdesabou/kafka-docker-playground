package com.github.vdesabou;

import org.apache.kafka.clients.producer.Callback;
import org.apache.kafka.clients.producer.KafkaProducer;
import org.apache.kafka.clients.producer.Producer;
import org.apache.kafka.clients.producer.ProducerConfig;
import org.apache.kafka.clients.producer.ProducerRecord;
import org.apache.kafka.clients.producer.RecordMetadata;
import java.util.Properties;
import java.util.concurrent.TimeUnit;

public class SimpleProducer {

    private static final String TOPIC = "testtopic";

    public static void main(String[] args) throws InterruptedException {

        Properties props = new Properties();
        props.put(ProducerConfig.BOOTSTRAP_SERVERS_CONFIG, "broker:9092");
        props.put(ProducerConfig.ACKS_CONFIG, "all");
        props.put(ProducerConfig.KEY_SERIALIZER_CLASS_CONFIG, "org.apache.kafka.common.serialization.StringSerializer");
        props.put(ProducerConfig.VALUE_SERIALIZER_CLASS_CONFIG, "org.apache.kafka.common.serialization.StringSerializer");

        System.out.println("Sending data to `testtopic` topic. Properties: " + props.toString());

        try (Producer<String, String> producer = new KafkaProducer<>(props)) {
            long i = 0;
            while (true) {

                ProducerRecord<String, String> record = new ProducerRecord<>(TOPIC, 0, 1581583089003L, null, "message " + i);

                System.out.println("Sending key="+ record.key() + " value=" + record.value());
                producer.send(record, new Callback() {
                    @Override
                    public void onCompletion(RecordMetadata metadata, Exception exception) {
                        if (exception == null) {
                            System.out.printf("Produced record to topic %s partition [%d] @ offset %d%n and timestamp %d", metadata.topic(), metadata.partition(), metadata.offset(), metadata.timestamp());
                        } else {
                            exception.printStackTrace();
                        }
                    }
                });
                producer.flush();
                i++;
                TimeUnit.MILLISECONDS.sleep(1000);
            }
        }
    }
}
