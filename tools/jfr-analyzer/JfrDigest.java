import java.nio.file.Path;
import java.time.Duration;
import java.time.Instant;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.regex.Pattern;

import jdk.jfr.consumer.RecordedClass;
import jdk.jfr.consumer.RecordedEvent;
import jdk.jfr.consumer.RecordedFrame;
import jdk.jfr.consumer.RecordedObject;
import jdk.jfr.consumer.RecordedStackTrace;
import jdk.jfr.consumer.RecordedThread;
import jdk.jfr.consumer.RecordingFile;

/**
 * Digest of a Java Flight Recorder file for tools/jfr-analyzer/jfr_analyzer.py: the events that matter to tell where the
 * time of some threads goes (Kafka Connect task threads by default), aggregated so that the output stays small.
 *
 *   java JfrDigest.java <recording.jfr> [--threads <regex>] [--depth <frames>]
 *
 * Runs with the source launcher of a JDK 17+ (playground analyze flight-recorder uses eclipse-temurin:25-jdk), reads
 * recordings of JDK 11+ JVMs, and prints one json document on stdout. No classification here: frames are printed as
 * "package.Class.method" strings, interned in "frames", and the python side decides what they mean.
 */
public class JfrDigest {

    static final Map<String, Integer> frameIds = new HashMap<>();
    static final List<String> frames = new ArrayList<>();
    static int depth = 40;
    static final int EVENT_DEPTH = 16;

    static class ThreadStats {
        double cpuUser, cpuSystem;
        int cpuN;
        long execSamples, nativeSamples;
        final List<Long> cpuTimes = new ArrayList<>();
        long monitorNs, parkNs, waitNs, sleepNs, fileNs;
        final Map<String, long[]> socket = new LinkedHashMap<>(); // "op remote" -> count, ns, bytes
        final Map<String, Long> nativeStacks = new HashMap<>();
        // the java threads sampled under this name: a task restarted while its thread is busy leaves that thread
        // running, with the same name as the new one
        final Set<Long> javaIds = new HashSet<>();
    }

    static class Agg {
        long count, ns, bytes;
        String kind, cls;
        String stack;
    }

