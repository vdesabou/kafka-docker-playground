package jscissors;

import java.util.EnumSet;

/**
 * Called by the advice inlined in the traced methods. Each thread keeps the stack of its traced calls: the parent of a
 * call is the traced call it runs in, so events.jsonl holds a call tree. While the tracer works for a thread (toString
 * of an argument, a dump), the calls of that thread are not traced: no recursion, no noise.
 */
public final class Tracer {
    static volatile Session session;

    private static final ThreadLocal<ThreadState> STATE = new ThreadLocal<ThreadState>() {
        @Override
        protected ThreadState initialValue() {
            return new ThreadState();
        }
    };

    static final class ThreadState {
        boolean busy;
        long generation;
        int depth;
        long[] ids = new long[32];
        long[] starts = new long[32];
        boolean[] emitted = new boolean[32];
        MethodStats[] stats = new MethodStats[32];
        // with onlyFailed / slowerThanMs: the enter event of the call, written only if the call throws or is slow
        String[] pending = new String[32];

        void push(long id, long start, boolean emit, MethodStats ms, String enter) {
            if (depth == ids.length) {
                int n = depth * 2;
                ids = java.util.Arrays.copyOf(ids, n);
                starts = java.util.Arrays.copyOf(starts, n);
                emitted = java.util.Arrays.copyOf(emitted, n);
                stats = java.util.Arrays.copyOf(stats, n);
                pending = java.util.Arrays.copyOf(pending, n);
            }
            ids[depth] = id;
            starts[depth] = start;
            emitted[depth] = emit;
            stats[depth] = ms;
            pending[depth] = enter;
            depth++;
        }

        int find(long id) {
            for (int i = depth - 1; i >= 0; i--) {
                if (ids[i] == id) {
                    return i;
                }
            }
            return -1;
        }
    }

    private Tracer() {
    }

    /** returns the id of the call, 0 when it is not traced */
    public static long enter(int rule, String origin, Object[] args) {
        Session s = session;
        if (s == null) {
            return 0;
        }
        ThreadState st = STATE.get();
        if (st.busy) {
            return 0;
        }
        st.busy = true;
        try {
            if (st.generation != s.generation) {
                // calls left open by a previous session
                st.generation = s.generation;
                st.depth = 0;
            }
            long now = System.nanoTime();
            MethodStats ms = s.stats(origin);
            long id = s.nextId();
            // filtered: the enter is built now (the arguments as they are when the method is called), and written by
            // exit only if the call throws or is slow
            boolean filtered = s.filtered && s.hasBudget(ms);
            boolean emit = !s.filtered && s.admit(ms);
            long parent = st.depth > 0 ? st.ids[st.depth - 1] : 0;
            int depth = st.depth;
            EnumSet<Op> ops = s.ops(rule);
            String enter = null;
            if (emit || filtered) {
                StringBuilder sb = s.event("enter", id, now);
                Json.field(sb, "parent", parent);
                Json.field(sb, "depth", depth);
                Json.field(sb, "class", ms.className);
                Json.field(sb, "method", ms.method);
                Json.field(sb, "sig", ms.signature);
                if (args != null && ops.contains(Op.VALUES)) {
                    sb.append(",\"args\":[");
                    for (int i = 0; i < args.length; i++) {
                        Json.str(i > 0 ? sb.append(',') : sb, Values.of(args[i], s.maxValueLength));
                    }
                    sb.append(']');
                }
                if (ops.contains(Op.STACK)) {
                    stack(sb.append(",\"stack\":"), new Throwable().getStackTrace(), s.maxStackDepth);
                }
                sb.append('}');
                if (emit) {
                    s.emit(sb);
                } else {
                    enter = sb.toString();
                }
            }
            st.push(id, now, emit, ms, enter);
            if (ops.contains(Op.THREADS)) {
                s.dumps.threads(id, "enter", ms.origin);
            }
            if (ops.contains(Op.HEAP)) {
                s.dumps.heap(id, "enter", ms.origin);
            }
            return id;
        } catch (Throwable t) {
            s.error("tracing the call of " + origin, t);
            return 0;
        } finally {
            st.busy = false;
        }
    }

