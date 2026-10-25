package jscissors;

import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.OutputStreamWriter;
import java.io.PrintWriter;
import java.io.StringWriter;
import java.io.Writer;
import java.lang.instrument.Instrumentation;
import java.lang.management.ManagementFactory;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.StandardCopyOption;
import java.text.SimpleDateFormat;
import java.util.ArrayList;
import java.util.Collections;
import java.util.Date;
import java.util.EnumSet;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.WeakHashMap;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.atomic.AtomicLong;

import net.bytebuddy.ByteBuddy;
import net.bytebuddy.agent.builder.AgentBuilder;
import net.bytebuddy.agent.builder.ResettableClassFileTransformer;
import net.bytebuddy.asm.Advice;
import net.bytebuddy.description.method.MethodDescription;
import net.bytebuddy.description.type.TypeDescription;
import net.bytebuddy.dynamic.DynamicType;
import net.bytebuddy.dynamic.scaffold.TypeValidation;
import net.bytebuddy.matcher.ElementMatcher;
import net.bytebuddy.utility.JavaModule;

import static net.bytebuddy.matcher.ElementMatchers.any;
import static net.bytebuddy.matcher.ElementMatchers.isBootstrapClassLoader;
import static net.bytebuddy.matcher.ElementMatchers.isSynthetic;
import static net.bytebuddy.matcher.ElementMatchers.nameContains;
import static net.bytebuddy.matcher.ElementMatchers.nameStartsWith;

/**
 * One tracing session, from --action start (or the start of the JVM) to --action stop: the transformer installed for
 * the rules, the files of the session and its statistics. Stopping it restores the original classes.
 *
 * Files, in &lt;out&gt;/pid-&lt;pid&gt;/: events.jsonl (one json event per line), summary.json (statistics, refreshed
 * every 5 s), agent.log, instrumented.txt (classes transformed) and dumps/.
 */
final class Session {
    private static final AtomicLong GENERATIONS = new AtomicLong();

    final long generation = GENERATIONS.incrementAndGet();
    final Config config;
    final File dir;
    final int maxValueLength;
    final int maxStackDepth;
    final Dumps dumps;
    private final Instrumentation inst;
    private final String mode;
    private final long startMillis = System.currentTimeMillis();
    private final long startNanos = System.nanoTime();
    private final long maxCalls;
    private final long maxCallsPerMethod;
    // only the calls that throw (onlyFailed) or take longer than slowerThanMs are written with their details
    final boolean onlyFailed;
    final long slowerThanNanos;
    final boolean filtered;
    private final AtomicLong ids = new AtomicLong();
    private final AtomicLong emittedCalls = new AtomicLong();
    private final AtomicLong cappedCalls = new AtomicLong();
    private final Map<String, MethodStats> stats = new ConcurrentHashMap<>();
    private final Set<String> instrumented = ConcurrentHashMap.newKeySet();
    private final Set<String> notVisible = ConcurrentHashMap.newKeySet();
    private final List<String> errors = Collections.synchronizedList(new ArrayList<String>());
    private final AtomicLong errorCount = new AtomicLong();
    private final Map<ClassLoader, Boolean> agentVisible = new WeakHashMap<>();
    // rules merged per method: the index is bound in the advice of the method (@RuleIndex)
    private final Map<String, Integer> mergedIndex = new LinkedHashMap<>();
    private volatile EnumSet<Op>[] mergedOps = newOps(0);
    private final List<String> mergedRules = new ArrayList<>();
    private volatile long limitReachedAt;
    private volatile String stopped;
    private final Object logLock = new Object();
    private Writer agentLog;
    private EventWriter writer;
    private ResettableClassFileTransformer transformer;
    private Thread shutdownHook;

