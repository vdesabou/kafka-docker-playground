import java.io.File;
import java.io.FileInputStream;
import java.io.PrintWriter;
import java.io.StringWriter;
import java.lang.reflect.Constructor;
import java.lang.reflect.Method;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.time.Duration;
import java.time.Instant;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.HashMap;
import java.util.Iterator;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Properties;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ArrayNode;
import com.fasterxml.jackson.databind.node.ObjectNode;

import org.apache.kafka.clients.consumer.ConsumerRecord;
import org.apache.kafka.clients.consumer.KafkaConsumer;
import org.apache.kafka.common.TopicPartition;
import org.apache.kafka.common.record.TimestampType;
import org.apache.kafka.common.serialization.ByteArrayDeserializer;
import org.apache.kafka.connect.connector.ConnectRecord;
import org.apache.kafka.connect.data.Field;
import org.apache.kafka.connect.data.Schema;
import org.apache.kafka.connect.data.SchemaAndValue;
import org.apache.kafka.connect.header.ConnectHeaders;
import org.apache.kafka.connect.header.Header;
import org.apache.kafka.connect.json.JsonConverter;
import org.apache.kafka.connect.sink.SinkRecord;
import org.apache.kafka.connect.source.SourceRecord;
import org.apache.kafka.connect.storage.Converter;
import org.apache.kafka.connect.storage.HeaderConverter;
import org.apache.kafka.connect.transforms.Transformation;

/**
 * Applies the transform chain of a connector configuration to one record, step by step, for
 * 'playground connector smt test'.
 *
 * Runs in a connect worker container with the worker classpath. Transforms, predicates and converters are loaded with
 * Connect's own plugin class loading (Plugins, through reflection since it is an internal API), with the plugin.path
 * given, so that each class comes from the same plugin, and the same version, as in the worker.
 *
 * Arguments: --config <connector config json> --record <record json> [--worker-config <properties>]
 *            [--plugin-path <dirs, comma separated>] [--type sink|source] [--label <text>] [--json] [--json-out <file>]
 *
 * Record json: {"topic", "partition", "offset", "timestamp", "key", "value", "headers": {}} where key and value are
 * schemaless json, or {"schema": ..., "payload": ...} for a Struct; or {"fromTopic", "partition", "offset"} to read a
 * real record and convert it with the converters of the connector.
 */
public class SmtTester {

    static final ObjectMapper MAPPER = new ObjectMapper();
    // the output of the harness; libraries (converters, plugin scanning) log to System.out, which goes to stderr
    static final java.io.PrintStream OUT = System.out;
    static ClassLoader pluginLoader;
    static String pluginLoadingNote = null;
    static String pluginPathValue = "";
    static boolean fullScan = false;
    // plugin directories given for the test (--smt-plugin, --smt-jar): their classes win over the worker plugins
    static List<String> priorityDirs = new ArrayList<>();
    static Map<String, ClassLoader> priorityLoaders = new HashMap<>();

    // AppInfoParser moved to org.apache.kafka.common.utils.internals in CP 8.4: found through
    // reflection, so that the harness compiles against the jars of every version
    static String kafkaVersion() {
        for (String name : new String[] {"org.apache.kafka.common.utils.internals.AppInfoParser", "org.apache.kafka.common.utils.AppInfoParser"}) {
            try {
                return (String) Class.forName(name).getMethod("getVersion").invoke(null);
            } catch (Exception ignored) {
                // not in this version
            }
        }
        return "unknown";
    }

