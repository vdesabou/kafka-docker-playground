import java.io.File;
import java.lang.reflect.Field;
import java.lang.reflect.Method;
import java.net.URL;
import java.net.URLClassLoader;
import java.util.ArrayList;
import java.util.Enumeration;
import java.util.List;
import java.util.Map;
import java.util.TreeSet;
import java.util.jar.JarEntry;
import java.util.jar.JarFile;

/**
 * Configuration of a connector plugin, without a Connect worker.
 *
 * Loads the plugin jars in their own class loader (parent: the Kafka jars of the classpath), creates the connector and
 * prints its ConfigDef as the JSON of PUT /connector-plugins/{class}/config/validate. Only JDK classes are used at
 * compile time (reflection for the Kafka ones), so it compiles once and runs with the java of any connect image.
 *
 *   java -cp <dir of ConfigDump.class>:<kafka jars> ConfigDump <plugin lib dir> --discover
 *   java -cp <dir of ConfigDump.class>:<kafka jars> ConfigDump <plugin lib dir> <connector class>
 */
public class ConfigDump {

    public static void main(String[] args) throws Exception {
        if (args.length != 2) {
            System.err.println("usage: ConfigDump <plugin lib dir> --discover|<connector class>");
            System.exit(2);
        }
        File[] jars = new File(args[0]).listFiles((d, n) -> n.endsWith(".jar"));
        if (jars == null || jars.length == 0) {
            System.err.println("no jar in " + args[0]);
            System.exit(1);
        }
        URL[] urls = new URL[jars.length];
        for (int i = 0; i < jars.length; i++) {
            urls[i] = jars[i].toURI().toURL();
        }
        URLClassLoader loader = new URLClassLoader(urls, ConfigDump.class.getClassLoader());
        Thread.currentThread().setContextClassLoader(loader);
        Class<?> connectorType = Class.forName("org.apache.kafka.connect.connector.Connector", false, loader);

        if ("--discover".equals(args[1])) {
            for (String c : discover(jars, loader, connectorType)) {
                System.out.println(c);
            }
            return;
        }

        Object connector = Class.forName(args[1], true, loader).getDeclaredConstructor().newInstance();
        Object configDef = connectorType.getMethod("config").invoke(connector);
        Class<?> configDefType = configDef.getClass();
        while (!configDefType.getName().equals("org.apache.kafka.common.config.ConfigDef")) {
            configDefType = configDefType.getSuperclass();
        }
        Class<?> typeEnum = Class.forName("org.apache.kafka.common.config.ConfigDef$Type", false, loader);
        Method convertToString = configDefType.getMethod("convertToString", Object.class, typeEnum);
        Map<?, ?> keys = (Map<?, ?>) configDefType.getMethod("configKeys").invoke(configDef);

        StringBuilder out = new StringBuilder();
        out.append("{\"name\":").append(str(args[1])).append(",\"configs\":[");
        boolean first = true;
        for (Object key : keys.values()) {
            Class<?> k = key.getClass();
            Object type = field(k, key, "type");
            boolean hasDefault = (Boolean) k.getMethod("hasDefault").invoke(key);
            Object defaultValue = field(k, key, "defaultValue");
            String defaultString = null;
            if (hasDefault && defaultValue != null) {
                defaultString = (String) convertToString.invoke(null, defaultValue, type);
            }
            Object validator = field(k, key, "validator");
            // a validator without its own toString() prints Class$1@hash, different on every run: not a value to compare
            if (validator != null && validator.getClass().getMethod("toString").getDeclaringClass() == Object.class) {
                validator = null;
            }
            if (!first) {
                out.append(',');
            }
            first = false;
            out.append("{\"definition\":{")
                .append("\"name\":").append(str(field(k, key, "name"))).append(',')
                .append("\"type\":").append(str(type)).append(',')
                .append("\"required\":").append(!hasDefault).append(',')
                .append("\"default_value\":").append(str(defaultString)).append(',')
                .append("\"importance\":").append(str(field(k, key, "importance"))).append(',')
                .append("\"documentation\":").append(str(field(k, key, "documentation"))).append(',')
                .append("\"group\":").append(str(field(k, key, "group"))).append(',')
                .append("\"order\":").append(field(k, key, "orderInGroup")).append(',')
                .append("\"display_name\":").append(str(field(k, key, "displayName"))).append(',')
                .append("\"valid_values\":").append(str(validValues(validator)))
                .append("}}");
        }
        out.append("]}");
        System.out.println(out);
    }

