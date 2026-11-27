import org.apache.kafka.clients.producer.*;
import org.apache.kafka.common.serialization.StringSerializer;
import java.util.Properties;

public class SyncVsAsync {
    public static void main(String[] args) throws Exception {
        int count = 2000;
        Properties props = new Properties();
        props.put(ProducerConfig.BOOTSTRAP_SERVERS_CONFIG, args.length > 0 ? args[0] : "localhost:9092,localhost:9094,localhost:9096");
        props.put(ProducerConfig.KEY_SERIALIZER_CLASS_CONFIG, StringSerializer.class);
        props.put(ProducerConfig.VALUE_SERIALIZER_CLASS_CONFIG, StringSerializer.class);

        try (KafkaProducer<String, String> producer = new KafkaProducer<>(props)) {
            long t0 = System.nanoTime();
            for (int i = 0; i < count; i++) {
                producer.send(new ProducerRecord<>("orders", "k" + i, "sync-" + i)).get();   // wait for every ack
            }
            long sync = (System.nanoTime() - t0) / 1_000_000;

            t0 = System.nanoTime();
            for (int i = 0; i < count; i++) {
                producer.send(new ProducerRecord<>("orders", "k" + i, "async-" + i), (m, e) -> { if (e != null) System.out.println(e); });
            }
            producer.flush();   // wait until the buffer is empty
            long async = (System.nanoTime() - t0) / 1_000_000;

            System.out.println(count + " records, send().get() each time: " + sync + " ms");
            System.out.println(count + " records, send() with a callback:  " + async + " ms");
        }
    }
}