    public static void main(String[] argv) throws Exception {
        System.setOut(System.err);
        Map<String, String> args = new HashMap<>();
        for (int i = 0; i < argv.length; i++) {
            if (argv[i].equals("--json")) {
                args.put("json", "true");
            } else if (argv[i].startsWith("--") && i + 1 < argv.length) {
                args.put(argv[i].substring(2), argv[++i]);
            }
        }
        if (!args.containsKey("config") || !args.containsKey("record")) {
            System.err.println("usage: SmtTester --config <file> --record <file> [--worker-config <file>] [--plugin-path <dirs>] [--type sink|source] [--label <text>] [--json]");
            System.exit(2);
        }
        Map<String, String> config = readStringMap(args.get("config"));
        JsonNode recordSpec = MAPPER.readTree(new File(args.get("record")));
        Properties worker = new Properties();
        if (args.containsKey("worker-config") && new File(args.get("worker-config")).exists()) {
            try (FileInputStream in = new FileInputStream(args.get("worker-config"))) {
                worker.load(in);
            }
        }
        String pluginPath = args.getOrDefault("plugin-path", worker.getProperty("plugin.path", ""));
        boolean json = args.containsKey("json");
        jsonOut = args.get("json-out");
        boolean source = "source".equals(args.get("type"));
        String label = args.getOrDefault("label", "");

        pluginPathValue = pluginPath;
        priorityDirs = list(args.get("priority-plugin-path"));
        // service_load (Apache Kafka 3.6+, ignored before) is much faster than scanning; a full scan is done when a
        // class is not found, for plugins without service manifests
        pluginLoader = loadPlugins(pluginPath, "service_load");

        ObjectNode out = MAPPER.createObjectNode();
        out.put("label", label);
        out.put("kafka_version", kafkaVersion());
        out.put("connector_type", source ? "source" : "sink");
        if (pluginLoadingNote != null) {
            out.put("plugin_loading", pluginLoadingNote);
        }
        ArrayNode steps = out.putArray("steps");
        int exit = 0;
        ConnectRecord<?> record;
        try {
            record = buildRecord(recordSpec, config, worker, source);
        } catch (Exception e) {
            out.put("error", "could not build the record: " + causes(e));
            print(out, json);
            System.exit(2);
            return;
        }
        ObjectNode input = steps.addObject();
        input.put("index", 0);
        input.put("alias", "input");
        input.set("record", snapshot(record));

        List<String> aliases = list(config.get("transforms"));
        Map<String, Object> predicates = new HashMap<>();
        for (String alias : aliases) {
            ObjectNode step = steps.addObject();
            step.put("index", steps.size() - 1);
            step.put("alias", alias);
            String type = config.get("transforms." + alias + ".type");
            step.put("type", type);
            try {
                if (type == null) {
                    throw new IllegalArgumentException("transforms." + alias + ".type is not set");
                }
                Class<?> klass = pluginClass(type);
                step.put("origin", origin(klass));
                List<String> also = duplicates(type, klass);
                if (!also.isEmpty()) {
                    ArrayNode a = step.putArray("also_in");
                    also.forEach(a::add);
                }
                Map<String, String> props = prefixed(config, "transforms." + alias + ".");
                props.remove("type");
                String predicateName = props.remove("predicate");
                boolean negate = Boolean.parseBoolean(props.remove("negate"));
                ObjectNode configNode = step.putObject("config");
                props.forEach(configNode::put);
                // raw type: the chain mixes record types at runtime, like the connect TransformationChain
                @SuppressWarnings("rawtypes")
                Transformation transformation = (Transformation) newInstance(klass);
                ClassLoader previous = swap(klass.getClassLoader());
                try {
                    transformation.configure(props);
                    if (predicateName != null) {
                        boolean result = testPredicate(predicateName, config, predicates, record, step);
                        boolean applies = negate != result;
                        step.put("negate", negate);
                        step.put("predicate_result", result);
                        if (!applies) {
                            step.put("skipped", true);
                            step.set("record", snapshot(record));
                            continue;
                        }
                    }
                    @SuppressWarnings("unchecked")
                    ConnectRecord<?> next = (ConnectRecord<?>) transformation.apply(record);
                    if (next == null) {
                        step.put("dropped", true);
                        break;
                    }
                    record = next;
                    step.set("record", snapshot(record));
                } finally {
                    swap(previous);
                }
            } catch (Throwable e) {
                step.put("error", causes(e));
                StringWriter trace = new StringWriter();
                e.printStackTrace(new PrintWriter(trace));
                step.put("stack_trace", trace.toString());
                exit = 1;
                break;
            }
        }
        print(out, json);
        System.exit(exit);
    }

    // ---- plugins ------------------------------------------------------------------------------------------------

    /** Connect's DelegatingClassLoader for the plugin path, or the worker class loader when Plugins is not usable. */
    /** jars of a plugin directory: the directory itself, its lib/ folder, or a single jar */
    static List<File> jars(String path) {
        List<File> jars = new ArrayList<>();
        File f = new File(path);
        if (f.isFile() && f.getName().endsWith(".jar")) {
            jars.add(f);
            return jars;
        }
        for (File dir : new File[] {f, new File(f, "lib")}) {
            File[] files = dir.listFiles((d, n) -> n.endsWith(".jar"));
            if (files != null) {
                jars.addAll(Arrays.asList(files));
            }
        }
        return jars;
    }