    public static void main(String[] args) throws Exception {
        List<Path> files = new ArrayList<>();
        String threadFilter = "^task-thread-.*";
        for (int i = 0; i < args.length; i++) {
            switch (args[i]) {
                case "--threads" -> threadFilter = args[++i];
                case "--depth" -> depth = Integer.parseInt(args[++i]);
                default -> files.add(Path.of(args[i]));
            }
        }
        if (files.isEmpty()) {
            System.err.println("usage: java JfrDigest.java <recording.jfr>... [--threads <regex>] [--depth <frames>]");
            System.exit(64);
        }
        Pattern filter = Pattern.compile(threadFilter);

        // first pass: are there threads matching the filter? otherwise every thread is analyzed
        // and when did the recording start: a recording copied over JMX is made of whole chunks of the repository, and a
        // chunk started before the recording holds older events (a previous recording): the start is the recordingStart
        // of the last recording (jdk.ActiveRecording), or the first end of an event. An event is recorded when it ends,
        // its start can be long before (a thread parked for an hour): the durations are clipped to the recording
        Set<String> sampled = new HashSet<>();
        long nbEvents = 0;
        Instant firstEnd = null, recordingStart = null;
        for (Path file : files) {
            try (RecordingFile rf = new RecordingFile(file)) {
                while (rf.hasMoreEvents()) {
                    RecordedEvent e = rf.readEvent();
                    nbEvents++;
                    if (firstEnd == null || e.getEndTime().isBefore(firstEnd)) firstEnd = e.getEndTime();
                    String type = e.getEventType().getName();
                    if (type.equals("jdk.ActiveRecording") && e.hasField("recordingStart")) {
                        Instant rs = e.getInstant("recordingStart");
                        if (recordingStart == null || rs.isAfter(recordingStart)) recordingStart = rs;
                    }
                    if (type.equals("jdk.ExecutionSample") || type.equals("jdk.ThreadCPULoad")) {
                        String name = threadName(e, type.equals("jdk.ExecutionSample") ? "sampledThread" : "eventThread");
                        if (name != null) sampled.add(name);
                    }
                }
            }
        }
        if (recordingStart == null || (firstEnd != null && recordingStart.isBefore(firstEnd))) recordingStart = firstEnd;
        boolean any = sampled.stream().anyMatch(n -> filter.matcher(n).find());
        String selection = any ? "filter" : "all";

        Map<String, ThreadStats> threads = new HashMap<>();
        Map<String, Long> execStacks = new HashMap<>();
        Map<String, Agg> monitors = new HashMap<>();
        Map<String, Agg> parks = new HashMap<>();
        Map<String, Long> allocClasses = new HashMap<>();
        Map<String, Long> allocStacks = new HashMap<>();
        Map<String, Agg> fileIo = new HashMap<>();
        long allocAllThreads = 0;
        Set<Long> allocSeen = new HashSet<>();

        List<Double> pauses = new ArrayList<>();
        Map<String, Integer> gcByName = new HashMap<>();
        double pauseTotal = 0, pauseMax = 0;
        long heapAfterMax = 0, heapAfterSum = 0, heapAfterN = 0;
        Long throwablesFirst = null, throwablesLast = null;
        Instant throwablesFirstTime = null, throwablesLastTime = null;
        double jvmUser = 0, jvmSystem = 0, machine = 0;
        int cpuLoadN = 0;
        Instant start = null, end = null;
        String jvmVersion = null;
        Integer effectiveCpus = null, hwThreads = null;

        for (Path file : files) {
            try (RecordingFile rf = new RecordingFile(file)) {
                while (rf.hasMoreEvents()) {
                    RecordedEvent e = rf.readEvent();
                    String type = e.getEventType().getName();
                    // the description of the JVM is written at the start of each chunk: kept whatever its time
                    boolean metadata = type.equals("jdk.JVMInformation") || type.equals("jdk.CPUInformation")
                        || type.equals("jdk.ContainerConfiguration") || type.equals("jdk.ActiveRecording");
                    if (!metadata && e.getEndTime().isBefore(recordingStart)) continue;
                    if (metadata) {
                        switch (type) {
                            case "jdk.JVMInformation" -> jvmVersion = str(e, "jvmVersion");
                            case "jdk.ContainerConfiguration" -> {
                                if (e.hasField("effectiveCpuCount")) effectiveCpus = (int) e.getLong("effectiveCpuCount");
                            }
                            case "jdk.CPUInformation" -> {
                                if (e.hasField("hwThreads")) hwThreads = e.getInt("hwThreads");
                            }
                            default -> { }
                        }
                        continue;
                    }
                    Instant st = e.getStartTime().isBefore(recordingStart) ? recordingStart : e.getStartTime(), et = e.getEndTime();
                    if (start == null || st.isBefore(start)) start = st;
                    long clippedNs = Duration.between(st, et).toNanos();
                    if (end == null || et.isAfter(end)) end = et;
                    switch (type) {
                        case "jdk.CPULoad" -> {
                            jvmUser += e.getFloat("jvmUser");
                            jvmSystem += e.getFloat("jvmSystem");
                            machine += e.getFloat("machineTotal");
                            cpuLoadN++;
                        }
                        case "jdk.ThreadCPULoad" -> {
                            String name = threadName(e, "eventThread");
                            if (name == null) break;
                            ThreadStats t = threads.computeIfAbsent(name, k -> new ThreadStats());
                            t.cpuUser += e.getFloat("user");
                            t.cpuSystem += e.getFloat("system");
                            t.cpuN++;
                            t.cpuTimes.add(st.toEpochMilli());
                        }
                        case "jdk.ExecutionSample" -> {
                            String name = threadName(e, "sampledThread");
                            if (name == null) break;
                            ThreadStats ts = threads.computeIfAbsent(name, k -> new ThreadStats());
                            ts.execSamples++;
                            RecordedThread rt = e.getValue("sampledThread");
                            if (rt != null) ts.javaIds.add(rt.getJavaThreadId());
                            if (selected(name, filter, any)) execStacks.merge(stackKey(e.getStackTrace(), depth), 1L, Long::sum);
                        }
                        case "jdk.NativeMethodSample" -> {
                            String name = threadName(e, "sampledThread");
                            if (name == null) break;
                            ThreadStats t = threads.computeIfAbsent(name, k -> new ThreadStats());
                            t.nativeSamples++;
                            if (selected(name, filter, any)) t.nativeStacks.merge(stackKey(e.getStackTrace(), depth), 1L, Long::sum);
                        }
                        case "jdk.SocketRead", "jdk.SocketWrite" -> {
                            String name = threadName(e, "eventThread");
                            if (name == null || !selected(name, filter, any)) break;
                            String host = str(e, "host");
                            if (host == null || host.isEmpty()) host = str(e, "address");
                            String remote = host + ":" + (e.hasField("port") ? e.getInt("port") : 0);
                            String op = type.equals("jdk.SocketRead") ? "read" : "write";
                            long bytes = e.hasField("bytesRead") ? e.getLong("bytesRead") : e.hasField("bytesWritten") ? e.getLong("bytesWritten") : 0;
                            long[] v = threads.computeIfAbsent(name, k -> new ThreadStats()).socket.computeIfAbsent(op + " " + remote, k -> new long[3]);
                            v[0]++;
                            v[1] += clippedNs;
                            v[2] += Math.max(bytes, 0);
                        }
                        case "jdk.FileRead", "jdk.FileWrite" -> {
                            String name = threadName(e, "eventThread");
                            if (name == null || !selected(name, filter, any)) break;
                            long ns = clippedNs;
                            threads.computeIfAbsent(name, k -> new ThreadStats()).fileNs += ns;
                            String op = type.equals("jdk.FileRead") ? "read" : "write";
                            String path = str(e, "path");
                            Agg a = fileIo.computeIfAbsent(op + " " + path, k -> new Agg());
                            a.kind = op;
                            a.cls = path;
                            a.count++;
                            a.ns += ns;
                            long bytes = e.hasField("bytesRead") ? e.getLong("bytesRead") : e.hasField("bytesWritten") ? e.getLong("bytesWritten") : 0;
                            a.bytes += Math.max(bytes, 0);
                        }
                        case "jdk.JavaMonitorEnter", "jdk.ThreadPark", "jdk.JavaMonitorWait", "jdk.ThreadSleep" -> {
                            String name = threadName(e, "eventThread");
                            if (name == null || !selected(name, filter, any)) break;
                            long ns = clippedNs;
                            ThreadStats t = threads.computeIfAbsent(name, k -> new ThreadStats());
                            String kind;
                            String cls;
                            switch (type) {
                                case "jdk.JavaMonitorEnter" -> { t.monitorNs += ns; kind = "monitor"; cls = className(e, "monitorClass"); }
                                case "jdk.ThreadPark" -> { t.parkNs += ns; kind = "park"; cls = className(e, "parkedClass"); }
                                case "jdk.JavaMonitorWait" -> { t.waitNs += ns; kind = "wait"; cls = className(e, "monitorClass"); }
                                default -> { t.sleepNs += ns; kind = "sleep"; cls = null; }
                            }
                            String stack = stackKey(e.getStackTrace(), EVENT_DEPTH);
                            Agg a = (kind.equals("monitor") ? monitors : parks).computeIfAbsent(kind + "|" + cls + "|" + stack, k -> new Agg());
                            a.kind = kind;
                            a.cls = cls;
                            a.stack = stack;
                            a.count++;
                            a.ns += ns;
                        }
                        case "jdk.ObjectAllocationSample" -> {
                            // the weight is what the thread allocated since its previous sample: the first sample of a
                            // thread carries everything since the thread started, before the recording (by thread id: a
                            // restarted task has two threads with the same name)
                            String name = threadName(e, "eventThread");
                            RecordedThread at = e.getValue("eventThread");
                            if (name == null || at == null || allocSeen.add(at.getJavaThreadId())) break;
                            long weight = e.getLong("weight");
                            allocAllThreads += weight;
                            if (!selected(name, filter, any)) break;
                            allocClasses.merge(String.valueOf(className(e, "objectClass")), weight, Long::sum);
                            allocStacks.merge(stackKey(e.getStackTrace(), EVENT_DEPTH), weight, Long::sum);
                        }
                        case "jdk.GarbageCollection" -> {
                            double sum = ms(e.getDuration("sumOfPauses"));
                            double longest = ms(e.getDuration("longestPause"));
                            pauses.add(longest);
                            pauseTotal += sum;
                            pauseMax = Math.max(pauseMax, longest);
                            gcByName.merge(String.valueOf(str(e, "name")), 1, Integer::sum);
                        }
                        case "jdk.GCHeapSummary" -> {
                            if ("After GC".equals(str(e, "when"))) {
                                long used = e.getLong("heapUsed");
                                heapAfterMax = Math.max(heapAfterMax, used);
                                heapAfterSum += used;
                                heapAfterN++;
                            }
                        }
                        case "jdk.ExceptionStatistics" -> {
                            long n = e.getLong("throwables");
                            if (throwablesFirst == null || st.isBefore(throwablesFirstTime)) { throwablesFirst = n; throwablesFirstTime = st; }
                            if (throwablesLast == null || st.isAfter(throwablesLastTime)) { throwablesLast = n; throwablesLastTime = st; }
                        }
                        default -> { }
                    }
                }
            }
        }

        StringBuilder out = new StringBuilder(1 << 16);
        out.append("{\"format\":1");
        out.append(",\"files\":[");
        for (int i = 0; i < files.size(); i++) out.append(i > 0 ? "," : "").append(json(files.get(i).getFileName().toString()));
        out.append("]");
        out.append(",\"events\":").append(nbEvents);
        out.append(",\"start\":").append(json(start == null ? null : start.toString()));
        out.append(",\"end\":").append(json(end == null ? null : end.toString()));
        out.append(",\"duration_s\":").append(start == null ? 0 : num(Duration.between(start, end).toNanos() / 1e9));
        out.append(",\"jvm_version\":").append(json(jvmVersion));
        out.append(",\"effective_cpus\":").append(effectiveCpus);
        out.append(",\"hw_threads\":").append(hwThreads);
        // a thread gets a jdk.ThreadCPULoad event only in the rounds where it used cpu: its average load is its sum over
        // the number of rounds of the recording (duration / period), not over its own events. The period is the median
        // gap between the events of the thread that has the most of them
        List<Long> times = threads.values().stream().map(t -> t.cpuTimes).max((a, b) -> Integer.compare(a.size(), b.size())).orElse(List.of());
        int rounds = 0;
        if (times.size() > 1 && start != null) {
            List<Long> sorted = new ArrayList<>(times);
            sorted.sort(Long::compare);
            List<Long> gaps = new ArrayList<>();
            for (int i = 1; i < sorted.size(); i++) gaps.add(sorted.get(i) - sorted.get(i - 1));
            gaps.sort(Long::compare);
            long period = Math.max(1, gaps.get(gaps.size() / 2));
            rounds = (int) Math.max(1, Math.round(Duration.between(start, end).toMillis() / (double) period));
        }
        out.append(",\"cpu_load_rounds\":").append(rounds);
        out.append(",\"thread_filter\":").append(json(threadFilter));
        out.append(",\"thread_selection\":").append(json(selection));

        out.append(",\"threads\":[");
        boolean first = true;
        for (Map.Entry<String, ThreadStats> en : threads.entrySet()) {
            ThreadStats t = en.getValue();
            boolean sel = selected(en.getKey(), filter, any);
            if (!sel && t.execSamples == 0 && t.cpuN == 0) continue;
            out.append(first ? "" : ",");
            first = false;
            out.append("{\"name\":").append(json(en.getKey()));
            out.append(",\"selected\":").append(sel);
            out.append(",\"cpu_user\":").append(t.cpuN > 0 ? num(t.cpuUser / Math.max(rounds, t.cpuN)) : "null");
            out.append(",\"cpu_system\":").append(t.cpuN > 0 ? num(t.cpuSystem / Math.max(rounds, t.cpuN)) : "null");
            out.append(",\"cpu_n\":").append(t.cpuN);
            out.append(",\"exec_samples\":").append(t.execSamples);
            out.append(",\"java_threads\":").append(t.javaIds.size());
            out.append(",\"native_samples\":").append(t.nativeSamples);
            if (sel) {
                out.append(",\"monitor_ms\":").append(num(t.monitorNs / 1e6));
                out.append(",\"park_ms\":").append(num(t.parkNs / 1e6));
                out.append(",\"wait_ms\":").append(num(t.waitNs / 1e6));
                out.append(",\"sleep_ms\":").append(num(t.sleepNs / 1e6));
                out.append(",\"file_ms\":").append(num(t.fileNs / 1e6));
                out.append(",\"socket\":[");
                boolean f2 = true;
                for (Map.Entry<String, long[]> s : t.socket.entrySet()) {
                    String[] kv = s.getKey().split(" ", 2);
                    out.append(f2 ? "" : ",");
                    f2 = false;
                    out.append("{\"op\":").append(json(kv[0])).append(",\"remote\":").append(json(kv[1]))
                       .append(",\"count\":").append(s.getValue()[0]).append(",\"ms\":").append(num(s.getValue()[1] / 1e6))
                       .append(",\"bytes\":").append(s.getValue()[2]).append("}");
                }
                out.append("],\"native_stacks\":");
                appendCounts(out, t.nativeStacks);
            }
            out.append("}");
        }
        out.append("]");

        out.append(",\"exec_stacks\":");
        appendCounts(out, execStacks);
        out.append(",\"monitor\":");
        appendAggs(out, monitors);
        out.append(",\"park\":");
        appendAggs(out, parks);
        out.append(",\"alloc_classes\":{");
        first = true;
        for (Map.Entry<String, Long> en : allocClasses.entrySet()) {
            out.append(first ? "" : ",").append(json(en.getKey())).append(":").append(en.getValue());
            first = false;
        }
        out.append("},\"alloc_stacks\":");
        appendCounts(out, allocStacks);
        out.append(",\"alloc_all_threads_bytes\":").append(allocAllThreads);
        out.append(",\"file_io\":[");
        first = true;
        for (Agg a : fileIo.values()) {
            out.append(first ? "" : ",");
            first = false;
            out.append("{\"op\":").append(json(a.kind)).append(",\"path\":").append(json(a.cls)).append(",\"count\":").append(a.count)
               .append(",\"ms\":").append(num(a.ns / 1e6)).append(",\"bytes\":").append(a.bytes).append("}");
        }
        out.append("]");

        pauses.sort(Double::compare);
        out.append(",\"gc\":{\"count\":").append(pauses.size());
        out.append(",\"pause_total_ms\":").append(num(pauseTotal));
        out.append(",\"pause_max_ms\":").append(num(pauseMax));
        out.append(",\"pause_p99_ms\":").append(pauses.isEmpty() ? "null" : num(pauses.get((int) Math.floor((pauses.size() - 1) * 0.99))));
        out.append(",\"by_name\":{");
        first = true;
        for (Map.Entry<String, Integer> en : gcByName.entrySet()) {
            out.append(first ? "" : ",").append(json(en.getKey())).append(":").append(en.getValue());
            first = false;
        }
        out.append("},\"heap_after_gc_max_bytes\":").append(heapAfterN > 0 ? heapAfterMax : "null");
        out.append(",\"heap_after_gc_avg_bytes\":").append(heapAfterN > 0 ? heapAfterSum / heapAfterN : "null");
        out.append("}");
        out.append(",\"exceptions\":{\"throwables\":")
           .append(throwablesFirst != null && throwablesLast != null ? throwablesLast - throwablesFirst : "null")
           .append(",\"seconds\":")
           .append(throwablesFirstTime != null ? num(Duration.between(throwablesFirstTime, throwablesLastTime).toNanos() / 1e9) : "null")
           .append("}");
        out.append(",\"cpu\":{\"jvm_user\":").append(cpuLoadN > 0 ? num(jvmUser / cpuLoadN) : "null")
           .append(",\"jvm_system\":").append(cpuLoadN > 0 ? num(jvmSystem / cpuLoadN) : "null")
           .append(",\"machine_total\":").append(cpuLoadN > 0 ? num(machine / cpuLoadN) : "null").append("}");

        out.append(",\"frames\":[");
        for (int i = 0; i < frames.size(); i++) out.append(i > 0 ? "," : "").append(json(frames.get(i)));
        out.append("]}");
        System.out.println(out);
    }

