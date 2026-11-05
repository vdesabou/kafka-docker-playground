#!/usr/bin/env python3
"""Turn a JSON export of log events back into plain log lines, for playground analyze logs.

Exports recognized (a JSON array, JSON lines, or one object wrapping the events; .gz accepted):
  - AWS CloudWatch Logs Insights console export: [{"@timestamp": ..., "@message": ...}]
  - CloudWatch Logs Insights API (get-query-results): {"results": [[{"field": "@message", "value": ...}]]}
  - CloudWatch filter-log-events / get-log-events: {"events": [{"timestamp": <ms>, "message": ...}]}
  - Elasticsearch / OpenSearch hits: {"hits": {"hits": [{"_source": {"message": ...}}]}}, or a list of _source
  - Kubernetes / fluentd / Loki style events: {"log": ...}, {"msg": ...}, {"line": ...}
  - structured JSON logs (logback / log4j2 JSON layout, ECS): {"@timestamp", "level", "logger_name", "message",
    "stack_trace"} become "[<ts>] <LEVEL> <message> (<logger>)" followed by the stack trace

Events are written oldest first (exports of the console are newest first), a multi-line message stays multi-line.

usage: json_log_export.py <input> <output>
exit 0: converted (output written), 2: not a JSON export of log events, 1: error
"""
import gzip
import json
import sys
from typing import Any, List, Optional, Tuple

MESSAGE_KEYS = ("@message", "message", "log", "msg", "line", "textPayload", "_raw")
TIME_KEYS = ("@timestamp", "timestamp", "time", "ts", "@t", "date", "eventTime")
LEVEL_KEYS = ("level", "log.level", "severity", "loglevel", "@l")
LOGGER_KEYS = ("logger_name", "logger", "loggerName", "log.logger", "class")
STACK_KEYS = ("stack_trace", "exception", "error.stack_trace", "stacktrace", "throwable")


def load(path: str) -> Any:
    opener = gzip.open if path.endswith(".gz") else open
    with opener(path, "rt", encoding="utf-8", errors="replace") as fh:
        text = fh.read()
    text = text.lstrip("﻿")
    try:
        return json.loads(text)
    except ValueError:
        pass
    # JSON lines
    events = []
    for line in text.splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            events.append(json.loads(line))
        except ValueError:
            return None
    return events or None


def get(obj: dict, keys) -> Any:
    for k in keys:
        if k in obj and obj[k] not in (None, ""):
            return obj[k]
        # dotted keys of ECS: {"log": {"level": ...}}
        if "." in k:
            cur: Any = obj
            for part in k.split("."):
                cur = cur.get(part) if isinstance(cur, dict) else None
            if cur not in (None, ""):
                return cur
    return None


def events_of(data: Any) -> Optional[List[dict]]:
    if isinstance(data, list):
        # Logs Insights API results: a list of rows, each a list of {field, value}
        if data and all(isinstance(r, list) for r in data[:50]):
            rows = []
            for r in data:
                row = {c.get("field"): c.get("value") for c in r if isinstance(c, dict)}
                rows.append(row)
            return rows
        objs = [e for e in data if isinstance(e, dict)]
        if not objs:
            return None
        # Elasticsearch hits
        if all("_source" in e for e in objs[:50]):
            return [dict(e["_source"]) if isinstance(e["_source"], dict) else {} for e in objs]
        return objs
    if isinstance(data, dict):
        for key in ("results", "events", "logEvents", "records", "data", "logs", "entries"):
            if isinstance(data.get(key), list):
                return events_of(data[key])
        hits = data.get("hits")
        if isinstance(hits, dict) and isinstance(hits.get("hits"), list):
            return events_of(hits["hits"])
    return None


def looks_like_log_line(message: str) -> bool:
    """a message that already carries its timestamp and level (log4j layout of Kafka, Connect, CP)"""
    head = message[:60]
    return any(f" {lvl} " in head or head.startswith(f"{lvl} ") for lvl in
               ("ERROR", "WARN", "INFO", "DEBUG", "TRACE", "FATAL", "WARNING", "SEVERE"))


def to_lines(event: dict) -> Tuple[Any, List[str]]:
    message = get(event, MESSAGE_KEYS)
    ts = get(event, TIME_KEYS)
    if message is None:
        return ts, []
    if not isinstance(message, str):
        message = json.dumps(message)
    message = message.rstrip("\n")
    level = get(event, LEVEL_KEYS)
    if isinstance(level, str) and not looks_like_log_line(message):
        level = level.upper()
        level = {"WARNING": "WARN", "CRITICAL": "FATAL", "SEVERE": "ERROR"}.get(level, level)
        logger = get(event, LOGGER_KEYS)
        line = f"[{ts}] {level} {message}" if ts is not None else f"{level} {message}"
        if isinstance(logger, str):
            line += f" ({logger})"
        message = line
        stack = get(event, STACK_KEYS)
        if isinstance(stack, dict):
            stack = stack.get("stack_trace") or stack.get("message")
        if isinstance(stack, str) and stack.strip():
            message += "\n" + stack.rstrip("\n")
    return ts, message.split("\n")


def sortable(ts: Any) -> Any:
    if isinstance(ts, (int, float)):
        return float(ts)
    return str(ts) if ts is not None else None


def main() -> int:
    if len(sys.argv) != 3:
        print(__doc__, file=sys.stderr)
        return 1
    try:
        data = load(sys.argv[1])
    except (OSError, EOFError, UnicodeError) as e:
        print(f"cannot read {sys.argv[1]}: {e}", file=sys.stderr)
        return 1
    events = events_of(data)
    if not events:
        return 2
    converted = [to_lines(e) for e in events]
    # a log export: most events have a message
    with_message = [c for c in converted if c[1]]
    if len(with_message) < max(1, len(converted) // 2):
        return 2
    # newest first (console exports): reverse, which keeps the lines of a same millisecond in their order
    first, last = sortable(with_message[0][0]), sortable(with_message[-1][0])
    if first is not None and last is not None and type(first) is type(last) and first > last:
        with_message.reverse()
    with open(sys.argv[2], "w", encoding="utf-8") as out:
        for _, lines in with_message:
            for line in lines:
                out.write(line + "\n")
    print(len(with_message))
    return 0


if __name__ == "__main__":
    sys.exit(main())