    static boolean containsClass(String path, String className) {
        String entry = className.replace('.', '/') + ".class";
        for (File jar : jars(path)) {
            try (java.util.zip.ZipFile zip = new java.util.zip.ZipFile(jar)) {
                if (zip.getEntry(entry) != null) {
                    return true;
                }
            } catch (Exception ignored) {
                // not a readable jar
            }
        }
        return false;
    }

    /** the plugin directories (other than the one used) that also contain a class */
    static List<String> duplicates(String className, Class<?> loaded) {
        List<String> dirs = new ArrayList<>();
        String used = "";
        try {
            used = loaded.getProtectionDomain().getCodeSource().getLocation().getPath();
        } catch (Exception ignored) {
            // no code source
        }
        List<String> all = new ArrayList<>(list(pluginPathValue));
        all.addAll(priorityDirs);
        for (String dir : all) {
            if (!used.startsWith(dir) && containsClass(dir, className)) {
                dirs.add(dir);
            }
        }
        return dirs;
    }

    /** a plugin class, with a full scan of the plugin path when the fast discovery did not find it */
    static Class<?> pluginClass(String name) throws ClassNotFoundException {
        for (String dir : priorityDirs) {
            if (containsClass(dir, name)) {
                ClassLoader loader = priorityLoaders.get(dir);
                if (loader == null) {
                    List<java.net.URL> urls = new ArrayList<>();
                    for (File jar : jars(dir)) {
                        try {
                            urls.add(jar.toURI().toURL());
                        } catch (Exception ignored) {
                            // invalid path
                        }
                    }
                    loader = new java.net.URLClassLoader(urls.toArray(new java.net.URL[0]), SmtTester.class.getClassLoader());
                    priorityLoaders.put(dir, loader);
                }
                return Class.forName(name, true, loader);
            }
        }
        try {
            return Class.forName(name, true, pluginLoader);
        } catch (ClassNotFoundException | NoClassDefFoundError e) {
            if (fullScan) {
                throw e;
            }
            fullScan = true;
            pluginLoader = loadPlugins(pluginPathValue, "hybrid_warn");
            return Class.forName(name, true, pluginLoader);
        }
    }

    static ClassLoader loadPlugins(String pluginPath, String discovery) {
        try {
            Class<?> pluginsClass = Class.forName("org.apache.kafka.connect.runtime.isolation.Plugins");
            Constructor<?> constructor = pluginsClass.getConstructor(Map.class);
            Map<String, String> props = new HashMap<>();
            props.put("plugin.path", pluginPath == null ? "" : pluginPath);
            props.put("plugin.discovery", discovery);
            Object plugins = constructor.newInstance(props);
            Method delegating = pluginsClass.getMethod("delegatingLoader");
            return (ClassLoader) delegating.invoke(plugins);
        } catch (Throwable e) {
            pluginLoadingNote = "Connect plugin class loading not available (" + causes(e) + "): plugin SMTs are loaded from the worker classpath only";
            return SmtTester.class.getClassLoader();
        }
    }

    static Object newInstance(Class<?> klass) throws Exception {
        ClassLoader previous = swap(klass.getClassLoader());
        try {
            return klass.getDeclaredConstructor().newInstance();
        } finally {
            swap(previous);
        }
    }

    static ClassLoader swap(ClassLoader loader) {
        ClassLoader previous = Thread.currentThread().getContextClassLoader();
        if (loader != null) {
            Thread.currentThread().setContextClassLoader(loader);
        }
        return previous;
    }

    /** where a class comes from: the worker (apache kafka version) or a plugin directory (its manifest version). */
    static String origin(Class<?> klass) {
        String location = "";
        try {
            location = klass.getProtectionDomain().getCodeSource().getLocation().getPath();
        } catch (Exception ignored) {
            // no code source
        }
        File jar = new File(location);
        for (File dir = jar.getParentFile(); dir != null; dir = dir.getParentFile()) {
            File manifest = new File(dir, "manifest.json");
            if (manifest.exists()) {
                try {
                    JsonNode m = MAPPER.readTree(manifest);
                    return m.path("owner").path("username").asText(m.path("name").asText(dir.getName())) + "/" + m.path("name").asText("") + " " + m.path("version").asText("") + " (plugin " + dir.getPath() + ")";
                } catch (Exception ignored) {
                    return "plugin " + dir.getPath();
                }
            }
            if (dir.getPath().equals("/usr/share/java") || dir.getParentFile() == null) {
                break;
            }
        }
        if (klass.getName().startsWith("org.apache.kafka.")) {
            return "Kafka " + kafkaVersion() + " (worker)";
        }
        String version = klass.getPackage() != null ? klass.getPackage().getImplementationVersion() : null;
        boolean testPlugin = priorityLoaders.containsValue(klass.getClassLoader());
        return jar.getName() + (version != null ? " " + version : "") + (testPlugin ? " (given for the test)" : " (worker classpath)");
    }