    static boolean selected(String name, Pattern filter, boolean any) {
        return !any || filter.matcher(name).find();
    }

    static String threadName(RecordedEvent e, String field) {
        if (!e.hasField(field)) return null;
        RecordedThread t = e.getValue(field);
        if (t == null) return null;
        String name = t.getJavaName();
        return name != null ? name : t.getOSName();
    }

    static String className(RecordedEvent e, String field) {
        if (!e.hasField(field)) return null;
        RecordedClass c = e.getValue(field);
        return c == null ? null : c.getName();
    }

    static String str(RecordedObject e, String field) {
        if (!e.hasField(field)) return null;
        Object v = e.getValue(field);
        return v == null ? null : v.toString();
    }

    static double ms(Duration d) {
        return d == null ? 0 : d.toNanos() / 1e6;
    }

    static String stackKey(RecordedStackTrace st, int max) {
        if (st == null) return "";
        StringBuilder sb = new StringBuilder();
        int n = 0;
        for (RecordedFrame f : st.getFrames()) {
            if (n >= max) break;
            if (f.getMethod() == null) continue;
            String frame = f.getMethod().getType().getName() + "." + f.getMethod().getName();
            Integer id = frameIds.get(frame);
            if (id == null) {
                id = frames.size();
                frames.add(frame);
                frameIds.put(frame, id);
            }
            sb.append(n > 0 ? "," : "").append(id);
            n++;
        }
        return sb.toString();
    }

