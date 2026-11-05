#!/usr/bin/env python3
"""Turn a JSON or CSV export of log events back into plain log lines, for playground analyze logs.

Exports recognized (a JSON array, JSON lines, or one object wrapping the events; .gz accepted):
  - AWS CloudWatch Logs Insights console export: [{"@timestamp": ..., "@message": ...}]
  - CloudWatch Logs Insights API (get-query-results): {"results": [[{"field": "@message", "value": ...}]]}
  - CloudWatch filter-log-events / get-log-events: {"events": [{"timestamp": <ms>, "message": ...}]}
  - Elasticsearch / OpenSearch hits: {"hits": {"hits": [{"_source": {"message": ...}}]}}, or a list of _source
  - Kubernetes / fluentd / Loki style events: {"log": ...}, {"msg": ...}, {"line": ...}
  - structured JSON logs (logback / log4j2 JSON layout, ECS): {"@timestamp", "level", "logger_name", "message",
    "stack_trace"} become "[<ts>] <LEVEL> <message> (<logger>)" followed by the stack trace
  - CSV exports (.csv, .csv.gz) with a header row: Kibana / OpenSearch Dashboards Discover ("Share > CSV report",
    "Oct 14, 2026 @ 19:13:28.977" timestamps, "-" for an empty cell), Splunk, Datadog, Grafana / Loki, CloudWatch
    Logs Insights: one event per row, the columns are its fields; a cell holding a JSON object (a "log" or "message"
    column with the structured JSON log line of the container) is parsed and its fields win

JSON lines are streamed one event at a time (a dump of several GB), whatever the extension of the file (.log, .txt):
analyze logs sends the files whose first line is a JSON object here. Events are written oldest first (exports of the console are newest first), a multi-line message stays multi-line.

usage: json_log_export.py <input> <output>
exit 0: converted (output written), 2: not an export of log events, 1: error
"""
import csv
import gzip
import json
import os
import re
import sys
from datetime import datetime, timezone
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


# Kibana / OpenSearch Dashboards Discover: "Oct 14, 2026 @ 19:13:28.977"
KIBANA_TIME = re.compile(r"^([A-Z][a-z]{2} \d{1,2}, \d{4}) @ (\d{2}:\d{2}:\d{2})(\.\d+)?$")


def csv_time(value: str) -> str:
    """the Kibana time of a cell as ISO 8601 (sortable, read by the digest), any other value unchanged"""
    m = KIBANA_TIME.match(value)
    if not m:
        return value
    try:
        day = datetime.strptime(m.group(1), "%b %d, %Y").strftime("%Y-%m-%d")
    except ValueError:
        return value
    return f"{day}T{m.group(2)}{m.group(3) or ''}"


def load_csv(path: str) -> Any:
    opener = gzip.open if path.endswith(".gz") else open
    csv.field_size_limit(sys.maxsize)
    with opener(path, "rt", encoding="utf-8", errors="replace", newline="") as fh:
        text = fh.read().lstrip("\ufeff")
    try:
        dialect = csv.Sniffer().sniff(text[:65536], delimiters=",;\t")
    except csv.Error:
        dialect = csv.excel
    reader = csv.DictReader(text.splitlines(keepends=True), dialect=dialect)
    if not reader.fieldnames or not any(f in MESSAGE_KEYS or f in ("Message", "Line", "_source")
                                        for f in reader.fieldnames):
        return None
    events = []
    for row in reader:
        event: dict = {}
        inner: dict = {}
        for key, value in row.items():
            if key is None or value is None:
                continue
            value = value.strip("\r\n")
            if value in ("", "-"):
                continue
            # Datadog, Splunk and Grafana CSV columns: Date, Message, Line, Level…
            if key in ("Message", "Line", "Date", "Time", "Timestamp", "Level", "Severity", "Logger"):
                key = key.lower()
            if value.startswith("{") and value.endswith("}"):
                try:
                    parsed = json.loads(value)
                except ValueError:
                    parsed = None
                if isinstance(parsed, dict):
                    inner.update(parsed)
                    continue
            event[key] = csv_time(value) if key in TIME_KEYS else value
        # the structured JSON log line wins over the columns of the export
        event.update(inner)
        events.append(event)
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


# a timestamp at the start of a message that carries its own (log4j, logback, GC logs with uptime only do not)
# ("2026-10-14 19:02:34,492 INFO", "[2026-10-14T19:02:34Z] INFO", "[INFO] 2026-10-14 19:02:34", "INFO 2026-10-14…"), not a
# date inside the data ("key CRIMS.123.2026-10-14T00:00:00Z")
TS_NEAR_START = re.compile(r"^\[?(?:[A-Za-z]+\]?\s+\[?)?\d{4}-\d{2}-\d{2}[ T]\d{2}:\d{2}:\d{2}")