    @SuppressWarnings({"unchecked", "rawtypes"})
    static boolean testPredicate(String name, Map<String, String> config, Map<String, Object> cache, ConnectRecord<?> record, ObjectNode step) throws Exception {
        Object predicate = cache.get(name);
        String type = config.get("predicates." + name + ".type");
        step.put("predicate", name);
        step.put("predicate_type", type);
        if (predicate == null) {
            if (type == null) {
                throw new IllegalArgumentException("predicates." + name + ".type is not set");
            }
            Class<?> klass = pluginClass(type);
            predicate = newInstance(klass);
            Map<String, String> props = prefixed(config, "predicates." + name + ".");
            props.remove("type");
            ((org.apache.kafka.connect.transforms.predicates.Predicate) predicate).configure(props);
            cache.put(name, predicate);
        }
        return ((org.apache.kafka.connect.transforms.predicates.Predicate) predicate).test(record);
    }

    // ---- record -------------------------------------------------------------------------------------------------

    static ConnectRecord<?> buildRecord(JsonNode spec, Map<String, String> config, Properties worker, boolean source) throws Exception {
        if (spec.has("fromTopic")) {
            return readRecord(spec, config, worker, source);
        }
        String topic = spec.path("topic").asText("test-topic");
        int partition = spec.path("partition").asInt(0);
        long offset = spec.path("offset").asLong(0);
        Long timestamp = spec.has("timestamp") ? spec.get("timestamp").asLong() : System.currentTimeMillis();
        SchemaAndValue key = jsonToConnect(topic, spec.get("key"), true);
        SchemaAndValue value = jsonToConnect(topic, spec.get("value"), false);
        ConnectHeaders headers = new ConnectHeaders();
        JsonNode headersNode = spec.get("headers");
        if (headersNode != null && headersNode.isObject()) {
            Iterator<Map.Entry<String, JsonNode>> it = headersNode.fields();
            while (it.hasNext()) {
                Map.Entry<String, JsonNode> h = it.next();
                headers.add(h.getKey(), jsonToHeader(topic, h.getValue()));
            }
        } else if (headersNode != null && headersNode.isArray()) {
            // [{"key": ..., "value": ...}]: several headers can have the same key
            for (JsonNode h : headersNode) {
                headers.add(h.path("key").asText(), jsonToHeader(topic, h.get("value")));
            }
        }
        return newRecord(source, topic, partition, offset, timestamp, key, value, headers);
    }

    static ConnectRecord<?> newRecord(boolean source, String topic, int partition, long offset, Long timestamp, SchemaAndValue key, SchemaAndValue value, ConnectHeaders headers) {
        if (source) {
            return new SourceRecord(Collections.emptyMap(), Collections.emptyMap(), topic, partition, key.schema(), key.value(), value.schema(), value.value(), timestamp, headers);
        }
        return new SinkRecord(topic, partition, key.schema(), key.value(), value.schema(), value.value(), offset, timestamp, TimestampType.CREATE_TIME, headers);
    }

    /** a header value from json, typed like the SimpleHeaderConverter does: string, int64, float64, boolean, map,
     *  array, null, or a value with a schema with the {"schema", "payload"} envelope */
    static SchemaAndValue jsonToHeader(String topic, JsonNode node) throws Exception {
        if (node == null || node.isNull()) {
            return new SchemaAndValue(null, null);
        }
        if (node.isTextual()) {
            return new SchemaAndValue(Schema.STRING_SCHEMA, node.asText());
        }
        if (node.isBoolean()) {
            return new SchemaAndValue(Schema.BOOLEAN_SCHEMA, node.asBoolean());
        }
        if (node.isIntegralNumber()) {
            return new SchemaAndValue(Schema.INT64_SCHEMA, node.asLong());
        }
        if (node.isNumber()) {
            return new SchemaAndValue(Schema.FLOAT64_SCHEMA, node.asDouble());
        }
        return jsonToConnect(topic, node, false);
    }