    Session(Config config, File out, Instrumentation inst, String mode) {
        this.config = config;
        this.inst = inst;
        this.mode = mode;
        this.dir = new File(out, "pid-" + pid());
        this.maxValueLength = (int) config.get("maxValueLength");
        this.maxStackDepth = (int) config.get("maxStackDepth");
        this.maxCalls = config.get("maxCalls");
        this.maxCallsPerMethod = config.get("maxCallsPerMethod");
        this.onlyFailed = config.get("onlyFailed") != 0;
        this.slowerThanNanos = config.get("slowerThanMs") * 1000000L;
        this.filtered = onlyFailed || slowerThanNanos > 0;
        this.dumps = new Dumps(this, new File(dir, "dumps"));
    }

    @SuppressWarnings("unchecked")
    private static EnumSet<Op>[] newOps(int n) {
        return new EnumSet[n];
    }

    void start() throws IOException {
        if (!dir.isDirectory() && !dir.mkdirs()) {
            throw new IOException("cannot create " + dir);
        }
        agentLog = new OutputStreamWriter(new FileOutputStream(new File(dir, "agent.log"), true), StandardCharsets.UTF_8);
        log("jscissors " + Agent.VERSION + " " + mode + " in pid " + pid() + " (" + System.getProperty("java.vm.name") + " " + System.getProperty("java.version") + ")");
        for (String warning : config.warnings) {
            log("WARN " + warning);
        }
        for (Config.Rule rule : config.rules) {
            log("rule " + rule.line);
        }
        writer = new EventWriter(this, new File(dir, "events.jsonl"));
        writeSummary(false);
        Tracer.session = this;
        long t0 = System.currentTimeMillis();
        transformer = new AgentBuilder.Default(new ByteBuddy().with(TypeValidation.DISABLED))
                .disableClassFormatChanges()
                .with(AgentBuilder.RedefinitionStrategy.RETRANSFORMATION)
                .with(new AgentBuilder.RedefinitionStrategy.Listener.Adapter() {
                    @Override
                    public Iterable<? extends List<Class<?>>> onError(int index, List<Class<?>> batch, Throwable throwable, List<Class<?>> types) {
                        error("retransforming " + batch, throwable);
                        return Collections.emptyList();
                    }
                })
                .with(AgentBuilder.InitializationStrategy.NoOp.INSTANCE)
                .with(AgentBuilder.TypeStrategy.Default.REDEFINE)
                .with(new AgentBuilder.Listener.Adapter() {
                    @Override
                    public void onTransformation(TypeDescription type, ClassLoader loader, JavaModule module, boolean loaded, DynamicType dynamicType) {
                        if (instrumented.add(type.getName())) {
                            log("instrumented " + type.getName());
                        }
                    }

                    @Override
                    public void onError(String typeName, ClassLoader loader, JavaModule module, boolean loaded, Throwable throwable) {
                        error("instrumenting " + typeName, throwable);
                    }
                })
                // the classes of the JDK (bootstrap class loader) cannot see the agent
                .ignore(any(), isBootstrapClassLoader())
                .or(nameStartsWith("jscissors."))
                .or(nameStartsWith("net.bytebuddy."))
                .or(nameContains("$$Lambda"))
                .or(nameContains("$ByteBuddy$"))
                .or(isSynthetic())
                .type(this::matchesType)
                .transform(this::transform)
                .installOn(inst);
        shutdownHook = new Thread(() -> stop("JVM exit"), "jscissors-shutdown");
        Runtime.getRuntime().addShutdownHook(shutdownHook);
        log("transformer installed in " + (System.currentTimeMillis() - t0) + " ms, " + instrumented.size() + " class(es) instrumented so far");
        writeSummary(false);
    }

    private boolean matchesType(TypeDescription type, ClassLoader loader, JavaModule module, Class<?> redefined, java.security.ProtectionDomain pd) {
        String name = type.getName();
        boolean matched = false;
        for (Config.Rule rule : config.rules) {
            if (rule.matchesClass(name)) {
                matched = true;
                break;
            }
        }
        if (!matched || type.isInterface() || type.isAnnotation()) {
            return false;
        }
        if (!canSeeAgent(loader)) {
            if (notVisible.add(name)) {
                log("WARN " + name + " matches a rule but its class loader cannot see the agent: not instrumented");
            }
            return false;
        }
        return true;
    }

