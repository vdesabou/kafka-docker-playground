package jscissors;

import java.io.File;
import java.io.OutputStreamWriter;
import java.io.Writer;
import java.lang.management.LockInfo;
import java.lang.management.ManagementFactory;
import java.lang.management.MonitorInfo;
import java.lang.management.ThreadInfo;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.util.ArrayList;
import java.util.List;
import javax.management.ObjectName;

/**
 * Thread and heap dumps taken when a traced method is called, returns or throws: rate limited (maxThreadDumps,
 * maxHeapDumps, dumpIntervalMs) so that a rule on a hot method cannot freeze the JVM or fill its disk.
 */
final class Dumps {
    private final Session session;
    private final File dir;
    private int threadDumps;
    private int heapDumps;
    private long lastThreadDump;
    private long lastHeapDump;
    long skipped;
    final List<String> files = new ArrayList<>();

    Dumps(Session session, File dir) {
        this.session = session;
        this.dir = dir;
    }

    synchronized void threads(long id, String when, String origin) {
        long now = System.currentTimeMillis();
        if (threadDumps >= session.config.get("maxThreadDumps") || now - lastThreadDump < session.config.get("dumpIntervalMs")) {
            skipped++;
            return;
        }
        threadDumps++;
        lastThreadDump = now;
        dir.mkdirs();
        String name = "threads-" + threadDumps + "-" + now + ".txt";
        File file = new File(dir, name);
        String error = null;
        try (Writer w = new OutputStreamWriter(Files.newOutputStream(file.toPath()), StandardCharsets.UTF_8)) {
            w.write(threadPrint());
        } catch (Throwable t) {
            error = t.toString();
        }
        record("threads", id, when, origin, name, error);
    }

    synchronized void heap(long id, String when, String origin) {
        long now = System.currentTimeMillis();
        if (heapDumps >= session.config.get("maxHeapDumps") || now - lastHeapDump < session.config.get("dumpIntervalMs")) {
            skipped++;
            return;
        }
        heapDumps++;
        lastHeapDump = now;
        dir.mkdirs();
        String name = "heap-" + heapDumps + "-" + now + ".hprof";
        String error = null;
        try {
            ManagementFactory.newPlatformMXBeanProxy(ManagementFactory.getPlatformMBeanServer(),
                    "com.sun.management:type=HotSpotDiagnostic", com.sun.management.HotSpotDiagnosticMXBean.class)
                    .dumpHeap(new File(dir, name).getAbsolutePath(), true);
        } catch (Throwable t) {
            error = t.toString();
        }
        record("heap", id, when, origin, name, error);
    }

    private void record(String kind, long id, String when, String origin, String name, String error) {
        String file = "dumps/" + name;
        if (error == null) {
            files.add(file);
        }
        StringBuilder sb = session.event("dump", id, System.nanoTime());
        Json.field(sb, "kind", kind);
        Json.field(sb, "when", when);
        Json.field(sb, "origin", origin);
        Json.field(sb, error == null ? "file" : "error", error == null ? file : error);
        session.emit(sb.append('}'));
        session.log((error == null ? kind + " dump written to " : kind + " dump failed: " + error + ", ") + file + " (" + when + " " + origin + ")");
    }

    /** the format of jstack (Thread.print), which playground analyze thread-dump reads */
    private static String threadPrint() throws Exception {
        try {
            return (String) ManagementFactory.getPlatformMBeanServer().invoke(new ObjectName("com.sun.management:type=DiagnosticCommand"),
                    "threadPrint", new Object[]{new String[]{"-l"}}, new String[]{String[].class.getName()});
        } catch (Throwable t) {
            return threadMXBeanDump();
        }
    }

    private static String threadMXBeanDump() {
        StringBuilder sb = new StringBuilder("Full thread dump (ThreadMXBean):\n\n");
        for (ThreadInfo ti : ManagementFactory.getThreadMXBean().dumpAllThreads(true, true)) {
            sb.append('"').append(ti.getThreadName()).append("\" #").append(ti.getThreadId())
                    .append("\n   java.lang.Thread.State: ").append(ti.getThreadState()).append('\n');
            StackTraceElement[] frames = ti.getStackTrace();
            for (int i = 0; i < frames.length; i++) {
                sb.append("\tat ").append(frames[i]).append('\n');
                if (i == 0 && ti.getLockInfo() != null) {
                    LockInfo lock = ti.getLockInfo();
                    sb.append("\t- waiting on <0x").append(Integer.toHexString(lock.getIdentityHashCode())).append("> (a ").append(lock.getClassName()).append(")\n");
                }
                for (MonitorInfo mi : ti.getLockedMonitors()) {
                    if (mi.getLockedStackDepth() == i) {
                        sb.append("\t- locked <0x").append(Integer.toHexString(mi.getIdentityHashCode())).append("> (a ").append(mi.getClassName()).append(")\n");
                    }
                }
            }
            sb.append('\n');
        }
        return sb.toString();
    }
}