    public static void exit(int rule, long id, String returnType, Object returned, Throwable thrown) {
        if (id == 0) {
            return;
        }
        Session s = session;
        if (s == null) {
            return;
        }
        ThreadState st = STATE.get();
        if (st.busy || st.generation != s.generation) {
            return;
        }
        st.busy = true;
        try {
            int i = st.find(id);
            if (i < 0) {
                return;
            }
            long now = System.nanoTime();
            long nanos = now - st.starts[i];
            boolean emit = st.emitted[i];
            MethodStats ms = st.stats[i];
            String pending = st.pending[i];
            st.pending[i] = null;
            if (pending != null && (s.onlyFailed && thrown != null || s.slowerThanNanos > 0 && nanos >= s.slowerThanNanos) && s.admit(ms)) {
                s.emitLine(pending);
                emit = true;
            }
            // pops the call, and the calls above it left open (should not happen)
            st.depth = i;
            boolean firstOfItsKind = ms.record(nanos, thrown);
            EnumSet<Op> ops = s.ops(rule);
            if (emit || (thrown != null && firstOfItsKind)) {
                StringBuilder sb = s.event("exit", id, now);
                Json.field(sb, "dur_us", nanos / 1000);
                if (!emit) {
                    // the enter of this call was past the limits: the exit carries what the report needs
                    Json.field(sb, "class", ms.className);
                    Json.field(sb, "method", ms.method);
                    Json.field(sb, "sig", ms.signature);
                }
                if (thrown != null) {
                    Json.field(sb, "exc", thrown.getClass().getName());
                    Json.field(sb, "exc_msg", thrown.getMessage() == null ? "" : Values.of(thrown.getMessage(), s.maxValueLength * 2).replaceAll("^\"|\"$", ""));
                    if (firstOfItsKind) {
                        stack(sb.append(",\"exc_stack\":"), thrown.getStackTrace(), s.maxStackDepth);
                        Throwable cause = thrown.getCause();
                        if (cause != null && cause != thrown) {
                            Json.field(sb, "exc_cause", cause.getClass().getName() + ": " + Values.of(cause.getMessage(), s.maxValueLength).replaceAll("^\"|\"$", ""));
                        }
                    }
                } else if (ops.contains(Op.RETURN_VALUE)) {
                    if ("void".equals(returnType)) {
                        sb.append(",\"void\":true");
                    } else {
                        Json.field(sb, "ret", Values.of(returned, s.maxValueLength));
                    }
                }
                s.emit(sb.append('}'));
            }
            if (thrown != null) {
                if (ops.contains(Op.EXCEPTION_THREADS)) {
                    s.dumps.threads(id, "exception", ms.origin);
                }
                if (ops.contains(Op.EXCEPTION_HEAP)) {
                    s.dumps.heap(id, "exception", ms.origin);
                }
            } else {
                if (ops.contains(Op.RETURN_THREADS)) {
                    s.dumps.threads(id, "exit", ms.origin);
                }
                if (ops.contains(Op.RETURN_HEAP)) {
                    s.dumps.heap(id, "exit", ms.origin);
                }
            }
        } catch (Throwable t) {
            s.error("tracing the exit of call " + id, t);
        } finally {
            st.busy = false;
        }
    }

    /** frames of the stack, without the ones of the agent */
    private static void stack(StringBuilder sb, StackTraceElement[] frames, int max) {
        sb.append('[');
        int n = 0;
        for (StackTraceElement frame : frames) {
            if (n == 0 && frame.getClassName().startsWith("jscissors.")) {
                continue;
            }
            if (n == max) {
                Json.str(sb.append(','), "… " + (frames.length - n) + " more");
                break;
            }
            Json.str(n > 0 ? sb.append(',') : sb, frame.toString());
            n++;
        }
        sb.append(']');
    }
}
