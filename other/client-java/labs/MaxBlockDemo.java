import org.apache.kafka.clients.producer.*;
import org.apache.kafka.common.serialization.StringSerializer;
import java.util.Properties;

public class MaxBlockDemo {
    public static void main(String[] args) throws Exception {
        Properties props = new Properties();
        props.put(ProducerConfig.BOOTSTRAP_SERVERS_CONFIG, args.length > 1 ? args[1] : "localhost:9092,localhost:9094,localhost:9096");
        props.put(ProducerConfig.KEY_SERIALIZER_CLASS_CONFIG, StringSerializer.class);
        props.put(ProducerConfig.VALUE_SERIALIZER_CLASS_CONFIG, StringSerializer.class);
        props.put(ProducerConfig.MAX_BLOCK_MS_CONFIG, 5000);
        try (KafkaProducer<String, String> producer = new KafkaProducer<>(props)) {
            long start = System.currentTimeMillis();
            try {
                producer.send(new ProducerRecord<>(args[0], "k", "v"), (metadata, exception) -> {
                    if (exception != null) System.out.println("callback: " + exception);
                    else System.out.println("callback: partition " + metadata.partition() + ", offset " + metadata.offset());
                });
                System.out.println("send() returned after " + (System.currentTimeMillis() - start) + " ms");
            } catch (Exception e) {
                System.out.println("send() threw after " + (System.currentTimeMillis() - start) + " ms: " + e);
            }
        }
    }
}