    // META-INF/services first (Connect 3.6+ service loading), else the classes named *Connector that are connectors
    static TreeSet<String> discover(File[] jars, ClassLoader loader, Class<?> connectorType) throws Exception {
        TreeSet<String> found = new TreeSet<>();
        for (String service : new String[] {"org.apache.kafka.connect.source.SourceConnector", "org.apache.kafka.connect.sink.SinkConnector"}) {
            Enumeration<URL> e = loader.getResources("META-INF/services/" + service);
            while (e.hasMoreElements()) {
                URL url = e.nextElement();
                if (!url.toString().contains(jarsRoot(jars))) {
                    continue;
                }
                try (java.io.InputStream in = url.openStream()) {
                    for (String line : new String(readAll(in), "UTF-8").split("\n")) {
                        line = line.replaceAll("#.*", "").trim();
                        if (!line.isEmpty()) {
                            found.add(line);
                        }
                    }
                }
            }
        }
        if (!found.isEmpty()) {
            return found;
        }
        List<String> candidates = new ArrayList<>();
        for (File jar : jars) {
            try (JarFile jf = new JarFile(jar)) {
                Enumeration<JarEntry> entries = jf.entries();
                while (entries.hasMoreElements()) {
                    String n = entries.nextElement().getName();
                    if (n.endsWith("Connector.class") && !n.contains("$")) {
                        candidates.add(n.substring(0, n.length() - 6).replace('/', '.'));
                    }
                }
            }
        }
        for (String c : candidates) {
            try {
                Class<?> cls = Class.forName(c, false, loader);
                if (connectorType.isAssignableFrom(cls) && !java.lang.reflect.Modifier.isAbstract(cls.getModifiers())) {
                    found.add(c);
                }
            } catch (Throwable ignored) {
                // not loadable without its optional dependencies: not a connector we can describe anyway
            }
        }
        return found;
    }

    // the valid values a validator describes; null when it prints an object identity (Class$1@6438a396, also nested
    // in a composite validator): different on every run, nothing to compare
    static String validValues(Object validator) {
        if (validator == null) {
            return null;
        }
        String s = validator.toString();
        return s.matches("(?s).*[\\w$]+@[0-9a-f]{4,}.*") ? null : s;
    }

    static String jarsRoot(File[] jars) {
        return jars[0].getParentFile().toURI().toString();
    }

    static byte[] readAll(java.io.InputStream in) throws java.io.IOException {
        java.io.ByteArrayOutputStream b = new java.io.ByteArrayOutputStream();
        byte[] buf = new byte[8192];
        int n;
        while ((n = in.read(buf)) > 0) {
            b.write(buf, 0, n);
        }
        return b.toByteArray();
    }

    static Object field(Class<?> k, Object o, String name) throws Exception {
        try {
            Field f = k.getField(name);
            return f.get(o);
        } catch (NoSuchFieldException e) {
            return null;
        }
    }

    static String str(Object o) {
        if (o == null) {
            return "null";
        }
        String s = o.toString();
        StringBuilder b = new StringBuilder("\"");
        for (char c : s.toCharArray()) {
            switch (c) {
                case '"': b.append("\\\""); break;
                case '\\': b.append("\\\\"); break;
                case '\n': b.append("\\n"); break;
                case '\r': b.append("\\r"); break;
                case '\t': b.append("\\t"); break;
                default:
                    if (c < 0x20) {
                        b.append(String.format("\\u%04x", (int) c));
                    } else {
                        b.append(c);
                    }
            }
        }
        return b.append('"').toString();
    }
}