    /** schemaless json, or the {"schema", "payload"} envelope of the JsonConverter for data with a schema */
    static SchemaAndValue jsonToConnect(String topic, JsonNode node, boolean isKey) throws Exception {
        if (node == null || node.isNull()) {
            return SchemaAndValue.NULL;
        }
        boolean envelope = node.isObject() && node.size() == 2 && node.has("schema") && node.has("payload");
        JsonConverter converter = new JsonConverter();
        Map<String, String> props = new HashMap<>();
        props.put("schemas.enable", Boolean.toString(envelope));
        converter.configure(props, isKey);
        return converter.toConnectData(topic, MAPPER.writeValueAsBytes(node));
    }

    /** a real record of a topic, converted with the converters of the connector (or of the worker) */
    static ConnectRecord<?> readRecord(JsonNode spec, Map<String, String> config, Properties worker, boolean source) throws Exception {
        String topic = spec.get("fromTopic").asText();
        int partition = spec.path("partition").asInt(0);
        long offset = spec.path("offset").asLong(0);
        Properties consumerProps = new Properties();
        for (String name : worker.stringPropertyNames()) {
            if (name.equals("bootstrap.servers") || name.startsWith("security.") || name.startsWith("sasl.") || name.startsWith("ssl.")) {
                consumerProps.put(name, worker.getProperty(name));
            }
        }
        consumerProps.put("key.deserializer", ByteArrayDeserializer.class.getName());
        consumerProps.put("value.deserializer", ByteArrayDeserializer.class.getName());
        consumerProps.put("enable.auto.commit", "false");
        ConsumerRecord<byte[], byte[]> raw = null;
        try (KafkaConsumer<byte[], byte[]> consumer = new KafkaConsumer<>(consumerProps)) {
            TopicPartition tp = new TopicPartition(topic, partition);
            consumer.assign(Collections.singletonList(tp));
            consumer.seek(tp, offset);
            long deadline = System.currentTimeMillis() + 15000;
            while (raw == null && System.currentTimeMillis() < deadline) {
                for (ConsumerRecord<byte[], byte[]> r : consumer.poll(Duration.ofMillis(500))) {
                    if (r.offset() >= offset) {
                        raw = r;
                        break;
                    }
                }
            }
        }
        if (raw == null) {
            throw new IllegalStateException("no record at offset " + offset + " of partition " + partition + " of topic " + topic);
        }
        Converter keyConverter = converter("key.converter", config, worker, true);
        Converter valueConverter = converter("value.converter", config, worker, false);
        SchemaAndValue key = keyConverter.toConnectData(topic, raw.headers(), raw.key());
        SchemaAndValue value = valueConverter.toConnectData(topic, raw.headers(), raw.value());
        HeaderConverter headerConverter = headerConverter(config, worker);
        ConnectHeaders headers = new ConnectHeaders();
        for (org.apache.kafka.common.header.Header h : raw.headers()) {
            headers.add(h.key(), headerConverter.toConnectHeader(topic, h.key(), h.value()));
        }
        return newRecord(source, topic, raw.partition(), raw.offset(), raw.timestamp(), key, value, headers);
    }

    static Converter converter(String prefix, Map<String, String> config, Properties worker, boolean isKey) throws Exception {
        String className = config.getOrDefault(prefix, worker.getProperty(prefix));
        if (className == null) {
            throw new IllegalArgumentException(prefix + " is not set in the connector nor in the worker");
        }
        Class<?> klass = pluginClass(className);
        Converter converter = (Converter) newInstance(klass);
        Map<String, Object> props = new HashMap<>();
        // the worker settings, overridden by the connector ones, like the connect runtime
        for (String name : worker.stringPropertyNames()) {
            if (name.startsWith(prefix + ".")) {
                props.put(name.substring(prefix.length() + 1), worker.getProperty(name));
            }
        }
        if (config.containsKey(prefix)) {
            props.putAll(prefixed(config, prefix + "."));
        }
        ClassLoader previous = swap(klass.getClassLoader());
        try {
            converter.configure(props, isKey);
        } finally {
            swap(previous);
        }
        return converter;
    }

    static HeaderConverter headerConverter(Map<String, String> config, Properties worker) throws Exception {
        String className = config.getOrDefault("header.converter", worker.getProperty("header.converter", "org.apache.kafka.connect.storage.SimpleHeaderConverter"));
        Class<?> klass = pluginClass(className);
        HeaderConverter converter = (HeaderConverter) newInstance(klass);
        converter.configure(prefixed(config, "header.converter."));
        return converter;
    }