    private DynamicType.Builder<?> transform(DynamicType.Builder<?> builder, TypeDescription type, ClassLoader loader, JavaModule module, java.security.ProtectionDomain pd) {
        List<Config.Rule> rules = new ArrayList<>();
        List<Integer> indexes = new ArrayList<>();
        for (int i = 0; i < config.rules.size(); i++) {
            if (config.rules.get(i).matchesClass(type.getName())) {
                rules.add(config.rules.get(i));
                indexes.add(i);
            }
        }
        // methods grouped by the set of rules matching them: one advice per method, with the union of the operations
        Map<Integer, Set<String>> methodsByRule = new LinkedHashMap<>();
        for (MethodDescription.InDefinedShape m : type.getDeclaredMethods()) {
            if (!m.isMethod() || m.isAbstract() || m.isNative() || m.isSynthetic() || m.isBridge()) {
                continue;
            }
            StringBuilder key = new StringBuilder();
            EnumSet<Op> ops = EnumSet.noneOf(Op.class);
            for (int i = 0; i < rules.size(); i++) {
                if (rules.get(i).matchesMethod(m.getName())) {
                    key.append(indexes.get(i)).append(',');
                    ops.addAll(rules.get(i).ops);
                }
            }
            if (key.length() == 0) {
                continue;
            }
            int index = merged(key.toString(), ops);
            Set<String> methods = methodsByRule.get(index);
            if (methods == null) {
                methods = new HashSet<>();
                methodsByRule.put(index, methods);
            }
            methods.add(m.getInternalName() + m.getDescriptor());
        }
        for (Map.Entry<Integer, Set<String>> entry : methodsByRule.entrySet()) {
            final Set<String> methods = entry.getValue();
            ElementMatcher<MethodDescription> matcher = m -> methods.contains(m.getInternalName() + m.getDescriptor());
            Class<?> advice = ops(entry.getKey()).contains(Op.VALUES) ? TraceAdvice.class : TraceAdviceNoArgs.class;
            builder = builder.visit(Advice.withCustomMapping().bind(RuleIndex.class, entry.getKey()).to(advice).on(matcher));
        }
        return builder;
    }

    private synchronized int merged(String key, EnumSet<Op> ops) {
        Integer index = mergedIndex.get(key);
        if (index == null) {
            index = mergedIndex.size();
            mergedIndex.put(key, index);
            mergedRules.add(key);
            EnumSet<Op>[] copy = newOps(index + 1);
            System.arraycopy(mergedOps, 0, copy, 0, index);
            copy[index] = ops;
            mergedOps = copy;
        }
        return index;
    }

    private boolean canSeeAgent(ClassLoader loader) {
        if (loader == null) {
            return false;
        }
        synchronized (agentVisible) {
            Boolean visible = agentVisible.get(loader);
            if (visible == null) {
                try {
                    visible = Class.forName(Tracer.class.getName(), false, loader) == Tracer.class;
                } catch (Throwable t) {
                    visible = false;
                }
                agentVisible.put(loader, visible);
            }
            return visible;
        }
    }

    EnumSet<Op> ops(int rule) {
        EnumSet<Op>[] ops = mergedOps;
        return rule < ops.length ? ops[rule] : EnumSet.noneOf(Op.class);
    }

    MethodStats stats(String origin) {
        MethodStats ms = stats.get(origin);
        if (ms == null) {
            ms = stats.computeIfAbsent(origin, MethodStats::new);
        }
        return ms;
    }

    long nextId() {
        return ids.incrementAndGet();
    }

