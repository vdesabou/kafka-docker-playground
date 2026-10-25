package jscissors;

import java.lang.reflect.Array;
import java.nio.charset.StandardCharsets;
import java.util.Collection;
import java.util.Iterator;
import java.util.Map;
import java.util.regex.Pattern;

/**
 * Text of an argument or a return value: bounded, never throws, secrets masked. toString() of the application objects
 * is called with the tracing of the thread suspended (Tracer), so it is never traced and cannot recurse.
 */
final class Values {
    private static final int MAX_ELEMENTS = 10;
    private static final int MAX_BYTES = 32;
    private static final Pattern SECRET_KEY = Pattern.compile("(?i).*(password|secret|token|credential|jaas|api\\.?key|private\\.key|keytab|sasl\\.jaas).*");
    // key=value / key: value / "key":"value" pairs of a secret inside any text (a config map, a connection string)
    private static final Pattern SECRET_IN_TEXT = Pattern.compile(
            "(?i)((?:password|passwd|pwd|secret|token|credentials?|api[._-]?key|private[._-]key)[\\w.-]*\"?\\s*[=:]\\s*\"?)([^\\s,;&}\\]\"]+)");
    private static final Pattern JAAS_PASSWORD = Pattern.compile("(?i)(password\\s*=\\s*\")([^\"]*)");

    private Values() {
    }

    static String of(Object value, int max) {
        try {
            StringBuilder sb = new StringBuilder();
            append(sb, value, max, 0);
            return mask(truncate(sb, max));
        } catch (Throwable t) {
            return "<" + value.getClass().getName() + ": toString failed with " + t.getClass().getSimpleName() + ">";
        }
    }

    static String mask(String s) {
        if (s.length() < 6) {
            return s;
        }
        String out = JAAS_PASSWORD.matcher(s).replaceAll("$1********");
        return SECRET_IN_TEXT.matcher(out).replaceAll("$1********");
    }

    private static String truncate(StringBuilder sb, int max) {
        if (sb.length() <= max) {
            return sb.toString();
        }
        return sb.substring(0, max) + "…(" + sb.length() + " chars)";
    }

    private static void append(StringBuilder sb, Object value, int max, int depth) {
        if (sb.length() > max) {
            return;
        }
        if (value == null) {
            sb.append("null");
        } else if (value instanceof CharSequence) {
            CharSequence cs = (CharSequence) value;
            sb.append('"').append(cs.length() > max ? cs.subSequence(0, max) : cs).append('"');
        } else if (value instanceof Number || value instanceof Boolean || value instanceof Enum) {
            sb.append(value);
        } else if (value instanceof Character) {
            sb.append('\'').append(value).append('\'');
        } else if (value instanceof byte[]) {
            bytes(sb, (byte[]) value, max);
        } else if (value.getClass().isArray()) {
            int length = Array.getLength(value);
            sb.append(value.getClass().getComponentType().getSimpleName()).append('[').append(length).append("] [");
            for (int i = 0; i < Math.min(length, MAX_ELEMENTS); i++) {
                if (i > 0) {
                    sb.append(", ");
                }
                element(sb, Array.get(value, i), max, depth);
            }
            sb.append(length > MAX_ELEMENTS ? ", …]" : "]");
        } else if (value instanceof Map) {
            Map<?, ?> map = (Map<?, ?>) value;
            sb.append(value.getClass().getSimpleName()).append('(').append(map.size()).append(") {");
            int i = 0;
            for (Map.Entry<?, ?> entry : map.entrySet()) {
                if (i++ == MAX_ELEMENTS || sb.length() > max) {
                    sb.append(", …");
                    break;
                }
                if (i > 1) {
                    sb.append(", ");
                }
                String key = String.valueOf(entry.getKey());
                sb.append(key).append('=');
                if (SECRET_KEY.matcher(key).matches()) {
                    sb.append("********");
                } else {
                    element(sb, entry.getValue(), max, depth);
                }
            }
            sb.append('}');
        } else if (value instanceof Collection) {
            Collection<?> collection = (Collection<?>) value;
            sb.append(value.getClass().getSimpleName()).append('(').append(collection.size()).append(") [");
            Iterator<?> it = collection.iterator();
            for (int i = 0; it.hasNext(); i++) {
                if (i == MAX_ELEMENTS || sb.length() > max) {
                    sb.append(", …");
                    break;
                }
                if (i > 0) {
                    sb.append(", ");
                }
                element(sb, it.next(), max, depth);
            }
            sb.append(']');
        } else {
            sb.append(value.toString());
        }
    }

    /**
     * A record key or value most of the time: its text when it is printable (JSON, string), the schema id of the
     * Confluent wire format (magic byte 0 + 4 bytes schema id: Avro, Protobuf, JSON Schema), else the first bytes in hex
     */
    private static void bytes(StringBuilder sb, byte[] bytes, int max) {
        sb.append("byte[").append(bytes.length).append(']');
        if (bytes.length == 0) {
            return;
        }
        String text = new String(bytes, 0, Math.min(bytes.length, max), StandardCharsets.UTF_8);
        int printable = 0;
        for (int i = 0; i < text.length(); i++) {
            char c = text.charAt(i);
            if (c >= 0x20 && c != 0xfffd || c == '\n' || c == '\r' || c == '\t') {
                printable++;
            }
        }
        if (printable == text.length()) {
            sb.append(" \"").append(text).append(bytes.length > max ? "…\"" : "\"");
            return;
        }
        int offset = 0;
        if (bytes[0] == 0 && bytes.length >= 5) {
            int schemaId = ((bytes[1] & 0xff) << 24) | ((bytes[2] & 0xff) << 16) | ((bytes[3] & 0xff) << 8) | (bytes[4] & 0xff);
            sb.append(" magic byte 0, schema id ").append(schemaId).append(',');
            offset = 5;
        }
        sb.append(" 0x");
        for (int i = offset; i < Math.min(bytes.length, offset + MAX_BYTES); i++) {
            sb.append(String.format("%02x", bytes[i]));
        }
        if (bytes.length > offset + MAX_BYTES) {
            sb.append("…");
        }
    }

    private static void element(StringBuilder sb, Object value, int max, int depth) {
        if (depth >= 2) {
            sb.append(value == null ? "null" : value.getClass().getSimpleName() + "@…");
        } else {
            append(sb, value, max, depth + 1);
        }
    }
}