    // ---- output -------------------------------------------------------------------------------------------------

    static ObjectNode snapshot(ConnectRecord<?> record) {
        ObjectNode node = MAPPER.createObjectNode();
        node.put("topic", record.topic());
        if (record.kafkaPartition() != null) {
            node.put("partition", record.kafkaPartition());
        }
        if (record instanceof SinkRecord) {
            node.put("offset", ((SinkRecord) record).kafkaOffset());
        }
        if (record.timestamp() != null) {
            node.put("timestamp", Instant.ofEpochMilli(record.timestamp()).toString());
        }
        node.put("key", render(record.topic(), record.keySchema(), record.key()));
        node.put("key_schema", describe(record.keySchema()));
        node.put("value", render(record.topic(), record.valueSchema(), record.value()));
        node.put("value_schema", describe(record.valueSchema()));
        ObjectNode schemaFields = node.putObject("value_fields");
        if (record.valueSchema() != null && record.valueSchema().type() == Schema.Type.STRUCT) {
            for (Field f : record.valueSchema().fields()) {
                schemaFields.put(f.name(), typeName(f.schema()));
            }
        }
        // an ordered list: several headers can have the same key
        ArrayNode headers = node.putArray("headers");
        for (Header h : record.headers()) {
            ObjectNode header = headers.addObject();
            header.put("key", h.key());
            header.put("value", render(record.topic(), h.schema(), h.value()));
            header.put("schema", h.schema() == null ? "schemaless" : describe(h.schema()));
        }
        return node;
    }

    /** a value as json (logical types converted), or its toString when it cannot be */
    static String render(String topic, Schema schema, Object value) {
        if (value == null) {
            return "null";
        }
        try {
            JsonConverter converter = new JsonConverter();
            Map<String, String> props = new HashMap<>();
            props.put("schemas.enable", "false");
            converter.configure(props, false);
            return new String(converter.fromConnectData(topic, schema, value), StandardCharsets.UTF_8);
        } catch (Exception e) {
            return String.valueOf(value);
        }
    }

    static String typeName(Schema schema) {
        if (schema == null) {
            return "none";
        }
        String type = schema.name() != null && schema.type() != Schema.Type.STRUCT ? schema.name() : schema.type().toString();
        return type + (schema.isOptional() ? "?" : "");
    }

    static String describe(Schema schema) {
        if (schema == null) {
            return "schemaless";
        }
        if (schema.type() == Schema.Type.STRUCT) {
            StringBuilder sb = new StringBuilder(schema.name() != null ? schema.name() : "struct");
            if (schema.version() != null) {
                sb.append(" v").append(schema.version());
            }
            sb.append(": ");
            List<String> fields = new ArrayList<>();
            for (Field f : schema.fields()) {
                fields.add(f.name() + " " + typeName(f.schema()));
            }
            return sb.append(String.join(", ", fields)).toString();
        }
        return typeName(schema);
    }

    static String jsonOut = null;

