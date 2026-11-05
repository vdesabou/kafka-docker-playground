package io.confluent.playground.streams;

import java.util.regex.Matcher;
import java.util.regex.Pattern;

/** Reads a field of a flat JSON object (the values of the examples), without a JSON library. */
final class Json {

    private Json() {
    }

    static String field(String json, String name) {
        if (json == null) {
            return null;
        }
        Matcher m = Pattern.compile("\"" + Pattern.quote(name) + "\"\\s*:\\s*(\"([^\"]*)\"|(-?[0-9.]+))").matcher(json);
        if (!m.find()) {
            return null;
        }
        return m.group(2) != null ? m.group(2) : m.group(3);
    }
}
