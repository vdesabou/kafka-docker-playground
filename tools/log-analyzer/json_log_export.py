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
  - the logs of a fully managed connector, confluent connect logs: --output-file ({"Timestamp", "Level", "TaskId",
    "Message", "Exception"}, keys of any case) and -o json ({"timestamp", "level", "task_id", "message", "exception":
    {"stacktrace"}}); with PG_LOG_CONNECTOR_NAME, each line gets the context of the connector logs, [<name>|task-0]
    (its task) or [<name>|worker], so that the report ties it to the connector
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
# _time: Splunk (its CSV exports are newest first: the time decides the order)
TIME_KEYS = ("@timestamp", "timestamp", "time", "ts", "@t", "date", "eventTime", "_time")
LEVEL_KEYS = ("level", "log.level", "severity", "loglevel", "@l")
LOGGER_KEYS = ("logger_name", "logger", "loggerName", "log.logger", "class")
STACK_KEYS = ("stack_trace", "exception", "error.stack_trace", "stacktrace", "throwable")
# the task of an event of a fully managed connector (confluent connect logs): "task-0", or none for the connector itself
TASK_KEYS = ("task_id", "taskId")
# [connector|task-0] / [connector|worker] already in the message: the MDC context of Connect
CONTEXT_RE = re.compile(r"\[[^\s|\]]+\|(?:task-\d+|worker)")


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
                # the JSON log line of the container (a message in it): its fields win; any other JSON (the value of a
                # record in the message column) stays the value of its column, else the row lost its message
                if isinstance(parsed, dict) and get(parsed, MESSAGE_KEYS) is not None:
                    inner.update(parsed)
                    continue
            event[key] = csv_time(value) if key in TIME_KEYS else value
        # the structured JSON log line wins over the columns of the export
        event.update(inner)
        events.append(event)
    return events or None


# the keys of the last event in lower case (get() is called several times per event, on dumps of millions of them)
_LOWER: List[Any] = [None, {}]


def lower_keys(obj: dict) -> dict:
    if _LOWER[0] is not obj:
        _LOWER[0], _LOWER[1] = obj, {key.lower(): key for key in obj if isinstance(key, str)}
    return _LOWER[1]


def get(obj: dict, keys) -> Any:
    for k in keys:
        if k in obj and obj[k] not in (None, ""):
            return obj[k]
        # any case: the --output-file of confluent connect logs writes "Timestamp", "Level", "Message", "TaskId"
        key = lower_keys(obj).get(k.lower())
        if key is not None and obj[key] not in (None, ""):
            return obj[key]
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
        # OpenSearch / Elasticsearch hits with "fields" (arrays of values) instead of _source
        if all(isinstance(e.get("fields"), dict) for e in objs[:50]):
            return [{k: (v[0] if isinstance(v, list) and len(v) == 1 else v) for k, v in e["fields"].items()} for e in objs]
        return objs
    if isinstance(data, dict):
        # Loki query API: {"data": {"result": [{"stream": {labels}, "values": [["<epoch ns>", "<line>"], …]}]}}, all the
        # streams merged in time order, the labels (level, container…) kept with each line
        loki = data.get("data")
        if isinstance(loki, dict) and isinstance(loki.get("result"), list) and \
                all(isinstance(r, dict) and isinstance(r.get("values"), list) for r in loki["result"]):
            rows = []
            for r in loki["result"]:
                labels = r.get("stream") if isinstance(r.get("stream"), dict) else {}
                for v in r["values"]:
                    if isinstance(v, list) and len(v) >= 2:
                        rows.append(dict(labels, timestamp=v[0], message=v[1]))
            rows.sort(key=lambda row: int(row["timestamp"]) if str(row["timestamp"]).isdigit() else 0)
            return rows or None
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
    if isinstance(ts, str) and re.fullmatch(r"\d+(?:\.\d+)?", ts):
        ts = float(ts) if "." in ts else int(ts)
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


# a time of day near the start of a message: 19:02:34
TIME_NEAR_START = re.compile(r"\d{2}:\d{2}:\d{2}")


def looks_like_log_line(message: str) -> bool:
    """a message that already carries its timestamp and level (log4j layout of Kafka, Connect, CP). A level word alone
    is not enough: "Task failed: WARN threshold reached" of a logback JSON event with "level":"ERROR" lost its level, its
    logger and its stack trace"""
    head = message[:60]
    return bool(TIME_NEAR_START.search(head)) and any(
        f" {lvl} " in head or head.startswith((f"{lvl} ", f"[{lvl}]")) for lvl in
        ("ERROR", "WARN", "INFO", "DEBUG", "TRACE", "FATAL", "WARNING", "SEVERE"))


