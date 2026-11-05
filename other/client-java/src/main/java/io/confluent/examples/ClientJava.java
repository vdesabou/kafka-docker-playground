// Apache Kafka Java client (kafka-clients) with the Confluent Avro serializer for Schema Registry.
//
// usage: java -jar client-java.jar produce|consume|produce-avro|consume-avro <topic> <config file> [<number of messages>]
//
// The config file holds Java client properties (bootstrap.servers, security.protocol, sasl.*, ssl.*...) and the
// schema.registry.* properties of the Schema Registry client: schema.registry.url, basic.auth.credentials.source,
// basic.auth.user.info (all passed as they are to the serializer and the deserializer).
package io.confluent.examples;

import io.confluent.kafka.serializers.KafkaAvroDeserializer;
import io.confluent.kafka.serializers.KafkaAvroSerializer;
import java.io.FileInputStream;
import java.io.IOException;
import java.time.Duration;
import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import java.util.Properties;
import java.util.concurrent.Future;
import org.apache.avro.Schema;
import org.apache.avro.generic.GenericData;
import org.apache.avro.generic.GenericRecord;
import org.apache.kafka.clients.consumer.ConsumerConfig;
import org.apache.kafka.clients.consumer.ConsumerRecord;
import org.apache.kafka.clients.consumer.ConsumerRecords;
import org.apache.kafka.clients.consumer.KafkaConsumer;
import org.apache.kafka.clients.producer.KafkaProducer;
import org.apache.kafka.clients.producer.ProducerConfig;
import org.apache.kafka.clients.producer.ProducerRecord;
import org.apache.kafka.clients.producer.RecordMetadata;
import org.apache.kafka.common.serialization.StringDeserializer;
import org.apache.kafka.common.serialization.StringSerializer;

public class ClientJava {

    private static final String USAGE =
        "usage: java -jar client-java.jar produce|consume|produce-avro|consume-avro <topic> <config file> [<number of messages>]";

    private static final Schema PAYMENT_SCHEMA = new Schema.Parser().parse(
        "{\"type\":\"record\",\"name\":\"Payment\",\"namespace\":\"io.confluent.examples\","
            + "\"fields\":[{\"name\":\"id\",\"type\":\"string\"},{\"name\":\"amount\",\"type\":\"double\"}]}");

    private static final Duration CONSUME_TIMEOUT = Duration.ofSeconds(60);

    public static void main(String[] args) throws Exception {
        if (args.length < 3 || args.length > 4) {
            System.err.println(USAGE);
            System.exit(1);
        }
        String mode = args[0];
        String topic = args[1];
        Properties props = loadConfig(args[2]);
        int nbMessages = args.length == 4 ? Integer.parseInt(args[3]) : 10;

        switch (mode) {
            case "produce" -> produce(topic, props, nbMessages, false);
            case "produce-avro" -> produce(topic, props, nbMessages, true);
            case "consume" -> consume(topic, props, nbMessages, false);
            case "consume-avro" -> consume(topic, props, nbMessages, true);
            default -> {
                System.err.println(USAGE);
                System.exit(1);
            }
        }
    }

    private static Properties loadConfig(String path) throws IOException {
        Properties props = new Properties();
        try (FileInputStream in = new FileInputStream(path)) {
            props.load(in);
        }
        return props;
    }

    private static void produce(String topic, Properties config, int nbMessages, boolean avro) throws Exception {
        Properties props = new Properties();
        props.putAll(config);
        props.put(ProducerConfig.ACKS_CONFIG, "all");
        props.put(ProducerConfig.CLIENT_ID_CONFIG, "client-java-producer");
        props.put(ProducerConfig.KEY_SERIALIZER_CLASS_CONFIG, StringSerializer.class.getName());
        props.put(ProducerConfig.VALUE_SERIALIZER_CLASS_CONFIG,
            avro ? KafkaAvroSerializer.class.getName() : StringSerializer.class.getName());

        try (KafkaProducer<String, Object> producer = new KafkaProducer<>(props)) {
            List<Future<RecordMetadata>> acks = new ArrayList<>();
            for (int i = 0; i < nbMessages; i++) {
                Object value;
                if (avro) {
                    GenericRecord payment = new GenericData.Record(PAYMENT_SCHEMA);
                    payment.put("id", "payment-" + i);
                    payment.put("amount", 10.0 * i);
                    value = payment;
                } else {
                    value = "{\"count\":" + i + "}";
                }
                acks.add(producer.send(new ProducerRecord<>(topic, "key-" + i, value)));
            }
            int nbProduced = 0;
            for (Future<RecordMetadata> ack : acks) {
                RecordMetadata metadata = ack.get();
                System.out.printf("Produced record to %s [%d] at offset %d%n",
                    metadata.topic(), metadata.partition(), metadata.offset());
                nbProduced++;
            }
            System.out.printf("%d records were produced to topic %s%n", nbProduced, topic);
        }
    }

    private static void consume(String topic, Properties config, int nbMessages, boolean avro) {
        String groupId = topic + "-group";
        Properties props = new Properties();
        props.putAll(config);
        props.put(ConsumerConfig.GROUP_ID_CONFIG, groupId);
        props.put(ConsumerConfig.CLIENT_ID_CONFIG, "client-java-consumer");
        props.put(ConsumerConfig.AUTO_OFFSET_RESET_CONFIG, "earliest");
        props.put(ConsumerConfig.ENABLE_AUTO_COMMIT_CONFIG, "false");
        props.put(ConsumerConfig.KEY_DESERIALIZER_CLASS_CONFIG, StringDeserializer.class.getName());
        props.put(ConsumerConfig.VALUE_DESERIALIZER_CLASS_CONFIG,
            avro ? KafkaAvroDeserializer.class.getName() : StringDeserializer.class.getName());

        int nbConsumed = 0;
        // close() leaves the group right away: without it the member stays until its session times out
        try (KafkaConsumer<String, Object> consumer = new KafkaConsumer<>(props)) {
            consumer.subscribe(List.of(topic));
            Instant deadline = Instant.now().plus(CONSUME_TIMEOUT);
            while (nbConsumed < nbMessages) {
                if (Instant.now().isAfter(deadline)) {
                    System.err.printf("Timeout: consumed %d records out of %d after %d seconds%n",
                        nbConsumed, nbMessages, CONSUME_TIMEOUT.toSeconds());
                    System.exit(1);
                }
                ConsumerRecords<String, Object> records = consumer.poll(Duration.ofMillis(500));
                for (ConsumerRecord<String, Object> record : records) {
                    System.out.printf("Consumed record from %s [%d] at offset %d: key=%s value=%s%n",
                        record.topic(), record.partition(), record.offset(), record.key(), record.value());
                }
                if (!records.isEmpty()) {
                    nbConsumed += records.count();
                    consumer.commitSync();
                }
            }
        }
        System.out.printf("%d records were consumed from topic %s by group %s%n", nbConsumed, topic, groupId);
    }
}
