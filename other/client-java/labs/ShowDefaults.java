import org.apache.kafka.clients.producer.ProducerConfig;
import java.util.Properties;

public class ShowDefaults {
    public static void main(String[] args) {
        Properties props = new Properties();
        props.put("bootstrap.servers", "localhost:9092");
        props.put("key.serializer", "org.apache.kafka.common.serialization.StringSerializer");
        props.put("value.serializer", "org.apache.kafka.common.serialization.StringSerializer");
        ProducerConfig config = new ProducerConfig(props);   // works out every default without connecting
        for (String name : new String[]{"acks", "enable.idempotence", "retries", "linger.ms", "batch.size",
                "request.timeout.ms", "delivery.timeout.ms", "max.block.ms", "buffer.memory", "compression.type"}) {
            System.out.println(name + " = " + config.values().get(name));
        }
    }
}
