import java.io.FileInputStream;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Properties;
import java.util.regex.Pattern;

import org.apache.kafka.clients.consumer.ConsumerConfig;
import org.apache.kafka.clients.consumer.ConsumerRecord;
import org.apache.kafka.clients.consumer.ConsumerRecords;
import org.apache.kafka.clients.consumer.KafkaConsumer;
import org.apache.kafka.clients.producer.KafkaProducer;
import org.apache.kafka.clients.producer.ProducerConfig;
import org.apache.kafka.clients.producer.ProducerRecord;
import org.apache.kafka.common.PartitionInfo;
import org.apache.kafka.common.TopicPartition;
import org.apache.kafka.common.header.Header;
import org.apache.kafka.common.header.internals.RecordHeaders;
import org.apache.kafka.common.serialization.ByteArrayDeserializer;
import org.apache.kafka.common.serialization.ByteArraySerializer;

/**
 * Reads a Kafka Connect dead letter queue, for 'playground topic dlq inspect' and 'playground topic dlq replay'.
 *
 * The records are read from the beginning up to the end offsets taken at start (records written to the topic while
 * it runs are not read, so replaying into the dead letter queue itself cannot loop), with raw bytes: keys and values
 * are re-produced exactly as they are (avro, protobuf, json schema...), only headers are changed.
 *
 *   inspect: prints one "DLQ_RECORD {json}" line per record with the __connect.errors.* headers decoded
 *   replay:  produces the records to --to, or to the topic of their __connect.errors.topic header, without the
 *            __connect.errors.* headers (unless --keep-error-headers), and prints "DLQ_SUMMARY {json}"
 *
 * Arguments: inspect|replay --topic <dlq> --bootstrap-server <servers> [--command-config <client properties>]
 *            [--max-messages <n>] [--grep <regex>] [--to <topic>] [--keep-error-headers] [--dry-run]
 * --grep keeps the records whose exception class, message or root cause match the regex.
 *
 * Uses only the kafka-clients api, run with kafka-run-class so that it gets the kafka jars of the container.
 */
public class DlqTool {

    private static final String PREFIX = "__connect.errors.";

