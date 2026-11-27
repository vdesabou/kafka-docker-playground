import org.apache.kafka.clients.consumer.*;
import org.apache.kafka.common.TopicPartition;
import org.apache.kafka.common.KafkaException;
import org.apache.kafka.common.errors.*;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import java.time.Duration;
import java.util.*;

/** Generic lab consumer. Args: key=value. Keys starting with x. drive the app, the rest go to the consumer config. */
public class LabConsumer {
    static final Logger log = LoggerFactory.getLogger("lab.LabConsumer");
    public static void main(String[] a) throws Exception {
        Properties p = new Properties();
        Map<String, String> x = new HashMap<>();
        p.put("key.deserializer", "org.apache.kafka.common.serialization.StringDeserializer");
        p.put("value.deserializer", "org.apache.kafka.common.serialization.StringDeserializer");
        p.put("enable.auto.commit", "false");
        p.put("auto.offset.reset", "earliest");
        for (String s : a) { int i = s.indexOf('='); String k = s.substring(0, i), v = s.substring(i + 1);
            if (k.startsWith("x.")) x.put(k, v); else p.put(k, v); }
        String topic = x.getOrDefault("x.topic", "orders");
        long runMs = Long.parseLong(x.getOrDefault("x.run.ms", "30000"));
        long sleepMs = Long.parseLong(x.getOrDefault("x.sleep.ms", "0"));
        boolean sleepOnce = Boolean.parseBoolean(x.getOrDefault("x.sleep.once", "false"));
        String commit = x.getOrDefault("x.commit", "sync");
        boolean catchCommit = Boolean.parseBoolean(x.getOrDefault("x.catch", "false"));
        String poison = x.getOrDefault("x.poison", "throw");
        long pollMs = Long.parseLong(x.getOrDefault("x.poll.ms", "1000"));
        int flood = Integer.parseInt(x.getOrDefault("x.flood", "0"));
        boolean printRecords = Boolean.parseBoolean(x.getOrDefault("x.print", "false"));
        String name = x.getOrDefault("x.name", p.getProperty("client.id", "app"));
        long commitEvery = Long.parseLong(x.getOrDefault("x.commit.interval.ms", "0")); long lastCommit = System.currentTimeMillis();
        log.info("{} starting: group.id={} topic={} sleep.ms={} commit={}", name, p.getProperty("group.id"), topic, sleepMs, commit);
        KafkaConsumer<Object, Object> c;
        try { c = new KafkaConsumer<>(p); }
        catch (Exception e) { log.error("{} failed to construct KafkaConsumer", name, e); System.out.println("CONSTRUCT FAILED: " + e); return; }
        c.subscribe(Arrays.asList(topic.split(",")), new ConsumerRebalanceListener() {
            public void onPartitionsRevoked(Collection<TopicPartition> ps) { log.info("{} onPartitionsRevoked {}", name, ps); }
            public void onPartitionsAssigned(Collection<TopicPartition> ps) { log.info("{} onPartitionsAssigned {}", name, ps); }
        });
        Map<TopicPartition, OffsetAndMetadata> pending = new HashMap<>();
        long end = System.currentTimeMillis() + runMs; long total = 0; boolean slept = false; int pollErrors = 0;
        try {
            while (System.currentTimeMillis() < end) {
                ConsumerRecords<Object, Object> recs;
                try { recs = c.poll(Duration.ofMillis(pollMs)); }
                catch (RecordDeserializationException e) {
                    pollErrors++;
                    log.error("{} poll() threw RecordDeserializationException (#{}) for {} offset {}", name, pollErrors, e.topicPartition(), e.offset(), e);
                    if (poison.equals("seek")) { c.seek(e.topicPartition(), e.offset() + 1);
                        log.info("{} skipped poison record: seek({}, {})", name, e.topicPartition(), e.offset() + 1); }
                    else if (poison.equals("throw")) throw e;
                    else Thread.sleep(500);
                    continue;
                } catch (WakeupException e) { throw e; }
                catch (KafkaException e) {
                    if (!catchCommit) throw e;
                    log.error("{} poll() threw {}", name, e.toString()); Thread.sleep(1000); continue;
                }
                if (!recs.isEmpty()) {
                    total += recs.count();
                    Map<TopicPartition, String> ranges = new LinkedHashMap<>();
                    for (ConsumerRecord<Object, Object> r : recs) {
                        TopicPartition tp = new TopicPartition(r.topic(), r.partition());
                        String seen = ranges.get(tp);
                        String from = seen == null ? String.valueOf(r.offset()) : seen.substring(0, seen.indexOf('.'));
                        ranges.put(tp, from + ".." + r.offset());
                        pending.put(tp, new OffsetAndMetadata(r.offset() + 1));
                        if (printRecords) log.info("{} record {}-{}@{} value={}", name, r.topic(), r.partition(), r.offset(), r.value());
                    }
                    log.info("{} poll returned {} records {}, total {}", name, recs.count(), ranges, total);
                    if (sleepMs > 0 && !(sleepOnce && slept)) { log.info("{} processing for {} ms", name, sleepMs); Thread.sleep(sleepMs); slept = true; log.info("{} processing done", name); }
                }
                if (flood > 0 && !pending.isEmpty()) {
                    long t0 = System.currentTimeMillis();
                    for (int i = 0; i < flood; i++) c.commitSync(pending);
                    log.info("{} committed the same offsets {} times in {} ms", name, flood, System.currentTimeMillis() - t0);
                    flood = 0;
                }
                if (!pending.isEmpty() && System.currentTimeMillis() - lastCommit >= commitEvery) {
                    lastCommit = System.currentTimeMillis();
                    Map<TopicPartition, OffsetAndMetadata> toCommit = new HashMap<>(pending);
                    if (commit.equals("sync")) {
                        try { c.commitSync(toCommit); log.info("{} commitSync ok {}", name, toCommit); pending.clear(); }
                        catch (RebalanceInProgressException e) {
                            log.warn("{} commitSync failed, retriable, will poll() and retry: {}", name, e.toString());
                        } catch (CommitFailedException e) {
                            if (!catchCommit) throw e;
                            log.error("{} commitSync failed, offsets not committed, records will be redelivered: {}", name, e.toString());
                            pending.clear();
                        } catch (RetriableException e) {
                            log.warn("{} commitSync failed, retriable, will retry: {}", name, e.toString());
                        }
                    } else if (commit.equals("async")) {
                        final Map<TopicPartition, OffsetAndMetadata> sent = toCommit;
                        c.commitAsync(toCommit, (offs, ex) -> {
                            if (ex == null) log.info("{} commitAsync ok {}", name, offs);
                            else log.warn("{} commitAsync callback exception (retriable={}): {}", name, ex instanceof RetriableException, ex.toString());
                        });
                        pending.clear();
                        if (Boolean.parseBoolean(x.getOrDefault("x.async.keep", "false"))) pending.putAll(sent);
                    } else pending.clear();
                }
            }
        } catch (Exception e) {
            log.error("{} stopped on exception", name, e);
        } finally {
            log.info("{} closing, consumed {} records", name, total);
            c.close();
            log.info("{} closed", name);
        }
    }
}
