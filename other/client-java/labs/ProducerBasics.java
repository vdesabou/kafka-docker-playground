import org.apache.kafka.clients.producer.*;
import org.apache.kafka.common.serialization.StringSerializer;
import java.nio.charset.StandardCharsets;
import java.util.Properties;

public class ProducerBasics {
    public static void main(String[] args) throws Exception {
        Properties props = new Properties();
        props.put(ProducerConfig.BOOTSTRAP_SERVERS_CONFIG, args.length > 0 ? args[0] : "localhost:9092,localhost:9094,localhost:9096");
        props.put(ProducerConfig.KEY_SERIALIZER_CLASS_CONFIG, StringSerializer.class);
        props.put(ProducerConfig.VALUE_SERIALIZER_CLASS_CONFIG, StringSerializer.class);

        try (KafkaProducer<String, String> producer = new KafkaProducer<>(props)) {
            String[] keys = {"customer1", "customer2", "customer3", "customer1", null};
            for (int i = 0; i < keys.length; i++) {
                ProducerRecord<String, String> record = new ProducerRecord<>("orders", keys[i], "order-" + (2000 + i));
                record.headers().add("source", "producer-lab".getBytes(StandardCharsets.UTF_8));
                final String key = keys[i];
                producer.send(record, (metadata, exception) -> {
                    if (exception != null) {
                        System.out.println("FAILED key=" + key + ": " + exception);
                    } else {
                        System.out.println("key=" + key + " -> partition " + metadata.partition() + ", offset " + metadata.offset());
                    }
                });
            }
        }   // close() flushes anything still in the buffer, so every callback has fired by here
    }
}
