package com.github.vdesabou;

import org.apache.kafka.clients.consumer.*;
import org.apache.kafka.common.TopicPartition;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.time.Duration;
import java.util.Collection;
import java.util.Map;
import java.util.Properties;
import java.util.regex.Pattern;
import java.util.stream.Collectors;
import com.github.vdesabou.Customer;

public class SimpleConsumer {

    private static final String KAFKA_ENV_PREFIX = "KAFKA_";
    private final Logger logger = LoggerFactory.getLogger(SimpleConsumer.class);
    private final Properties properties;
    private final String topicName;
    private final boolean checkGaps;
    private final CommitStrategy commitStrategy;

    public static void main(String[] args) {
        SimpleConsumer simpleConsumer = new SimpleConsumer();
        simpleConsumer.start();
    }

    public SimpleConsumer() {
        properties = buildProperties(defaultProps, System.getenv(), KAFKA_ENV_PREFIX);
        topicName = System.getenv().getOrDefault("TOPIC","sample");
        checkGaps = Boolean.valueOf(System.getenv().getOrDefault("CHECK_GAPS","false"));
        commitStrategy = CommitStrategy.valueOf(System.getenv().getOrDefault("COMMIT_STRATEGY","AUTO_COMMIT"));
    }

    private void start() {

        Properties props = buildProperties(defaultProps, System.getenv(), KAFKA_ENV_PREFIX);
        props.put(ConsumerConfig.ENABLE_AUTO_COMMIT_CONFIG, commitStrategy == CommitStrategy.AUTO_COMMIT);
        logger.info("creating producer with props: {}", properties);

        KafkaConsumer<Long, Customer> consumer = new KafkaConsumer<>(props);

        logger.info("Subscribing to {} prefix", topicName);
        consumer.subscribe(Pattern.compile(topicName), listener);
        long lastKey = 0L;
        while (true) {
            ConsumerRecords<Long, Customer> records = consumer.poll(Duration.ofMillis(100));

            if (logger.isDebugEnabled() && !records.isEmpty()) {
                logger.debug("Received {}", records.count());
            }
            for (ConsumerRecord<Long, Customer> record : records) {
                String rp = record.topic() + "#" + record.partition();

                if (checkGaps && record.key() - lastKey != 1L) {
                    logger.warn("KEY GAP found on {} from {} to {}",rp, lastKey,record.key());
                }
                lastKey = record.key();
                logger.debug("Received {} offset = {}, key = {} , value = {}", rp, record.offset(), record.key(), record.value());

                if (commitStrategy == CommitStrategy.PER_MESSAGE) {
                    commit(consumer);
                }
            }
            if (commitStrategy == CommitStrategy.PER_BATCH) {
                commit(consumer);
            }
        }
    }

    private void commit(KafkaConsumer<Long, Customer> consumer) {
        try {
            consumer.commitSync();
        } catch (Exception e) {
            logger.error("failed to commit: ", e);
        }
    }

    private static ConsumerRebalanceListener listener = new ConsumerRebalanceListener() {
        private final Logger logger = LoggerFactory.getLogger(ConsumerRebalanceListener.class);


        @Override
        public void onPartitionsRevoked(Collection<TopicPartition> revokedPartitions) {
            logger.info("Partitions revoked : {}", revokedPartitions);
        }

        @Override
        public void onPartitionsAssigned(Collection<TopicPartition> assignedPartitions) {
            logger.info("Partitions assigned : {}", assignedPartitions);
        }
    };

    private Map<String, String> defaultProps = Map.of(
            ConsumerConfig.BOOTSTRAP_SERVERS_CONFIG, "broker:9092",
            ConsumerConfig.GROUP_ID_CONFIG, "simple-consumer",
            ConsumerConfig.KEY_DESERIALIZER_CLASS_CONFIG, "org.apache.kafka.common.serialization.LongDeserializer",
            ConsumerConfig.VALUE_DESERIALIZER_CLASS_CONFIG, "io.confluent.kafka.serializers.KafkaAvroDeserializer");

    private Properties buildProperties(Map<String, String> baseProps, Map<String, String> envProps, String prefix) {
        Map<String, String> systemProperties = envProps.entrySet()
                .stream()
                .filter(e -> e.getKey().startsWith(prefix))
                .filter(e -> ! e.getValue().isEmpty())
                .collect(Collectors.toMap(
                        e -> e.getKey()
                                .replace(prefix, "")
                                .toLowerCase()
                                .replace("_", ".")
                        , e -> e.getValue())
                );

        Properties props = new Properties();
        props.putAll(baseProps);
        props.putAll(systemProperties);
        return props;
    }

    public enum CommitStrategy {
        AUTO_COMMIT,
        PER_MESSAGE,
        PER_BATCH;
    }
}