    public static void main(String[] args) throws Exception {
        if (args.length == 0 || (!"inspect".equals(args[0]) && !"replay".equals(args[0]))) {
            usage();
        }
        String mode = args[0];
        String topic = null, bootstrap = null, commandConfig = null, to = null, grep = null;
        long maxMessages = Long.MAX_VALUE;
        boolean keepErrorHeaders = false, dryRun = false;
        for (int i = 1; i < args.length; i++) {
            String a = args[i];
            if ("--keep-error-headers".equals(a)) {
                keepErrorHeaders = true;
                continue;
            }
            if ("--dry-run".equals(a)) {
                dryRun = true;
                continue;
            }
            if (i + 1 >= args.length) {
                usage();
            }
            String v = args[++i];
            switch (a) {
                case "--topic": topic = v; break;
                case "--bootstrap-server": bootstrap = v; break;
                case "--command-config": commandConfig = v; break;
                case "--to": to = v; break;
                case "--grep": grep = v; break;
                case "--max-messages": maxMessages = Long.parseLong(v); break;
                default: usage();
            }
        }
        if (topic == null || bootstrap == null) {
            usage();
        }
        Pattern filter = grep == null || grep.isEmpty() ? null : Pattern.compile(grep);

        Properties common = new Properties();
        if (commandConfig != null && !commandConfig.isEmpty()) {
            try (InputStream in = new FileInputStream(commandConfig)) {
                common.load(in);
            }
        }
        common.put("bootstrap.servers", bootstrap);

        Properties consumerProps = new Properties();
        consumerProps.putAll(common);
        consumerProps.put(ConsumerConfig.KEY_DESERIALIZER_CLASS_CONFIG, ByteArrayDeserializer.class.getName());
        consumerProps.put(ConsumerConfig.VALUE_DESERIALIZER_CLASS_CONFIG, ByteArrayDeserializer.class.getName());
        consumerProps.put(ConsumerConfig.ENABLE_AUTO_COMMIT_CONFIG, "false");
        consumerProps.remove(ConsumerConfig.GROUP_ID_CONFIG);
        consumerProps.put(ConsumerConfig.CLIENT_ID_CONFIG, "playground-dlq-" + mode);

        KafkaProducer<byte[], byte[]> producer = null;
        if ("replay".equals(mode) && !dryRun) {
            Properties producerProps = new Properties();
            producerProps.putAll(common);
            producerProps.put(ProducerConfig.KEY_SERIALIZER_CLASS_CONFIG, ByteArraySerializer.class.getName());
            producerProps.put(ProducerConfig.VALUE_SERIALIZER_CLASS_CONFIG, ByteArraySerializer.class.getName());
            producerProps.put(ProducerConfig.ACKS_CONFIG, "all");
            producerProps.put(ProducerConfig.CLIENT_ID_CONFIG, "playground-dlq-replay");
            producer = new KafkaProducer<>(producerProps);
        }

        long read = 0, replayed = 0, skippedFilter = 0, skippedNoTopic = 0, total = 0;
        Map<String, Long> targets = new LinkedHashMap<>();
        final Exception[] sendError = new Exception[1];
        try (KafkaConsumer<byte[], byte[]> consumer = new KafkaConsumer<>(consumerProps)) {
            List<PartitionInfo> infos = consumer.partitionsFor(topic, Duration.ofSeconds(30));
            if (infos == null || infos.isEmpty()) {
                System.out.println("DLQ_ERROR topic " + topic + " does not exist");
                System.exit(2);
            }
            List<TopicPartition> partitions = new ArrayList<>();
            for (PartitionInfo info : infos) {
                partitions.add(new TopicPartition(topic, info.partition()));
            }
            Map<TopicPartition, Long> begin = consumer.beginningOffsets(partitions, Duration.ofSeconds(30));
            Map<TopicPartition, Long> end = consumer.endOffsets(partitions, Duration.ofSeconds(30));
            Map<TopicPartition, Long> remaining = new HashMap<>();
            for (TopicPartition tp : partitions) {
                total += end.get(tp) - begin.get(tp);
                if (end.get(tp) > begin.get(tp)) {
                    remaining.put(tp, end.get(tp));
                }
            }
            System.out.println("DLQ_TOTAL " + total);
            consumer.assign(new ArrayList<>(remaining.keySet()));
            consumer.seekToBeginning(remaining.keySet());

            long lastProgress = System.currentTimeMillis();
            while (!remaining.isEmpty() && read < maxMessages && sendError[0] == null) {
                ConsumerRecords<byte[], byte[]> records = consumer.poll(Duration.ofSeconds(1));
                if (records.isEmpty()) {
                    // transaction markers and compacted offsets: the position moves without records
                    for (TopicPartition tp : new ArrayList<>(remaining.keySet())) {
                        if (consumer.position(tp) >= remaining.get(tp)) {
                            remaining.remove(tp);
                        }
                    }
                    if (System.currentTimeMillis() - lastProgress > 60000) {
                        System.out.println("DLQ_ERROR no progress for 60 seconds, stopping");
                        break;
                    }
                    continue;
                }
                lastProgress = System.currentTimeMillis();
                for (ConsumerRecord<byte[], byte[]> r : records) {
                    TopicPartition tp = new TopicPartition(r.topic(), r.partition());
                    Long stop = remaining.get(tp);
                    if (stop == null || r.offset() >= stop || read >= maxMessages) {
                        continue;
                    }
                    read++;
                    if (r.offset() + 1 >= stop) {
                        remaining.remove(tp);
                    }
                    Map<String, String> errors = new LinkedHashMap<>();
                    for (Header h : r.headers()) {
                        if (h.key().startsWith(PREFIX)) {
                            errors.put(h.key().substring(PREFIX.length()), h.value() == null ? null : new String(h.value(), StandardCharsets.UTF_8));
                        }
                    }
                    String rootCause = rootCause(errors.get("exception.stacktrace"));
                    if (filter != null) {
                        String haystack = errors.get("exception.class.name") + " " + errors.get("exception.message") + " " + rootCause;
                        if (!filter.matcher(haystack).find()) {
                            skippedFilter++;
                            continue;
                        }
                    }
                    if ("inspect".equals(mode)) {
                        System.out.println("DLQ_RECORD " + recordJson(r, errors, rootCause));
                        continue;
                    }
                    String target = to != null ? to : errors.get("topic");
                    if (target == null || target.isEmpty()) {
                        skippedNoTopic++;
                        continue;
                    }
                    if (producer != null) {
                        RecordHeaders headers = new RecordHeaders();
                        for (Header h : r.headers()) {
                            if (keepErrorHeaders || !h.key().startsWith(PREFIX)) {
                                headers.add(h.key(), h.value());
                            }
                        }
                        Long timestamp = r.timestamp() >= 0 ? r.timestamp() : null;
                        producer.send(new ProducerRecord<>(target, null, timestamp, r.key(), r.value(), headers), (metadata, e) -> {
                            if (e != null && sendError[0] == null) {
                                sendError[0] = e;
                            }
                        });
                        if (sendError[0] != null) {
                            break;
                        }
                    }
                    replayed++;
                    targets.merge(target, 1L, Long::sum);
                }
            }
        } finally {
            if (producer != null) {
                producer.flush();
                producer.close();
            }
        }
        if (sendError[0] != null) {
            System.out.println("DLQ_ERROR could not produce: " + sendError[0]);
            System.exit(3);
        }

        StringBuilder sb = new StringBuilder("{");
        sb.append("\"total\":").append(total)
          .append(",\"read\":").append(read)
          .append(",\"replayed\":").append(replayed)
          .append(",\"skipped_filter\":").append(skippedFilter)
          .append(",\"skipped_no_topic\":").append(skippedNoTopic)
          .append(",\"dry_run\":").append(dryRun)
          .append(",\"targets\":{");
        boolean first = true;
        for (Map.Entry<String, Long> e : targets.entrySet()) {
            if (!first) {
                sb.append(',');
            }
            first = false;
            sb.append(json(e.getKey())).append(':').append(e.getValue());
        }
        sb.append("}}");
        System.out.println("DLQ_SUMMARY " + sb);
    }

