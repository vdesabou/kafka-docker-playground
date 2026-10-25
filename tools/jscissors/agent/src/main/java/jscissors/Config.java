package jscissors;

import java.io.BufferedReader;
import java.io.File;
import java.io.IOException;
import java.io.InputStreamReader;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.util.ArrayList;
import java.util.EnumSet;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * The rules file, one rule per line (same syntax as jscissors 1.0):
 *
 * <pre>
 * # class{method}=OP+OP
 * io.confluent.connect.jdbc.sink.JdbcDbWriter{write}=VALUES+RETURN_VALUE
 * io.confluent.connect.jdbc.*{.*find.*}=STACK
 * jscissors.maxCalls=50000
 * </pre>
 *
 * A pattern made of a class or method name only ([\w.$]+) is an exact name, anything else a java regex matched against
 * the whole name. Lines starting with "jscissors." are settings.
 */
public final class Config {

    public static final class Rule {
        public final String line;
        public final String classPattern;
        public final String methodPattern;
        public final EnumSet<Op> ops;
        final Pattern classRegex;
        final Pattern methodRegex;

        Rule(String line, String classPattern, String methodPattern, EnumSet<Op> ops) {
            this.line = line;
            this.classPattern = classPattern;
            this.methodPattern = methodPattern;
            this.ops = ops;
            this.classRegex = compile(classPattern);
            this.methodRegex = compile(methodPattern);
        }

        public boolean matchesClass(String name) {
            return classRegex == null ? classPattern.equals(name) : classRegex.matcher(name).matches();
        }

        public boolean matchesMethod(String name) {
            return methodRegex == null ? methodPattern.equals(name) : methodRegex.matcher(name).matches();
        }

        private static Pattern compile(String pattern) {
            return PLAIN_NAME.matcher(pattern).matches() ? null : Pattern.compile(pattern);
        }
    }

    private static final Pattern PLAIN_NAME = Pattern.compile("[\\w.$]+");
    private static final Pattern RULE = Pattern.compile("^(.+?)\\{(.*)}\\s*=\\s*(.*)$");

    public final List<Rule> rules = new ArrayList<>();
    public final List<String> warnings = new ArrayList<>();
    public final Map<String, Long> settings = new LinkedHashMap<>();

    public Config() {
        // calls with their details in events.jsonl: past it, calls are only counted in the per-method statistics
        settings.put("maxCalls", 50000L);
        // calls of one method with their details: a hot method does not use the whole budget
        settings.put("maxCallsPerMethod", 2000L);
        // characters of a value (argument, return value, exception message)
        settings.put("maxValueLength", 300L);
        // frames of a stack trace
        settings.put("maxStackDepth", 40L);
        settings.put("maxThreadDumps", 10L);
        settings.put("maxHeapDumps", 1L);
        // minimum interval between two dumps of the same kind
        settings.put("dumpIntervalMs", 2000L);
        // 1: only the calls that throw are written with their details (every call is still counted)
        settings.put("onlyFailed", 0L);
        // > 0: only the calls that take at least this long are written with their details (or that throw, with onlyFailed)
        settings.put("slowerThanMs", 0L);
    }

    public long get(String key) {
        return settings.get(key);
    }

    public static Config load(File file) throws IOException {
        Config config = new Config();
        try (BufferedReader reader = new BufferedReader(new InputStreamReader(Files.newInputStream(file.toPath()), StandardCharsets.UTF_8))) {
            String raw;
            while ((raw = reader.readLine()) != null) {
                config.parseLine(raw.trim());
            }
        }
        return config;
    }

    void parseLine(String line) {
        if (line.isEmpty() || line.startsWith("#")) {
            return;
        }
        if (line.startsWith("jscissors.")) {
            int eq = line.indexOf('=');
            String key = eq < 0 ? "" : line.substring("jscissors.".length(), eq).trim();
            if (!settings.containsKey(key)) {
                warnings.add("unknown setting ignored: " + line);
                return;
            }
            try {
                settings.put(key, Long.parseLong(line.substring(eq + 1).trim()));
            } catch (NumberFormatException e) {
                warnings.add("setting ignored, not a number: " + line);
            }
            return;
        }
        Matcher m = RULE.matcher(line);
        if (!m.matches()) {
            warnings.add("line ignored, expected class{method}=OP+OP: " + line);
            return;
        }
        String classPattern = m.group(1).trim();
        String methodPattern = m.group(2).trim();
        if (methodPattern.isEmpty()) {
            methodPattern = ".*";
        }
        EnumSet<Op> ops = EnumSet.noneOf(Op.class);
        for (String op : m.group(3).split("[+,\\s]+")) {
            if (op.isEmpty()) {
                continue;
            }
            try {
                ops.add(Op.valueOf(op.trim().toUpperCase()));
            } catch (IllegalArgumentException e) {
                warnings.add("unknown operation " + op + " ignored in: " + line);
            }
        }
        try {
            rules.add(new Rule(line, classPattern, methodPattern, ops));
        } catch (RuntimeException e) {
            warnings.add("rule ignored, invalid regex (" + e.getMessage().split("\n")[0] + "): " + line);
        }
    }
}
