package jscissors;

import java.io.File;
import java.lang.instrument.Instrumentation;
import java.util.HashMap;
import java.util.Map;

/**
 * Entry point of the agent, at the start of the JVM (-javaagent:jscissors.jar=&lt;args&gt;) or attached to a running
 * JVM (jscissors.Attach). Arguments, comma separated:
 *
 * <pre>
 * config=&lt;rules file&gt;   rules and settings (see Config)
 * out=&lt;folder&gt;          where the session writes its files, in pid-&lt;pid&gt;/ (default /tmp/jscissors/out)
 * action=start|stop       stop: restores the original classes and writes the final summary (attach only)
 * </pre>
 *
 * Attaching again with action=start replaces the running session: the rules can change without a restart.
 */
public final class Agent {
    public static final String VERSION = "2.0";
    private static Session session;

    private Agent() {
    }

    public static void premain(String args, Instrumentation inst) {
        run(args, inst, "started with the JVM");
    }

    public static void agentmain(String args, Instrumentation inst) {
        run(args, inst, "attached");
    }

    private static synchronized void run(String agentArgs, Instrumentation inst, String mode) {
        try {
            // byte-buddy reads the class files of a JDK more recent than the ones it knows
            if (System.getProperty("net.bytebuddy.experimental") == null) {
                System.setProperty("net.bytebuddy.experimental", "true");
            }
            // no sun.misc.Unsafe (warnings of JDK 24+): the advice is inlined, no class is injected
            if (System.getProperty("net.bytebuddy.safe") == null) {
                System.setProperty("net.bytebuddy.safe", "true");
            }
            Map<String, String> args = parse(agentArgs);
            String action = args.getOrDefault("action", "start");
            if (session != null) {
                session.stop("start".equals(action) ? "replaced by a new session" : "stopped");
                System.err.println("[jscissors] session stopped, original classes restored, files in " + session.dir);
                session = null;
            } else if ("stop".equals(action)) {
                System.err.println("[jscissors] no session to stop");
            }
            if (!"start".equals(action)) {
                return;
            }
            String config = args.containsKey("config") ? args.get("config") : args.get("configfile");
            if (config == null) {
                throw new IllegalArgumentException("missing config=<rules file>");
            }
            String out = args.containsKey("out") ? args.get("out") : args.getOrDefault("tracedir", "/tmp/jscissors/out");
            Session s = new Session(Config.load(new File(config)), new File(out), inst, mode);
            s.start();
            session = s;
            System.err.println("[jscissors] tracing " + s.config.rules.size() + " rule(s), files in " + s.dir);
        } catch (Throwable t) {
            System.err.println("[jscissors] failed to start: " + t);
            t.printStackTrace();
        }
    }

    private static Map<String, String> parse(String agentArgs) {
        Map<String, String> args = new HashMap<>();
        if (agentArgs == null) {
            return args;
        }
        for (String pair : agentArgs.split(",")) {
            int eq = pair.indexOf('=');
            if (eq > 0) {
                args.put(pair.substring(0, eq).trim().toLowerCase(), pair.substring(eq + 1).trim());
            }
        }
        return args;
    }
}