    static void print(ObjectNode out, boolean json) throws Exception {
        if (jsonOut != null) {
            Files.write(new File(jsonOut).toPath(), MAPPER.writerWithDefaultPrettyPrinter().writeValueAsBytes(out));
        }
        if (json) {
            OUT.println(MAPPER.writerWithDefaultPrettyPrinter().writeValueAsString(out));
            return;
        }
        StringBuilder sb = new StringBuilder();
        String label = out.path("label").asText();
        if (out.has("plugin_loading")) {
            sb.append("⚠️ ").append(out.get("plugin_loading").asText()).append("\n");
        }
        if (out.has("error")) {
            sb.append("❌ ").append(out.get("error").asText()).append("\n");
            OUT.print(sb);
            return;
        }
        ArrayNode steps = (ArrayNode) out.get("steps");
        sb.append("🧪 ").append(steps.size() - 1).append(" transform(s) on a ").append(out.get("connector_type").asText())
          .append(" record, Kafka ").append(out.get("kafka_version").asText()).append(label.isEmpty() ? "" : " (" + label + ")").append("\n\n");
        JsonNode previous = null;
        JsonNode last = null;
        for (JsonNode step : steps) {
            int index = step.get("index").asInt();
            if (index == 0) {
                JsonNode r = step.get("record");
                sb.append("step 0  input\n");
                line(sb, "topic", r.path("topic").asText() + "  partition " + r.path("partition").asText("-") + (r.has("offset") ? "  offset " + r.get("offset").asText() : "") + "  timestamp " + r.path("timestamp").asText("-"));
                line(sb, "key", r.get("key").asText() + "   (" + r.get("key_schema").asText() + ")");
                line(sb, "value", r.get("value").asText());
                line(sb, "schema", r.get("value_schema").asText());
                for (JsonNode h : r.get("headers")) {
                    line(sb, "header", h.get("key").asText() + " = " + h.get("value").asText() + "   (" + h.get("schema").asText() + ")");
                }
                previous = r;
                last = r;
                continue;
            }
            sb.append("\nstep ").append(index).append("  ").append(shortType(step.path("type").asText("?"))).append(" \"").append(step.get("alias").asText()).append("\"");
            if (step.has("config") && step.get("config").size() > 0) {
                sb.append("  ").append(compactConfig(step.get("config")));
            }
            sb.append("\n");
            if (step.has("origin")) {
                line(sb, "from", step.get("origin").asText());
            }
            if (step.has("also_in")) {
                List<String> also = new ArrayList<>();
                step.get("also_in").forEach(n -> also.add(n.asText()));
                line(sb, "also in", "⚠️ " + String.join(", ", also) + " (the worker could load another copy)");
            }
            if (step.has("predicate")) {
                line(sb, "predicate", step.get("predicate").asText() + " (" + shortType(step.path("predicate_type").asText()) + ") = " + step.path("predicate_result").asText()
                        + (step.path("negate").asBoolean() ? ", negate=true" : ""));
            }
            if (step.has("error")) {
                sb.append("        ❌ ").append(step.get("error").asText()).append("\n");
                sb.append("\n❌ the chain stopped at step ").append(index).append(" (--verbose or --json for the stack trace)\n");
                String verbose = System.getenv("SMT_TESTER_VERBOSE");
                if (verbose != null && !verbose.isEmpty()) {
                    sb.append(step.get("stack_trace").asText());
                }
                OUT.print(sb);
                return;
            }
            if (step.path("dropped").asBoolean()) {
                sb.append("        🗑️ the record is dropped (the transform returned null)\n");
                sb.append("\n🗑️ dropped by step ").append(index).append("\n");
                OUT.print(sb);
                return;
            }
            if (step.path("skipped").asBoolean()) {
                sb.append("        ⏭️ skipped (predicate)\n");
                continue;
            }
            JsonNode r = step.get("record");
            List<String> changes = diff(previous, r, sb);
            if (changes.isEmpty()) {
                sb.append("        (no change)\n");
            }
            previous = r;
            last = r;
        }
        sb.append("\n✅ result: topic ").append(last.path("topic").asText()).append(", key ").append(last.path("key").asText()).append("\n");
        line(sb, "value", last.path("value").asText());
        OUT.print(sb);
    }

    static List<String> diff(JsonNode before, JsonNode after, StringBuilder sb) {
        List<String> changes = new ArrayList<>();
        for (String field : Arrays.asList("topic", "partition", "timestamp")) {
            if (!before.path(field).equals(after.path(field))) {
                line(sb, field, before.path(field).asText() + " → " + after.path(field).asText());
                changes.add(field);
            }
        }
        if (!before.path("key").equals(after.path("key")) || !before.path("key_schema").equals(after.path("key_schema"))) {
            line(sb, "key", after.path("key").asText() + "   (" + after.path("key_schema").asText() + ")");
            changes.add("key");
        }
        if (!before.path("value").equals(after.path("value"))) {
            line(sb, "value", after.path("value").asText());
            changes.add("value");
        }
        if (!before.path("value_schema").equals(after.path("value_schema"))) {
            List<String> schemaChanges = new ArrayList<>();
            JsonNode bf = before.path("value_fields");
            JsonNode af = after.path("value_fields");
            Iterator<String> names = af.fieldNames();
            while (names.hasNext()) {
                String n = names.next();
                if (!bf.has(n)) {
                    schemaChanges.add("+ " + n + " " + af.get(n).asText());
                } else if (!bf.get(n).equals(af.get(n))) {
                    schemaChanges.add(n + " " + bf.get(n).asText() + " → " + af.get(n).asText());
                }
            }
            names = bf.fieldNames();
            while (names.hasNext()) {
                String n = names.next();
                if (!af.has(n)) {
                    schemaChanges.add("- " + n);
                }
            }
            line(sb, "schema", schemaChanges.isEmpty() ? before.path("value_schema").asText() + " → " + after.path("value_schema").asText() : String.join(", ", schemaChanges));
            changes.add("schema");
        }
        if (!before.path("headers").equals(after.path("headers"))) {
            for (String change : headerChanges(before.path("headers"), after.path("headers"))) {
                line(sb, "header", change);
            }
            changes.add("headers");
        }
        return changes;
    }