    // [[count, [frame ids]], ...]
    static void appendCounts(StringBuilder out, Map<String, Long> counts) {
        out.append("[");
        boolean first = true;
        for (Map.Entry<String, Long> en : counts.entrySet()) {
            out.append(first ? "" : ",").append("[").append(en.getValue()).append(",[").append(en.getKey()).append("]]");
            first = false;
        }
        out.append("]");
    }

    static void appendAggs(StringBuilder out, Map<String, Agg> aggs) {
        out.append("[");
        boolean first = true;
        for (Agg a : aggs.values()) {
            out.append(first ? "" : ",");
            first = false;
            out.append("{\"kind\":").append(json(a.kind)).append(",\"class\":").append(json(a.cls)).append(",\"count\":").append(a.count)
               .append(",\"ms\":").append(num(a.ns / 1e6)).append(",\"stack\":[").append(a.stack).append("]}");
        }
        out.append("]");
    }

    static String num(double v) {
        if (Double.isNaN(v) || Double.isInfinite(v)) return "null";
        return String.format(java.util.Locale.ROOT, "%.4f", v);
    }

    static String json(String s) {
        if (s == null) return "null";
        StringBuilder sb = new StringBuilder(s.length() + 2).append('"');
        for (char c : s.toCharArray()) {
            switch (c) {
                case '"' -> sb.append("\\\"");
                case '\\' -> sb.append("\\\\");
                case '\n' -> sb.append("\\n");
                case '\r' -> sb.append("\\r");
                case '\t' -> sb.append("\\t");
                default -> {
                    if (c < 0x20) sb.append(String.format("\\u%04x", (int) c));
                    else sb.append(c);
                }
            }
        }
        return sb.append('"').toString();
    }
}
