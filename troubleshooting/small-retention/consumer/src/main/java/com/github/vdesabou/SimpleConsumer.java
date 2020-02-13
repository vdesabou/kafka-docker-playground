package com.github.vdesabou;

import org.apache.kafka.clients.CommonClientConfigs;
import org.apache.kafka.clients.consumer.ConsumerConfig;
import org.apache.kafka.clients.consumer.ConsumerRecord;
import org.apache.kafka.clients.consumer.ConsumerRecords;
import org.apache.kafka.clients.consumer.KafkaConsumer;
import java.time.Duration;
import java.util.Arrays;
import org.apache.kafka.clients.producer.Producer;
import org.apache.kafka.clients.producer.Callback;
import org.apache.kafka.clients.producer.KafkaProducer;
import org.apache.kafka.clients.producer.Producer;
import org.apache.kafka.clients.producer.ProducerConfig;
import org.apache.kafka.clients.producer.ProducerRecord;
import org.apache.kafka.clients.producer.RecordMetadata;
import java.util.Properties;
import java.util.concurrent.TimeUnit;

public class SimpleConsumer {

    private static final String TOPIC = "testtopic";
    private static final String OUTPUTTOPIC = "outputtesttopic";

    public static void main(String[] args) throws InterruptedException {
        final Properties consumerProps = new Properties();
        consumerProps.put(ConsumerConfig.BOOTSTRAP_SERVERS_CONFIG, "broker:9092");
        consumerProps.put(ConsumerConfig.GROUP_ID_CONFIG, "testtopic-app");
        consumerProps.put(ConsumerConfig.ENABLE_AUTO_COMMIT_CONFIG, "true");
        consumerProps.put(ConsumerConfig.AUTO_COMMIT_INTERVAL_MS_CONFIG, "5000");
        consumerProps.put(ConsumerConfig.AUTO_OFFSET_RESET_CONFIG, "earliest");
        consumerProps.put(ConsumerConfig.KEY_DESERIALIZER_CLASS_CONFIG, "org.apache.kafka.common.serialization.StringDeserializer");
        consumerProps.put(ConsumerConfig.VALUE_DESERIALIZER_CLASS_CONFIG, "org.apache.kafka.common.serialization.StringDeserializer");

        Properties producerProps = new Properties();
        producerProps.put(ProducerConfig.BOOTSTRAP_SERVERS_CONFIG, "broker:9092");
        producerProps.put(ProducerConfig.ACKS_CONFIG, "all");
        producerProps.put(ProducerConfig.ENABLE_IDEMPOTENCE_CONFIG, "true");
        producerProps.put(ProducerConfig.KEY_SERIALIZER_CLASS_CONFIG, "org.apache.kafka.common.serialization.StringSerializer");
        producerProps.put(ProducerConfig.VALUE_SERIALIZER_CLASS_CONFIG, "org.apache.kafka.common.serialization.StringSerializer");

        final Producer<String, String> producer = new KafkaProducer<>(producerProps);
        final KafkaConsumer<String, String> consumer = new KafkaConsumer<>(consumerProps);

        consumer.subscribe(Arrays.asList(TOPIC));

        while (true) {
            final ConsumerRecords<String, String> records = consumer.poll(Duration.ofMillis(100));
            for (final ConsumerRecord<String, String> record : records) {

                final String key = record.key();
                final String value = record.value();

                ProducerRecord<String, String> prodrecord = new ProducerRecord<>(OUTPUTTOPIC, 0, 1581583089003L, record.key(), record.value());

                System.out.printf("Processing key %s value %s\n", prodrecord.key(), prodrecord.value());


                producer.send(prodrecord, new Callback() {
                    @Override
                    public void onCompletion(RecordMetadata metadata, Exception exception) {
                        if (exception == null) {
                            System.out.printf("Produced record to topic %s partition [%d] @ offset %d%n and timestamp %d\n", metadata.topic(), metadata.partition(), metadata.offset(), metadata.timestamp());
                        } else {
                            exception.printStackTrace();
                        }
                    }
                });
                producer.flush();
            }
        }
    }
}