# numeric levels: pino / bunyan (10 trace … 60 fatal), syslog / GELF (0 emergency … 7 debug)
PINO_LEVELS = {10: "TRACE", 20: "DEBUG", 30: "INFO", 40: "WARN", 50: "ERROR", 60: "FATAL"}
SYSLOG_LEVELS = {0: "FATAL", 1: "FATAL", 2: "FATAL", 3: "ERROR", 4: "WARN", 5: "INFO", 6: "INFO", 7: "DEBUG"}


def level_name(level: Any) -> Any:
    """a numeric level as its name ({"level":50} of pino is an ERROR), anything else as it is"""
    if isinstance(level, str) and level.isdigit():
        level = int(level)
    if isinstance(level, int) and not isinstance(level, bool):
        if level in SYSLOG_LEVELS:
            return SYSLOG_LEVELS[level]
        return PINO_LEVELS.get(min(PINO_LEVELS, key=lambda k: abs(k - level))) if level >= 10 else None
    return level


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
    level = level_name(get(event, LEVEL_KEYS))
    ts = iso_ts(ts)
    stack = get(event, STACK_KEYS)
    if isinstance(stack, dict):
        stack = stack.get("stack_trace") or stack.get("stacktrace") or stack.get("message")
    if not (isinstance(level, str) and not looks_like_log_line(message)) and ts is not None \
            and not TS_NEAR_START.match(message):
        # a message without its time (the second part of a line split by docker at 16 KB, a GC log line with the JVM
        # uptime, a plain message): the time of the event in front, for the period and the order of the digest
        message = f"[{ts}] {message}"
        # the stack trace of an event without level ({"message": "boom", "stack_trace": "java.lang.X…"})
        if isinstance(stack, str) and stack.strip() and stack.strip() not in message:
            message += "\n" + stack.rstrip("\n")
    elif isinstance(level, str) and not looks_like_log_line(message):
        level = level.upper()
        level = {"WARNING": "WARN", "CRITICAL": "FATAL", "SEVERE": "ERROR"}.get(level, level)
        logger = get(event, LOGGER_KEYS)
        message = connector_context(event) + message
        line = f"[{ts}] {level} {message}" if ts is not None else f"{level} {message}"
        if isinstance(logger, str):
            line += f" ({logger})"
        message = line
        if isinstance(stack, str) and stack.strip():
            message += "\n" + stack.rstrip("\n")
    return ts, message.split("\n")


def connector_context(event: dict) -> str:
    """the [<connector>|task-0] / [<connector>|worker] context of an event of a fully managed connector, when
    PG_LOG_CONNECTOR_NAME names it (playground connector logs) and the message has none"""
    name = os.environ.get("PG_LOG_CONNECTOR_NAME", "")
    if not name:
        return ""
    message = get(event, MESSAGE_KEYS)
    if isinstance(message, str) and CONTEXT_RE.search(message[:300]):
        return ""
    task = get(event, TASK_KEYS)
    if isinstance(task, int) or (isinstance(task, str) and task.isdigit()):
        task = f"task-{task}"
    return f"[{name}|{task}] " if isinstance(task, str) and re.match(r"^task-\d+$", task) else f"[{name}|worker] "


def sortable(ts: Any) -> Any:
    """a value to compare the first and last times of an export (newest first: reversed). A time with an offset is
    compared in UTC (21:00:00+02:00 is before 19:30:00Z): as a string, the export was reversed"""
    if isinstance(ts, (int, float)):
        return float(ts)
    if ts is None:
        return None
    text = str(ts)
    if re.search(r"(?:Z|[+-]\d\d:?\d\d)$", text):
        try:
            return datetime.fromisoformat(re.sub(r"Z$", "+00:00", text.replace(" ", "T", 1))).timestamp()
        except ValueError:
            pass
    return text


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
    nb = write_events(events_of(data), sys.argv[2])
    if not nb:
        return 2
    print(nb)
    return 0


def write_events(events: Optional[List[dict]], out_path: str) -> int:
    """the log events as log lines, oldest first, in out_path: their number, 0 when they are not log events (most of
    them without a message). Also used by office_export.py for the sheet of an Excel export"""
    if not events:
        return 0
    converted = [to_lines(e) for e in events]
    # a log export: most events have a message
    with_message = [c for c in converted if c[1]]
    if len(with_message) < max(1, len(converted) // 2):
        return 0
    # newest first (console exports): reverse, which keeps the lines of a same millisecond in their order
    first, last = sortable(with_message[0][0]), sortable(with_message[-1][0])
    if first is not None and last is not None and type(first) is type(last) and first > last:
        with_message.reverse()
    with open(out_path, "w", encoding="utf-8") as out:
        for _, lines in with_message:
            for line in lines:
                out.write(line + "\n")
    return len(with_message)


if __name__ == "__main__":
    sys.exit(main())
