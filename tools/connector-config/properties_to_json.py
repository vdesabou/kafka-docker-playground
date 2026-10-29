#!/usr/bin/env python3
"""
Java .properties file (a connect-standalone connector file) to a flat JSON object, for playground connector
create-or-update / validate / diff / convert (normalize_connector_config in scripts/cli/src/lib/cli_function.sh).

Follows the rules of java.util.Properties.load, which is how Kafka Connect reads the file:
  - comment lines start with # or ! (after optional whitespace), blank lines are ignored
  - the key ends at the first unescaped =, : or whitespace; whitespace around the separator is skipped
  - a line ending with an odd number of backslashes continues on the next line (its leading whitespace dropped)
  - escapes: \\t \\n \\r \\f, \\uXXXX, and a backslash before any other character keeps that character
    (so a regex written transforms.r.regex=(.*)\\\\.public gives (.*)\\.public)

Keys keep their order and their dots: transforms=route next to transforms.route.type=... are two keys
(yq -p props nests dotted keys and drops one of them). A key given twice keeps the last value, like Java.

Usage: properties_to_json.py [file]   (stdin when no file)
"""
import json
import sys


def logical_lines(text):
    """Physical lines joined on line continuations, comments and blank lines removed."""
    lines = text.splitlines()
    i = 0
    while i < len(lines):
        line = lines[i].lstrip(" \t\f")
        i += 1
        if not line or line[0] in "#!":
            continue
        # a line ending with an odd number of backslashes continues on the next one
        while True:
            trailing = len(line) - len(line.rstrip("\\"))
            if trailing % 2 == 1 and i < len(lines):
                line = line[:-1] + lines[i].lstrip(" \t\f")
                i += 1
            else:
                if trailing % 2 == 1:
                    line = line[:-1]
                break
        yield line


def unescape(value):
    out = []
    i = 0
    while i < len(value):
        c = value[i]
        if c == "\\" and i + 1 < len(value):
            n = value[i + 1]
            hex_digits = value[i + 2:i + 6]
            if n == "u" and len(hex_digits) == 4 and all(ch in "0123456789abcdefABCDEF" for ch in hex_digits):
                out.append(chr(int(value[i + 2:i + 6], 16)))
                i += 6
                continue
            out.append({"t": "\t", "n": "\n", "r": "\r", "f": "\f"}.get(n, n))
            i += 2
            continue
        out.append(c)
        i += 1
    return "".join(out)


def split_key_value(line):
    """Key and value of a logical line, still escaped."""
    i = 0
    while i < len(line):
        c = line[i]
        if c == "\\":
            i += 2
            continue
        if c in "=: \t\f":
            break
        i += 1
    key = line[:i]
    rest = line[i:].lstrip(" \t\f")
    # one = or : separator, after optional whitespace
    if rest[:1] in ("=", ":") and (i == len(line) or line[i] in " \t\f=:"):
        rest = rest[1:].lstrip(" \t\f")
    return key, rest


def parse(text):
    result = {}
    for line in logical_lines(text):
        key, value = split_key_value(line)
        result[unescape(key)] = unescape(value)
    return result


def main():
    if len(sys.argv) > 1:
        with open(sys.argv[1], encoding="utf-8") as f:
            text = f.read()
    else:
        text = sys.stdin.read()
    json.dump(parse(text), sys.stdout, indent=2, ensure_ascii=False)
    sys.stdout.write("\n")


if __name__ == "__main__":
    main()