    /** header changes between two snapshots, by key (the n-th header of a key against the n-th one) */
    static List<String> headerChanges(JsonNode before, JsonNode after) {
        Map<String, List<JsonNode>> b = byKey(before);
        Map<String, List<JsonNode>> a = byKey(after);
        List<String> changes = new ArrayList<>();
        for (Map.Entry<String, List<JsonNode>> e : a.entrySet()) {
            List<JsonNode> old = b.getOrDefault(e.getKey(), Collections.emptyList());
            for (int i = 0; i < e.getValue().size(); i++) {
                JsonNode h = e.getValue().get(i);
                String text = h.get("key").asText() + " = " + h.get("value").asText() + "   (" + h.get("schema").asText() + ")";
                if (i >= old.size()) {
                    changes.add("+ " + text);
                } else if (!old.get(i).equals(h)) {
                    changes.add("~ " + text + "   was " + old.get(i).get("value").asText() + " (" + old.get(i).get("schema").asText() + ")");
                }
            }
        }
        for (Map.Entry<String, List<JsonNode>> e : b.entrySet()) {
            List<JsonNode> now = a.getOrDefault(e.getKey(), Collections.emptyList());
            for (int i = now.size(); i < e.getValue().size(); i++) {
                changes.add("- " + e.getKey());
            }
        }
        return changes;
    }

    static Map<String, List<JsonNode>> byKey(JsonNode headers) {
        Map<String, List<JsonNode>> map = new LinkedHashMap<>();
        for (JsonNode h : headers) {
            map.computeIfAbsent(h.get("key").asText(), k -> new ArrayList<>()).add(h);
        }
        return map;
    }

    static void line(StringBuilder sb, String label, String text) {
        sb.append("        ").append(String.format("%-10s", label)).append(text).append("\n");
    }

    static String shortType(String type) {
        int dot = type.lastIndexOf('.');
        return dot >= 0 ? type.substring(dot + 1) : type;
    }

    static String compactConfig(JsonNode config) {
        List<String> parts = new ArrayList<>();
        Iterator<Map.Entry<String, JsonNode>> it = config.fields();
        while (it.hasNext()) {
            Map.Entry<String, JsonNode> e = it.next();
            parts.add(e.getKey() + "=" + e.getValue().asText());
        }
        String s = "(" + String.join(", ", parts) + ")";
        return s.length() > 110 ? s.substring(0, 107) + "...)" : s;
    }

    // ---- helpers ------------------------------------------------------------------------------------------------

    static Map<String, String> readStringMap(String path) throws Exception {
        JsonNode node = MAPPER.readTree(new String(Files.readAllBytes(new File(path).toPath()), StandardCharsets.UTF_8));
        Map<String, String> map = new LinkedHashMap<>();
        Iterator<Map.Entry<String, JsonNode>> it = node.fields();
        while (it.hasNext()) {
            Map.Entry<String, JsonNode> e = it.next();
            map.put(e.getKey(), e.getValue().isTextual() ? e.getValue().asText() : e.getValue().toString());
        }
        return map;
    }

    static Map<String, String> prefixed(Map<String, String> config, String prefix) {
        Map<String, String> props = new LinkedHashMap<>();
        for (Map.Entry<String, String> e : config.entrySet()) {
            if (e.getKey().startsWith(prefix)) {
                props.put(e.getKey().substring(prefix.length()), e.getValue());
            }
        }
        return props;
    }

    static List<String> list(String value) {
        List<String> items = new ArrayList<>();
        if (value != null) {
            for (String s : value.split(",")) {
                if (!s.trim().isEmpty()) {
                    items.add(s.trim());
                }
            }
        }
        return items;
    }

    static String causes(Throwable e) {
        StringBuilder sb = new StringBuilder();
        for (Throwable t = e; t != null; t = t.getCause()) {
            if (sb.length() > 0) {
                sb.append(" | Caused by: ");
            }
            sb.append(t.getClass().getName()).append(t.getMessage() != null ? ": " + t.getMessage() : "");
            if (t.getCause() == t) {
                break;
            }
        }
        return sb.toString();
    }
}
