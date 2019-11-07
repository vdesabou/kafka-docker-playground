package com.github.vdesabou;

import org.apache.kafka.clients.CommonClientConfigs;
import org.apache.kafka.clients.consumer.ConsumerConfig;
import org.apache.kafka.clients.consumer.ConsumerRecord;
import org.apache.kafka.clients.consumer.ConsumerRecords;
import org.apache.kafka.clients.consumer.KafkaConsumer;
import io.confluent.kafka.serializers.KafkaAvroDeserializer;
import io.confluent.kafka.serializers.KafkaAvroDeserializerConfig;

import org.apache.kafka.common.config.SaslConfigs;
import java.time.Duration;
import java.util.Arrays;
import java.util.Properties;
import com.github.vdesabou.Customer;

public class SimpleConsumer {

    private static final String TOPIC = "customer-avro";

    public static void main(String[] args) {
        final Properties props = new Properties();
        props.put(ConsumerConfig.BOOTSTRAP_SERVERS_CONFIG, System.getenv("BOOTSTRAP_SERVERS"));
        props.put(ConsumerConfig.GROUP_ID_CONFIG, "customer-avro-app");
        props.put(ConsumerConfig.ENABLE_AUTO_COMMIT_CONFIG, "true");
        props.put(ConsumerConfig.AUTO_COMMIT_INTERVAL_MS_CONFIG, "1000");
        props.put(ConsumerConfig.AUTO_OFFSET_RESET_CONFIG, "earliest");

        props.put("ssl.endpoint.identification.algorithm", "https");
        props.put(SaslConfigs.SASL_MECHANISM, "PLAIN");
        props.put(SaslConfigs.SASL_JAAS_CONFIG, "org.apache.kafka.common.security.plain.PlainLoginModule required username=\"" + System.getenv("CLOUD_KEY") + "\" password=\"" + System.getenv("CLOUD_SECRET") + "\";");
        props.put(CommonClientConfigs.SECURITY_PROTOCOL_CONFIG, "SASL_SSL");
        
        props.put(ConsumerConfig.KEY_DESERIALIZER_CLASS_CONFIG, "org.apache.kafka.common.serialization.StringDeserializer");
        props.put(ConsumerConfig.VALUE_DESERIALIZER_CLASS_CONFIG, KafkaAvroDeserializer.class);
        props.put(KafkaAvroDeserializerConfig.SPECIFIC_AVRO_READER_CONFIG, true); 


        // Schema Registry specific settings
        props.put("schema.registry.url", System.getenv("SCHEMA_REGISTRY_URL"));
        if(!System.getenv("BASIC_AUTH_CREDENTIALS_SOURCE").equals("")) {
            props.put("basic.auth.credentials.source", System.getenv("BASIC_AUTH_CREDENTIALS_SOURCE"));
        }
        if(!System.getenv("SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO").equals("")) {
            props.put("schema.registry.basic.auth.user.info", System.getenv("SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO"));
        }       
        
         // interceptor for C3
         // https://docs.confluent.io/current/control-center/installation/clients.html#java-producers-and-consumers
        props.put(ConsumerConfig.INTERCEPTOR_CLASSES_CONFIG,"io.confluent.monitoring.clients.interceptor.MonitoringConsumerInterceptor");
        props.put("confluent.monitoring.interceptor.bootstrap.servers", System.getenv("BOOTSTRAP_SERVERS"));
        props.put("confluent.monitoring.interceptor.security.protocol", "SASL_SSL");
        props.put("confluent.monitoring.interceptor.sasl.jaas.config", "org.apache.kafka.common.security.plain.PlainLoginModule required username=\"" + System.getenv("CLOUD_KEY") + "\" password=\"" + System.getenv("CLOUD_SECRET") + "\";");
        props.put("confluent.monitoring.interceptor.sasl.mechanism", "PLAIN");


        try (final KafkaConsumer<String, Customer> consumer = new KafkaConsumer<>(props)) {
            consumer.subscribe(Arrays.asList(TOPIC));

            while (true) {
                final ConsumerRecords<String, Customer> records = consumer.poll(Duration.ofMillis(100));
                for (final ConsumerRecord<String, Customer> record : records) {
                    final String key = record.key();
                    final Customer value = record.value();
                    System.out.printf("key = %s, value = %s%n", key, value);
                }
            }

        }
    }
}
