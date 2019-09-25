package com.github.vdesabou;

import org.apache.kafka.clients.CommonClientConfigs;
import org.apache.kafka.clients.producer.Callback;
import org.apache.kafka.clients.producer.KafkaProducer;
import org.apache.kafka.clients.producer.Producer;
import org.apache.kafka.clients.producer.ProducerConfig;
import org.apache.kafka.clients.producer.ProducerRecord;
import org.apache.kafka.clients.producer.RecordMetadata;
import org.apache.kafka.common.config.SaslConfigs;
import io.confluent.kafka.serializers.KafkaAvroSerializer;
import java.util.Properties;
import java.util.concurrent.TimeUnit;
import com.github.vdesabou.Customer;
import com.github.javafaker.Faker;

public class SimpleProducer {

    private static final String TOPIC = "customer-avro";

    public static void main(String[] args) throws InterruptedException {


        Properties props = new Properties();

        props.put(ProducerConfig.BOOTSTRAP_SERVERS_CONFIG, System.getenv("BOOTSTRAP_SERVERS"));

        props.put(ProducerConfig.ACKS_CONFIG, "all");
        props.put(ProducerConfig.REQUEST_TIMEOUT_MS_CONFIG, 20000);
        props.put(ProducerConfig.RETRY_BACKOFF_MS_CONFIG, 500);
        props.put(ProducerConfig.RETRIES_CONFIG, Integer.MAX_VALUE);

        props.put("ssl.endpoint.identification.algorithm", "https");
        props.put(SaslConfigs.SASL_MECHANISM, "PLAIN");
        props.put(SaslConfigs.SASL_JAAS_CONFIG, "org.apache.kafka.common.security.plain.PlainLoginModule required username=\"" + System.getenv("CLOUD_KEY") + "\" password=\"" + System.getenv("CLOUD_SECRET") + "\";");
        props.put(CommonClientConfigs.SECURITY_PROTOCOL_CONFIG, "SASL_SSL");

        props.put(ProducerConfig.KEY_SERIALIZER_CLASS_CONFIG, "org.apache.kafka.common.serialization.StringSerializer");
        props.put(ProducerConfig.VALUE_SERIALIZER_CLASS_CONFIG, KafkaAvroSerializer.class);
        
        // Schema Registry specific settings
        props.put("schema.registry.url", System.getenv("SCHEMA_REGISTRY_URL"));
        props.put("basic.auth.credentials.source", System.getenv("BASIC_AUTH_CREDENTIALS_SOURCE"));
        props.put("schema.registry.basic.auth.user.info", System.getenv("SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO"));
        
         // interceptor for C3
         // https://docs.confluent.io/current/control-center/installation/clients.html#java-producers-and-consumers
        props.put(ProducerConfig.INTERCEPTOR_CLASSES_CONFIG,"io.confluent.monitoring.clients.interceptor.MonitoringProducerInterceptor");
        props.put("confluent.monitoring.interceptor.bootstrap.servers", System.getenv("BOOTSTRAP_SERVERS"));
        props.put("confluent.monitoring.interceptor.security.protocol", "SASL_SSL");
        props.put("confluent.monitoring.interceptor.sasl.jaas.config", "org.apache.kafka.common.security.plain.PlainLoginModule required username=\"" + System.getenv("CLOUD_KEY") + "\" password=\"" + System.getenv("CLOUD_SECRET") + "\";");
        props.put("confluent.monitoring.interceptor.sasl.mechanism", "PLAIN");


        System.out.println("Sending data to `customer-avro` topic. Properties: " + props.toString());

        Faker faker = new Faker();

        String key = "alice";
        try (Producer<String, Customer> producer = new KafkaProducer<>(props)) {
            long i = 0;

            while (true) {

                Customer customer = Customer.newBuilder()
                .setCount(i)
                .setFirstName(faker.name().firstName())
                .setLastName(faker.name().lastName())
                .setAddress(faker.address().streetAddress())
                .build();

                ProducerRecord<String, Customer> record = new ProducerRecord<>(TOPIC, key, customer);
                System.out.println("Sending " + record.key() + " " + record.value());
                producer.send(record, new Callback() {
                    @Override
                    public void onCompletion(RecordMetadata metadata, Exception exception) {
                        if (exception == null) {
                            System.out.printf("Produced record to topic %s partition [%d] @ offset %d%n", metadata.topic(), metadata.partition(), metadata.offset());
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
