package com.github.vdesabou;

import java.io.FileInputStream;
import java.io.IOException;
import java.io.InputStream;
import java.time.Duration;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Properties;
import java.util.TreeMap;

import org.apache.kafka.clients.consumer.ConsumerConfig;
import org.apache.kafka.clients.consumer.ConsumerRecord;
import org.apache.kafka.clients.consumer.KafkaConsumer;
import org.apache.kafka.clients.producer.KafkaProducer;
import org.apache.kafka.clients.producer.ProducerConfig;
import org.apache.kafka.clients.producer.ProducerRecord;
import org.apache.kafka.common.PartitionInfo;
import org.apache.kafka.common.TopicPartition;
import org.apache.kafka.common.serialization.ByteArrayDeserializer;
import org.apache.kafka.common.serialization.ByteArraySerializer;

/**
 * Copies every record of a topic (keys, values, headers, timestamps, partition by partition and in order) to another
 * topic in one transaction, then commits it, aborts it, or leaves it open (the process stops without ending it: the
 * coordinator aborts it after transaction.timeout.ms). Used by 'playground topic produce --transactional-id'.
 */
public class TransactionalCopier {

    public static void main(String[] args) throws Exception {
        Map<String, String> options = new HashMap<>();
        for (int i = 0; i + 1 < args.length; i += 2) {
            options.put(args[i], args[i + 1]);
        }
        String bootstrapServer = required(options, "--bootstrap-server");
        String inputTopic = required(options, "--input-topic");
        String outputTopic = required(options, "--output-topic");
        String transactionalId = required(options, "--transactional-id");
        String transaction = options.getOrDefault("--transaction", "commit");
        String transactionTimeoutMs = options.getOrDefault("--transaction-timeout-ms", "60000");
        if (!transaction.equals("commit") && !transaction.equals("abort") && !transaction.equals("open")) {
            usage("--transaction must be commit, abort or open");
        }

        Properties common = new Properties();
        if (options.containsKey("--command-config")) {
            try (InputStream in = new FileInputStream(options.get("--command-config"))) {
                common.load(in);
            } catch (IOException e) {
                usage("cannot read " + options.get("--command-config") + ": " + e.getMessage());
            }
        }
        common.put("bootstrap.servers", bootstrapServer);

        Properties consumerProps = new Properties();
        consumerProps.putAll(common);
        consumerProps.put(ConsumerConfig.KEY_DESERIALIZER_CLASS_CONFIG, ByteArrayDeserializer.class.getName());
        consumerProps.put(ConsumerConfig.VALUE_DESERIALIZER_CLASS_CONFIG, ByteArrayDeserializer.class.getName());
        consumerProps.put(ConsumerConfig.ENABLE_AUTO_COMMIT_CONFIG, "false");

        Properties producerProps = new Properties();
        producerProps.putAll(common);
        producerProps.put(ProducerConfig.KEY_SERIALIZER_CLASS_CONFIG, ByteArraySerializer.class.getName());
        producerProps.put(ProducerConfig.VALUE_SERIALIZER_CLASS_CONFIG, ByteArraySerializer.class.getName());
        producerProps.put(ProducerConfig.TRANSACTIONAL_ID_CONFIG, transactionalId);
        producerProps.put(ProducerConfig.TRANSACTION_TIMEOUT_CONFIG, transactionTimeoutMs);
        producerProps.put(ProducerConfig.ENABLE_IDEMPOTENCE_CONFIG, "true");
        producerProps.put(ProducerConfig.ACKS_CONFIG, "all");
        // the records were accepted by the staging topic: the limits of the topic decide, not the producer defaults
        producerProps.put(ProducerConfig.MAX_REQUEST_SIZE_CONFIG, "104857600");
        producerProps.put(ProducerConfig.BUFFER_MEMORY_CONFIG, "268435456");
        producerProps.put(ProducerConfig.REQUEST_TIMEOUT_MS_CONFIG, "60000");

        KafkaConsumer<byte[], byte[]> consumer = new KafkaConsumer<>(consumerProps);
        List<TopicPartition> partitions = new ArrayList<>();
        for (PartitionInfo info : consumer.partitionsFor(inputTopic, Duration.ofSeconds(60))) {
            partitions.add(new TopicPartition(inputTopic, info.partition()));
        }
        consumer.assign(partitions);
        consumer.seekToBeginning(partitions);
        Map<TopicPartition, Long> endOffsets = consumer.endOffsets(partitions);

        KafkaProducer<byte[], byte[]> producer = new KafkaProducer<>(producerProps);
        producer.initTransactions();
        producer.beginTransaction();

        Map<Integer, Integer> copied = new TreeMap<>();
        long deadline = System.currentTimeMillis() + 120_000;
        while (!reachedEnd(consumer, partitions, endOffsets)) {
            if (System.currentTimeMillis() > deadline) {
                System.err.println("timeout: could not read every record of " + inputTopic + " in 120 seconds");
                producer.abortTransaction();
                System.exit(1);
            }
            for (ConsumerRecord<byte[], byte[]> record : consumer.poll(Duration.ofSeconds(1))) {
                if (record.offset() >= endOffsets.get(new TopicPartition(record.topic(), record.partition()))) {
                    continue;
                }
                producer.send(new ProducerRecord<>(outputTopic, record.partition(), record.timestamp(), record.key(),
                        record.value(), record.headers()));
                copied.merge(record.partition(), 1, Integer::sum);
            }
        }
        producer.flush();
        consumer.close();

        int total = copied.values().stream().mapToInt(Integer::intValue).sum();
        System.out.println("records sent in the transaction of " + transactionalId + ": " + total + " " + copied);
        switch (transaction) {
            case "commit":
                producer.commitTransaction();
                System.out.println("transaction committed");
                producer.close();
                break;
            case "abort":
                producer.abortTransaction();
                System.out.println("transaction aborted");
                producer.close();
                break;
            default:
                System.out.println("transaction left open, the coordinator aborts it after transaction.timeout.ms ("
                        + transactionTimeoutMs + " ms)");
                System.out.flush();
                // no close(): it would wait for the transaction to end
                Runtime.getRuntime().halt(0);
        }
    }

    private static boolean reachedEnd(KafkaConsumer<byte[], byte[]> consumer, List<TopicPartition> partitions,
            Map<TopicPartition, Long> endOffsets) {
        for (TopicPartition partition : partitions) {
            if (consumer.position(partition) < endOffsets.get(partition)) {
                return false;
            }
        }
        return true;
    }

    private static String required(Map<String, String> options, String name) {
        String value = options.get(name);
        if (value == null) {
            usage("missing " + name);
        }
        return value;
    }

    private static void usage(String error) {
        System.err.println(error);
        System.err.println("usage: TransactionalCopier --bootstrap-server <host:port> [--command-config <file>]"
                + " --input-topic <topic> --output-topic <topic> --transactional-id <id>"
                + " [--transaction commit|abort|open] [--transaction-timeout-ms <ms>]");
        System.exit(2);
    }
}