    // last "Caused by:" line of the stack trace, or its first line
    private static String rootCause(String stacktrace) {
        if (stacktrace == null) {
            return null;
        }
        String cause = null;
        for (String line : stacktrace.split("\n")) {
            String l = line.trim();
            if (cause == null && !l.isEmpty()) {
                cause = l;
            }
            if (l.startsWith("Caused by:")) {
                cause = l.substring("Caused by:".length()).trim();
            }
        }
        return cause;
    }

    private static String recordJson(ConsumerRecord<byte[], byte[]> r, Map<String, String> errors, String rootCause) {
        StringBuilder sb = new StringBuilder("{");
        sb.append("\"partition\":").append(r.partition())
          .append(",\"offset\":").append(r.offset())
          .append(",\"timestamp\":").append(r.timestamp())
          .append(",\"key_bytes\":").append(r.key() == null ? -1 : r.key().length)
          .append(",\"value_bytes\":").append(r.value() == null ? -1 : r.value().length)
          .append(",\"value_preview\":").append(json(preview(r.value())))
          .append(",\"root_cause\":").append(json(rootCause))
          .append(",\"errors\":{");
        boolean first = true;
        for (Map.Entry<String, String> e : errors.entrySet()) {
            if ("exception.stacktrace".equals(e.getKey())) {
                continue;
            }
            if (!first) {
                sb.append(',');
            }
            first = false;
            sb.append(json(e.getKey())).append(':').append(json(e.getValue()));
        }
        sb.append("}}");
        return sb.toString();
    }

    // first 200 bytes, non printable characters (binary avro / protobuf, magic byte) as '.'
    private static String preview(byte[] value) {
        if (value == null) {
            return null;
        }
        String s = new String(value, 0, Math.min(value.length, 200), StandardCharsets.UTF_8);
        StringBuilder sb = new StringBuilder();
        for (char c : s.toCharArray()) {
            sb.append(c < 0x20 || c == 0xFFFD ? '.' : c);
        }
        return sb.toString();
    }

    private static String json(String s) {
        if (s == null) {
            return "null";
        }
        StringBuilder sb = new StringBuilder("\"");
        for (char c : s.toCharArray()) {
            switch (c) {
                case '"': sb.append("\\\""); break;
                case '\\': sb.append("\\\\"); break;
                case '\n': sb.append("\\n"); break;
                case '\r': sb.append("\\r"); break;
                case '\t': sb.append("\\t"); break;
                default:
                    if (c < 0x20) {
                        sb.append(String.format("\\u%04x", (int) c));
                    } else {
                        sb.append(c);
                    }
            }
        }
        return sb.append('"').toString();
    }

    private static void usage() {
        System.err.println("usage: DlqTool inspect|replay --topic <dlq> --bootstrap-server <servers> [--command-config <file>] "
                + "[--max-messages <n>] [--grep <regex>] [--to <topic>] [--keep-error-headers] [--dry-run]");
        System.exit(1);
    }
}
