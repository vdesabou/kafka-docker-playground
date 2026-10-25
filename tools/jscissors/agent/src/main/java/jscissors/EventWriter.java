package jscissors;

import java.io.BufferedWriter;
import java.io.File;
import java.io.IOException;
import java.io.OutputStreamWriter;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.util.concurrent.ArrayBlockingQueue;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicLong;

/**
 * Writes events.jsonl from a background thread: the traced threads only put a line in a bounded queue, and never
 * wait for the disk. When the queue is full the event is dropped and counted. Also refreshes summary.json every 5 s,
 * so that a JVM killed without --action stop still leaves its statistics.
 */
final class EventWriter implements Runnable {
    private final ArrayBlockingQueue<String> queue = new ArrayBlockingQueue<>(100000);
    private final Session session;
    private final BufferedWriter writer;
    private final Thread thread;
    private volatile boolean running = true;
    final AtomicLong written = new AtomicLong();
    final AtomicLong dropped = new AtomicLong();

    EventWriter(Session session, File file) throws IOException {
        this.session = session;
        this.writer = new BufferedWriter(new OutputStreamWriter(Files.newOutputStream(file.toPath()), StandardCharsets.UTF_8), 1 << 16);
        this.thread = new Thread(this, "jscissors-writer");
        this.thread.setDaemon(true);
        this.thread.start();
    }

    void offer(String line) {
        if (!queue.offer(line)) {
            dropped.incrementAndGet();
        }
    }

    @Override
    public void run() {
        long lastSummary = System.currentTimeMillis();
        while (running) {
            try {
                String line = queue.poll(200, TimeUnit.MILLISECONDS);
                if (line != null) {
                    write(line);
                    drain();
                }
                writer.flush();
                if (System.currentTimeMillis() - lastSummary >= 5000) {
                    lastSummary = System.currentTimeMillis();
                    session.writeSummary(false);
                }
            } catch (InterruptedException e) {
                break;
            } catch (Throwable t) {
                session.error("writing events.jsonl", t);
            }
        }
    }

    private void drain() throws IOException {
        String line;
        while ((line = queue.poll()) != null) {
            write(line);
        }
    }

    private void write(String line) throws IOException {
        writer.write(line);
        writer.write('\n');
        written.incrementAndGet();
    }

    void close() {
        running = false;
        try {
            thread.join(5000);
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
        }
        try {
            drain();
            writer.close();
        } catch (IOException e) {
            session.error("closing events.jsonl", e);
        }
    }
}
