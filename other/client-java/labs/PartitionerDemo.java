import org.apache.kafka.clients.producer.*;
import org.apache.kafka.common.Cluster;
import org.apache.kafka.common.serialization.StringSerializer;
import org.apache.kafka.common.utils.Utils;
import java.util.Map;
import java.util.Properties;

public class PartitionerDemo {
    // VIP customers always go to partition 0; everyone else is hashed across the other partitions
    public static class VipPartitioner implements Partitioner {
        public int partition(String topic, Object key, byte[] keyBytes, Object value, byte[] valueBytes, Cluster cluster) {
            int n = cluster.partitionCountForTopic(topic);
            if (key != null && key.toString().startsWith("vip-")) return 0;
            return 1 + Utils.toPositive(Utils.murmur2(keyBytes)) % (n - 1);
        }
        public void close() {}
        public void configure(Map<String, ?> configs) {}
    }

    public static void main(String[] args) throws Exception {
        Properties props = new Properties();
        props.put(ProducerConfig.BOOTSTRAP_SERVERS_CONFIG, args.length > 0 ? args[0] : "localhost:9092,localhost:9094,localhost:9096");
        props.put(ProducerConfig.KEY_SERIALIZER_CLASS_CONFIG, StringSerializer.class);
        props.put(ProducerConfig.VALUE_SERIALIZER_CLASS_CONFIG, StringSerializer.class);
        props.put(ProducerConfig.PARTITIONER_CLASS_CONFIG, VipPartitioner.class);

        try (KafkaProducer<String, String> producer = new KafkaProducer<>(props)) {
            for (String key : new String[]{"vip-alice", "bob", "vip-carol", "dave", "erin", "frank", "grace", "heidi"}) {
                producer.send(new ProducerRecord<>("orders", key, "order"), (m, e) ->
                    System.out.println(e != null ? "FAILED " + key + ": " + e : key + " -> partition " + m.partition()));
            }
        }
    }
}
