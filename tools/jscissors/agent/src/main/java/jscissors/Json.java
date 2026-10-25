package jscissors;

/** Just enough JSON writing for the events and the summary, without dependency. */
final class Json {
    private Json() {
    }

    static StringBuilder str(StringBuilder sb, String s) {
        if (s == null) {
            return sb.append("null");
        }
        sb.append('"');
        for (int i = 0; i < s.length(); i++) {
            char c = s.charAt(i);
            switch (c) {
                case '"': sb.append("\\\""); break;
                case '\\': sb.append("\\\\"); break;
                case '\n': sb.append("\\n"); break;
                case '\r': sb.append("\\r"); break;
                case '\t': sb.append("\\t"); break;
                default:
                    if (c < 0x20 || (c >= 0xd800 && c <= 0xdfff && !validSurrogate(s, i))) {
                        sb.append(String.format("\\u%04x", (int) c));
                    } else {
                        sb.append(c);
                    }
            }
        }
        return sb.append('"');
    }

    // a lone surrogate (a value cut in the middle of an emoji) is not valid UTF-8
    private static boolean validSurrogate(String s, int i) {
        char c = s.charAt(i);
        if (Character.isHighSurrogate(c)) {
            return i + 1 < s.length() && Character.isLowSurrogate(s.charAt(i + 1));
        }
        return i > 0 && Character.isHighSurrogate(s.charAt(i - 1));
    }

    static StringBuilder field(StringBuilder sb, String key, String value) {
        str(sb.append(','), key).append(':');
        return str(sb, value);
    }

    static StringBuilder field(StringBuilder sb, String key, long value) {
        str(sb.append(','), key).append(':');
        return sb.append(value);
    }
}