    /** whether the call goes to events.jsonl (it is counted in the statistics anyway) */
    boolean admit(MethodStats ms) {
        if (ms.emitted.get() >= maxCallsPerMethod) {
            cappedCalls.incrementAndGet();
            return false;
        }
        if (emittedCalls.incrementAndGet() > maxCalls) {
            if (limitReachedAt == 0) {
                limitReachedAt = System.currentTimeMillis();
                log("WARN maxCalls (" + maxCalls + ") reached: the next calls are only counted in summary.json");
            }
            return false;
        }
        ms.emitted.incrementAndGet();
        return true;
    }

    /** whether a call could still be written: checked on enter by the filtered mode, without using the budget */
    boolean hasBudget(MethodStats ms) {
        return ms.emitted.get() < maxCallsPerMethod && emittedCalls.get() < maxCalls;
    }

    void emitLine(String line) {
        EventWriter w = writer;
        if (w != null) {
            w.offer(line);
        }
    }

    StringBuilder event(String type, long id, long nanos) {
        StringBuilder sb = new StringBuilder(256).append("{\"ev\":\"").append(type).append('"');
        Json.field(sb, "id", id);
        Json.field(sb, "ts", startMillis + (nanos - startNanos) / 1000000);
        Json.field(sb, "us", (nanos - startNanos) / 1000);
        Json.field(sb, "thread", Thread.currentThread().getName());
        return sb;
    }

    void emit(StringBuilder event) {
        EventWriter w = writer;
        if (w != null) {
            w.offer(event.toString());
        }
    }

    void error(String what, Throwable t) {
        long n = errorCount.incrementAndGet();
        if (n <= 50) {
            String message = what + ": " + t;
            errors.add(message);
            StringWriter sw = new StringWriter();
            t.printStackTrace(new PrintWriter(sw));
            log("ERROR " + message + "\n" + sw);
        }
    }

    // its own lock: logged while holding the lock of the dumps, which writeSummary takes holding the session one
    void log(String message) {
        synchronized (logLock) {
            try {
                if (agentLog != null) {
                    agentLog.write(new SimpleDateFormat("yyyy-MM-dd HH:mm:ss.SSS").format(new Date()) + " " + message + "\n");
                    agentLog.flush();
                }
            } catch (IOException ignored) {
                // nothing to do
            }
        }
    }

    /** stops recording, restores the original classes, writes the final summary.json */
    void stop(String reason) {
        synchronized (this) {
            if (stopped != null) {
                return;
            }
            stopped = reason;
        }
        Tracer.session = null;
        if (shutdownHook != null && !"JVM exit".equals(reason)) {
            try {
                Runtime.getRuntime().removeShutdownHook(shutdownHook);
            } catch (IllegalStateException ignored) {
                // the JVM is exiting
            }
        }
        // when the JVM exits, the classes do not need to be restored
        if (transformer != null && !"JVM exit".equals(reason)) {
            long t0 = System.currentTimeMillis();
            try {
                transformer.reset(inst, AgentBuilder.RedefinitionStrategy.RETRANSFORMATION);
                log("original classes restored in " + (System.currentTimeMillis() - t0) + " ms");
            } catch (Throwable t) {
                error("restoring the original classes", t);
            }
        }
        if (writer != null) {
            writer.close();
        }
        writeSummary(true);
        log("stopped: " + reason);
        synchronized (logLock) {
            try {
                agentLog.close();
            } catch (IOException ignored) {
                // nothing to do
            }
            agentLog = null;
        }
    }

