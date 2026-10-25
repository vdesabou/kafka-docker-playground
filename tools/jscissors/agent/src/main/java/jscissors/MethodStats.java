package jscissors;

import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.AtomicLong;
import java.util.concurrent.atomic.LongAccumulator;

/** Statistics of one traced method: exact, even when its calls are past the limits of events.jsonl. */
final class MethodStats {
    final String origin;
    final String className;
    final String method;
    final String signature;
    final AtomicLong calls = new AtomicLong();
    final AtomicLong errors = new AtomicLong();
    final AtomicLong totalNanos = new AtomicLong();
    final LongAccumulator maxNanos = new LongAccumulator(Math::max, 0);
    final AtomicInteger emitted = new AtomicInteger();
    // exception class -> count
    final Map<String, AtomicLong> exceptions = new ConcurrentHashMap<>();

    MethodStats(String origin) {
        this.origin = origin;
        // origin is "<class>.<method>(<parameter types>)"
        int paren = origin.indexOf('(');
        int dot = origin.lastIndexOf('.', paren < 0 ? origin.length() : paren);
        this.className = dot < 0 ? "" : origin.substring(0, dot);
        this.method = origin.substring(dot + 1, paren < 0 ? origin.length() : paren);
        this.signature = paren < 0 ? "" : origin.substring(paren);
    }

    /** true the first time this method throws this exception class: its stack trace is recorded once */
    boolean record(long nanos, Throwable thrown) {
        calls.incrementAndGet();
        totalNanos.addAndGet(nanos);
        maxNanos.accumulate(nanos);
        if (thrown == null) {
            return false;
        }
        errors.incrementAndGet();
        AtomicLong count = exceptions.get(thrown.getClass().getName());
        if (count == null) {
            count = exceptions.computeIfAbsent(thrown.getClass().getName(), k -> new AtomicLong());
        }
        return count.incrementAndGet() == 1;
    }
}