def iso_ts(ts: Any) -> Any:
    """epoch seconds / milliseconds / nanoseconds of the CloudWatch and Loki exports as ISO 8601 UTC, anything else as it is"""
    if isinstance(ts, str) and ts.isdigit():
        ts = int(ts)
    if isinstance(ts, (int, float)) and not isinstance(ts, bool):
        seconds = float(ts)
        while seconds > 1e11:
            seconds /= 1000
        try:
            return datetime.fromtimestamp(seconds, timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%f")[:-3] + "Z"
        except (OverflowError, OSError, ValueError):
            return ts
    return ts


# the first line of an exception: org.apache.kafka.common.errors.TimeoutException: …
EXCEPTION_LINE = re.compile(r"^[A-Za-z0-9_$]+(\.[A-Za-z0-9_$]+)+(Exception|Error|Throwable)(:|$)")


def looks_like_log_line(message: str) -> bool:
    """a message that already carries its timestamp and level (log4j layout of Kafka, Connect, CP)"""
    head = message[:60]
    return any(f" {lvl} " in head or head.startswith((f"{lvl} ", f"[{lvl}]")) for lvl in
               ("ERROR", "WARN", "INFO", "DEBUG", "TRACE", "FATAL", "WARNING", "SEVERE"))


def to_lines(event: dict) -> Tuple[Any, List[str]]:
    message = get(event, MESSAGE_KEYS)
    ts = get(event, TIME_KEYS)
    if message is None:
        return ts, []
    if not isinstance(message, str):
        message = json.dumps(message)
    message = message.rstrip("\n")
    # the next lines of a multi-line message, indented: they continue its record in the digest (a line with a
    # date of the data must not start a record or count as a timestamp of the log). Exception lines and
    # "Caused by:" are left as they are, for the cause chain
    if "\n" in message:
        head, *rest = message.split("\n")
        message = "\n".join([head] + [r if not r or r[0] in " \t" or r.startswith("Caused by:") or EXCEPTION_LINE.match(r)
                                       else "    " + r for r in rest])
    level = get(event, LEVEL_KEYS)
    ts = iso_ts(ts)
    if not (isinstance(level, str) and not looks_like_log_line(message)) and ts is not None \
            and not TS_NEAR_START.match(message):
        # a message without its time (the second part of a line split by docker at 16 KB, a GC log line with the JVM
        # uptime, a plain message): the time of the event in front, for the period and the order of the digest
        message = f"[{ts}] {message}"
    elif isinstance(level, str) and not looks_like_log_line(message):
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


def first_object(path: str) -> Optional[dict]:
    """the first line of a JSON lines file, when it is a JSON object (None: anything else, a pretty-printed JSON…)"""
    opener = gzip.open if path.endswith(".gz") else open
    with opener(path, "rb") as fh:
        for raw in fh:
            line = raw.strip().lstrip(b"\xef\xbb\xbf")
            if not line:
                continue
            if not line.startswith(b"{"):
                return None
            try:
                obj = json.loads(line)
            except ValueError:
                return None
            return obj if isinstance(obj, dict) else None
    return None


def stream_json_lines(path: str, out_path: str) -> int:
    """JSON lines (a fluentd / Kubernetes / logstash dump of several GB), converted one event at a time instead of
    loaded in memory. Returns the number of events written, 0 when it is not a log export"""
    try:
        # no __pycache__ next to the tools of the repository
        sys.dont_write_bytecode = True
        sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
        from progress import Progress
    except ImportError:
        Progress = None
    size = None if path.endswith(".gz") else os.path.getsize(path)
    progress = Progress(path, size, f"🔄 converting the JSON lines of {path}") if Progress else None
    opener = gzip.open if path.endswith(".gz") else open
    nb_events = nb_with_message = 0
    first_ts = last_ts = None
    offsets: List[int] = []
    with opener(path, "rb") as fh, open(out_path, "w", encoding="utf-8") as out:
        try:
            for raw in fh:
                if progress:
                    progress.update(len(raw))
                line = raw.strip()
                if not line:
                    continue
                nb_events += 1
                try:
                    event = json.loads(line)
                except ValueError:
                    event = None
                if isinstance(event, dict):
                    ts, lines = to_lines(event)
                else:
                    # a plain line in the dump: kept as it is
                    ts, lines = None, [line.decode("utf-8", "replace")]
                if not lines:
                    continue
                nb_with_message += 1
                if ts is not None:
                    if first_ts is None:
                        first_ts = sortable(ts)
                    last_ts = sortable(ts)
                offsets.append(out.tell())
                out.write("\n".join(lines) + "\n")
        finally:
            if progress:
                progress.close()
    if nb_with_message < max(1, nb_events // 2):
        os.remove(out_path)
        return 0
    # newest first (console exports): the events written again in the other order
    if first_ts is not None and last_ts is not None and type(first_ts) is type(last_ts) and first_ts > last_ts:
        reversed_path = out_path + ".reversed"
        with open(out_path, "rb") as src, open(reversed_path, "wb") as dst:
            end = os.path.getsize(out_path)
            for start in reversed(offsets):
                src.seek(start)
                dst.write(src.read(end - start))
                end = start
        os.replace(reversed_path, out_path)
    return nb_with_message


def main() -> int:
    if len(sys.argv) != 3:
        print(__doc__, file=sys.stderr)
        return 1
    try:
        first = None if sys.argv[1].lower().endswith((".csv", ".csv.gz")) else first_object(sys.argv[1])
        # JSON lines whose first event is a log event: streamed (a dump can be several GB)
        if first is not None and to_lines(first)[1]:
            nb = stream_json_lines(sys.argv[1], sys.argv[2])
            if not nb:
                return 2
            print(nb)
            return 0
        if sys.argv[1].lower().endswith((".csv", ".csv.gz")):
            data = load_csv(sys.argv[1])
        else:
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