    synchronized void writeSummary(boolean last) {
        try {
            StringBuilder sb = new StringBuilder("{\"version\":");
            Json.str(sb, Agent.VERSION);
            Json.field(sb, "pid", pid());
            Json.field(sb, "mode", mode);
            Json.field(sb, "main", mainClass());
            Json.field(sb, "jvm", System.getProperty("java.vm.name") + " " + System.getProperty("java.version"));
            Json.field(sb, "started", startMillis);
            Json.field(sb, "updated", System.currentTimeMillis());
            if (stopped != null) {
                Json.field(sb, "stopped", System.currentTimeMillis());
                Json.field(sb, "stop_reason", stopped);
            }
            sb.append(",\"rules\":[");
            for (int i = 0; i < config.rules.size(); i++) {
                Json.str(i > 0 ? sb.append(',') : sb, config.rules.get(i).line);
            }
            sb.append("],\"settings\":{");
            int i = 0;
            for (Map.Entry<String, Long> setting : config.settings.entrySet()) {
                Json.str(i++ > 0 ? sb.append(',') : sb, setting.getKey()).append(':').append(setting.getValue());
            }
            sb.append('}');
            strings(sb, "warnings", config.warnings);
            strings(sb, "instrumented", new ArrayList<>(instrumented));
            strings(sb, "not_visible", new ArrayList<>(notVisible));
            strings(sb, "errors", new ArrayList<>(errors));
            Json.field(sb, "error_count", errorCount.get());
            Json.field(sb, "calls", ids.get());
            Json.field(sb, "calls_recorded", Math.min(emittedCalls.get(), maxCalls));
            Json.field(sb, "calls_capped_per_method", cappedCalls.get());
            Json.field(sb, "limit_reached_at", limitReachedAt);
            Json.field(sb, "events_written", writer == null ? 0 : writer.written.get());
            Json.field(sb, "events_dropped", writer == null ? 0 : writer.dropped.get());
            synchronized (dumps) {
                strings(sb, "dumps", new ArrayList<>(dumps.files));
                Json.field(sb, "dumps_skipped", dumps.skipped);
            }
            sb.append(",\"methods\":[");
            i = 0;
            for (MethodStats ms : stats.values()) {
                sb.append(i++ > 0 ? ",{" : "{");
                Json.str(sb, "class").append(':');
                Json.str(sb, ms.className);
                Json.field(sb, "method", ms.method);
                Json.field(sb, "sig", ms.signature);
                Json.field(sb, "calls", ms.calls.get());
                Json.field(sb, "errors", ms.errors.get());
                Json.field(sb, "total_us", ms.totalNanos.get() / 1000);
                Json.field(sb, "max_us", ms.maxNanos.get() / 1000);
                sb.append(",\"exceptions\":{");
                int j = 0;
                for (Map.Entry<String, AtomicLong> e : ms.exceptions.entrySet()) {
                    Json.str(j++ > 0 ? sb.append(',') : sb, e.getKey()).append(':').append(e.getValue().get());
                }
                sb.append("}}");
            }
            sb.append("]}\n");
            File tmp = new File(dir, "summary.json.tmp");
            Files.write(tmp.toPath(), sb.toString().getBytes(StandardCharsets.UTF_8));
            Files.move(tmp.toPath(), new File(dir, "summary.json").toPath(), StandardCopyOption.REPLACE_EXISTING, StandardCopyOption.ATOMIC_MOVE);
            if (last) {
                List<String> names = new ArrayList<>(instrumented);
                Collections.sort(names);
                Files.write(new File(dir, "instrumented.txt").toPath(), names, StandardCharsets.UTF_8);
            }
        } catch (Throwable t) {
            if (errorCount.get() < 50) {
                error("writing summary.json", t);
            }
        }
    }

    private static void strings(StringBuilder sb, String key, List<String> values) {
        Json.str(sb.append(','), key).append(":[");
        for (int i = 0; i < values.size(); i++) {
            Json.str(i > 0 ? sb.append(',') : sb, values.get(i));
        }
        sb.append(']');
    }

    static long pid() {
        try {
            return Long.parseLong(ManagementFactory.getRuntimeMXBean().getName().split("@")[0]);
        } catch (RuntimeException e) {
            return 0;
        }
    }

    private static String mainClass() {
        String command = System.getProperty("sun.java.command", "");
        String[] parts = command.trim().split("\\s+");
        return parts.length == 0 ? "" : parts[0];
    }
}
