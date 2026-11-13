#!/usr/bin/env python3
"""Overview of logs without findings, for playground analyze logs.

When no file has an ERROR/FATAL (or WARN) record, "no record found" alone does not say whether the logs are healthy or
just the wrong ones. This says what they contain and what to ask for next:
  - each file: lines, period covered (first and last timestamps found by the digest), records by level
  - the most frequent messages, masked (numbers, identifiers), and the most frequent loggers
  - hints: a period shorter than 10 min, only INFO/DEBUG records, an export of a log console (cut at its size limit)

usage: log_overview.py --records <records file> --sources <label<tab>path…> [--exports <label<tab>format<tab>events>]
                       [--levels ERROR/FATAL] [--top 10] [--json]
"""
import argparse
import gzip
import json
import os
import re
import sys
from collections import Counter, OrderedDict
from typing import Dict, List, Optional

# no __pycache__ next to the tools of the repository
sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import log_report as lr  # noqa: E402

LEVELS = ("FATAL", "ERROR", "WARN", "INFO", "DEBUG", "TRACE")
LEVEL_ALIASES = {"WARNING": "WARN", "SEVERE": "ERROR", "CRITICAL": "FATAL", "FINE": "DEBUG", "FINER": "TRACE",
                 "FINEST": "TRACE", "CONFIG": "INFO"}
# the level token of a log line, in its first 80 characters: log4j / logback / the JSON exports converted back
LEVEL_RE = re.compile(r"(?:^|[\s\[|])(FATAL|ERROR|WARN|WARNING|INFO|DEBUG|TRACE|SEVERE|CRITICAL)(?=[\s\]|:])")
# the lower case levels: logfmt level=error, JSON "level":"error", zap / logrus after the time (… 10:00:05 error …), the
# .NET console logger (fail:), klog of Kubernetes and the CFK operator (E1014 10:00:05.123 …)
LOWER_LEVEL_RE = re.compile(r"(?:^|[\s{,])\"?level\"?\s*[=:]\s*\"?(fatal|error|warn|warning|info|debug|trace)\b"
                            r"|^\S*\d{2}:\d{2}:\d{2}\S*\s+\[?(fatal|error|warn|warning|info|debug|trace)\b"
                            r"|^(crit|fail|warn|info|dbug|trce):", re.IGNORECASE)
KLOG_RE = re.compile(r"^([IWEF])\d{4} \d{2}:\d{2}:\d{2}")
KLOG_LEVELS = {"I": "INFO", "W": "WARN", "E": "ERROR", "F": "FATAL"}
DOTNET_LEVELS = {"crit": "FATAL", "fail": "ERROR", "warn": "WARN", "info": "INFO", "dbug": "DEBUG", "trce": "TRACE"}
# a line that starts with its own time: a new record even without a level, not the next line of a multi-line message
STARTS_WITH_TIME_RE = re.compile(r"^\[?(?:\d{4}[-/]\d{2}[-/]\d{2}[ T]\d{2}:\d{2}|\d{2}:\d{2}:\d{2}|[A-Z][a-z]{2} [ \d]\d \d{2}:)")
# JVM unified logging (GC logs): [57686.021s][info][gc,heap     ] GC(13392) …
# (after the time of the event, put in front by json_log_export.py: "[2026-10-14T19:13:28.410] [57686.021s][info]…")
JVM_RE = re.compile(r"^(?:\[[^\]]*\] )?\[[^\]]*\](?:\[[^\]]*\])*?\[(error|warning|info|debug|trace)\s*\]\[([a-z0-9_, ]+?)\s*\]\s*(.*)$")
# the logger at the end of a line: "(org.apache.kafka.connect.runtime.WorkerTask:123)" or " (com.example.Foo)"
LOGGER_RE = re.compile(r"\s\(([A-Za-z_$][\w$]*(?:\.[\w$]+)+)(?::\d+)?\)$")
# the logger after the level / thread of logback / log4j: "INFO  c.e.Foo - message", "INFO [thread] o.a.k.Foo: message"
LOGGER_PREFIX_RE = re.compile(r"^(?:\[[^\]]*\]\s*)?([a-zA-Z_$][\w$]*(?:\.[\w$]+){2,})\s*(?:-|:)\s+")
UUID_RE = re.compile(r"\b[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\b")
HEX_RE = re.compile(r"\b(?=[0-9a-fA-F]*[0-9])(?=[0-9a-fA-F]*[a-fA-F])[0-9a-fA-F]{8,}\b")
# a number on its own, not the digit of a name (s3-sink, log4j, c027)
NUM_RE = re.compile(r"(?<![A-Za-z0-9])\d+")
MAX_PATTERN = 160


# distinct messages kept while reading: past it, the ones seen once are dropped (multi-GB logs with ids that mask() does
# not catch made millions of keys, an example of 400 characters and a set each)
MAX_PATTERNS = 50000


def prune(patterns: Counter, *side: dict) -> None:
    """drops the rarest messages (the top messages are the frequent ones) from the counts and their side maps: seen once,
    then twice… until half of MAX_PATTERNS is left, so that the next prune comes MAX_PATTERNS / 2 new messages later"""
    seen = 1
    while len(patterns) > MAX_PATTERNS // 2:
        for key in [k for k, c in patterns.items() if c <= seen]:
            del patterns[key]
            for d in side:
                d.pop(key, None)
        seen *= 2

def open_text(path: str):
    if path.endswith(".gz"):
        return gzip.open(path, "rt", encoding="utf-8", errors="replace")
    return open(path, encoding="utf-8", errors="replace")


def mask(message: str) -> str:
    message = UUID_RE.sub("<uuid>", message)
    message = re.sub(r"\b0x[0-9a-fA-F]+\b", "<hex>", message)
    message = HEX_RE.sub("<hex>", message)
    message = NUM_RE.sub("N", message)
    message = re.sub(r"\s+", " ", message).strip()
    return message[:MAX_PATTERN] + ("…" if len(message) > MAX_PATTERN else "")


def parse_line(line: str):
    """(level, logger, message) of the first line of a record, None for a continuation line"""
    if not line.strip() or line[0] in " \t" or line.startswith("Caused by:"):
        return None
    m = JVM_RE.match(line)
    if m:
        level = LEVEL_ALIASES.get(m.group(1).upper(), m.group(1).upper())
        return level, "jvm " + m.group(2).replace(" ", ""), m.group(3)
    m = LEVEL_RE.search(line[:80])
    if not m:
        k = KLOG_RE.match(line)
        if k:
            return KLOG_LEVELS[k.group(1)], "", line[k.end():].lstrip(" .0123456789")
        lm = LOWER_LEVEL_RE.search(line[:120])
        if not lm:
            return "", "", line
        word = next(g for g in lm.groups() if g).lower()
        level = DOTNET_LEVELS.get(word) or LEVEL_ALIASES.get(word.upper(), word.upper())
        return level, "", line[lm.end():].lstrip(" ]|:\"")
    level = LEVEL_ALIASES.get(m.group(1), m.group(1))
    message = line[m.end():].lstrip(" ]|:")
    logger = ""
    lm = LOGGER_RE.search(message)
    if lm:
        logger = lm.group(1)
        message = message[:lm.start()]
    else:
        pm = LOGGER_PREFIX_RE.match(message)
        if pm:
            logger = pm.group(1)
            message = message[pm.end():]
    return level, logger, message


# librdkafka: "%3|1793896102.923|FAIL|rdkafka#producer-1| …", its level is the syslog number after the %
LIBRDKAFKA_RE = re.compile(r"^%\d\|\d+(?:\.\d+)?\|")
# how much of a file is read to find a line with a level: the head of a log has some
LEVEL_SNIFF_BYTES = 4 * 1024 * 1024


def has_level(path: str, max_bytes: int = LEVEL_SNIFF_BYTES) -> bool:
    """a line with a log level in the head of the file: a log of Kafka, Connect, a client, the CFK operator… (a capture of
    host commands, a table of kubectl, a GC log decorated with the uptime only have none)"""
    read = 0
    try:
        with open_text(path) as fh:
            for line in fh:
                read += len(line)
                if LIBRDKAFKA_RE.match(line):
                    return True
                parsed = parse_line(line.rstrip("\n"))
                if parsed and parsed[0]:
                    return True
                if read >= max_bytes:
                    break
    except (OSError, EOFError, gzip.BadGzipFile):
        return True
    return False


def unleveled(sources: str) -> List[str]:
    """the labels of the files analyzed (label<tab>path…) without any line with a log level: not logs"""
    out: List[str] = []
    seen = set()
    with open(sources, encoding="utf-8", errors="replace") as fh:
        for line in fh:
            parts = line.rstrip("\n").split("\t")
            if len(parts) < 2 or parts[0] in seen:
                continue
            seen.add(parts[0])
            if os.path.isfile(parts[1]) and not has_level(parts[1]):
                out.append(parts[0])
    return out


def overview(records: str, sources: str, exports: Optional[str], top: int) -> dict:
    periods: Dict[str, tuple] = {}
    with open(records, encoding="utf-8", errors="replace") as fh:
        for line in fh:
            if line.startswith("@@PGFILE@@\t"):
                parts = line.rstrip("\n").split("\t")
                if len(parts) >= 7:
                    periods[parts[1]] = (int(parts[2] or 0), parts[5] or None, parts[6] or None)
    # the offsets of the timestamps (2026-10-13T10:00:05+02:00): stripped, or converted to UTC when the files mix several,
    # as in the log report (log_report.normalize_times)
    stub = [{"label": k, "log_first_ts": v[1], "log_last_ts": v[2], "records": [], "configs": []} for k, v in periods.items()]
    lr.normalize_times(stub)
    periods = {f["label"]: (periods[f["label"]][0], f["log_first_ts"], f["log_last_ts"]) for f in stub}
    export_of: Dict[str, tuple] = {}
    if exports and os.path.isfile(exports):
        with open(exports, encoding="utf-8") as fh:
            for line in fh:
                parts = line.rstrip("\n").split("\t")
                if len(parts) >= 3:
                    export_of[parts[0]] = (parts[1], int(parts[2] or 0))
    files: List[dict] = []
    patterns: Counter = Counter()
    pattern_level: Dict[str, Counter] = {}
    pattern_example: Dict[str, str] = {}
    pattern_files: Dict[str, set] = {}
    loggers: Counter = Counter()
    seen = set()
    with open(sources, encoding="utf-8", errors="replace") as fh:
        for src in fh:
            parts = src.rstrip("\n").split("\t")
            if len(parts) < 2 or parts[0] in seen or not os.path.isfile(parts[1]):
                continue
            label, path = parts[0], parts[1]
            seen.add(label)
            levels: Counter = Counter()
            previous_level = ""
            try:
                with open_text(path) as lf:
                    for raw in lf:
                        parsed = parse_line(raw.rstrip("\r\n"))
                        if parsed is None:
                            continue
                        level, logger, message = parsed
                        # a line without level after a record with one: the next line of a multi-line message, unless
                        # it starts with its own time (a new record without level: every later line was skipped)
                        if not level and previous_level and not STARTS_WITH_TIME_RE.match(raw):
                            continue
                        previous_level = level
                        levels[level or "no level"] += 1
                        key = mask(message)
                        if not key:
                            continue
                        patterns[key] += 1
                        pattern_level.setdefault(key, Counter())[level or "no level"] += 1
                        pattern_example.setdefault(key, message.strip()[:400])
                        pattern_files.setdefault(key, set()).add(label)
                        if len(patterns) > MAX_PATTERNS:
                            prune(patterns, pattern_level, pattern_example, pattern_files)
                        if logger:
                            loggers[logger] += 1
            except OSError:
                continue
            nb_lines, first, last = periods.get(label, (0, None, None))
            entry = OrderedDict(label=label, lines=nb_lines, first_timestamp=first, last_timestamp=last,
                                duration_seconds=lr.duration_seconds(first, last),
                                levels=OrderedDict(sorted(levels.items(),
                                                          key=lambda kv: (list(LEVELS) + ["no level"]).index(kv[0])
                                                          if kv[0] in LEVELS or kv[0] == "no level" else 99)))
            if label in export_of:
                entry["export"] = OrderedDict(format=export_of[label][0], events=export_of[label][1])
            files.append(entry)
    top_messages = [OrderedDict(count=c, level=pattern_level[p].most_common(1)[0][0], pattern=p,
                                example=pattern_example[p], files=len(pattern_files[p]))
                    for p, c in patterns.most_common(top)]
    top_loggers = [OrderedDict(count=c, logger=lg) for lg, c in loggers.most_common(5)]
    return OrderedDict(files=files, top_messages=top_messages, top_loggers=top_loggers, hints=hints(files))


def hints(files: List[dict]) -> List[str]:
    out: List[str] = []
    short = [f for f in files if f["duration_seconds"] is not None and f["duration_seconds"] < lr.SHORT_PERIOD_SECONDS]
    if short:
        names = ", ".join(os.path.basename(f["label"]) for f in short[:3]) + (" …" if len(short) > 3 else "")
        out.append(f"🕐 {names}: shorter than {lr.human_duration(lr.SHORT_PERIOD_SECONDS)} of logs. Ask for the whole "
                   "incident window, from before the problem started to after it ended")
    if files and all(f["first_timestamp"] is None for f in files):
        out.append("🕐 no timestamp found: the period covered is unknown, check that these are the logs of the incident")
    levels: Counter = Counter()
    for f in files:
        levels.update(f["levels"])
    if levels and not any(levels.get(lv) for lv in ("FATAL", "ERROR", "WARN")):
        found = ", ".join(lv for lv in levels if levels[lv] and lv != "no level") or "unleveled"
        out.append(f"🔇 only {found} records: the logs (or the export) may be filtered on a level or a component, or "
                   "the problem is not logged here. Ask for the logs of the component that fails, at INFO or more")
    exports = [f for f in files if f.get("export")]
    if exports:
        fmt = "/".join(sorted({f["export"]["format"] for f in exports}))
        out.append(f"📤 {fmt} export of a log console: Kibana / OpenSearch Dashboards Discover exports the newest rows "
                   "first and stops at a size limit (xpack.reporting.csv.maxSizeBytes), CloudWatch Logs Insights at "
                   "10,000 rows. Export the incident window with a query on the problems, e.g. "
                   "log: *ERROR* or log: *WARN* or log: *Exception*")
    return out


def text(res: dict, levels: str) -> str:
    lines = [f"🔭 Overview: no {levels} record, what the logs contain"]
    for f in res["files"]:
        period = ""
        if f["first_timestamp"]:
            period = f", {lr.period_text(f['first_timestamp'], f['last_timestamp'])} " \
                     f"({lr.human_duration(f['duration_seconds'])})"
        export = f", {f['export']['format']} export of {f['export']['events']} events" if f.get("export") else ""
        lines.append(f"   📄 {f['label']}: {f['lines']} lines{period}{export}")
        if f["levels"]:
            lines.append("      " + " · ".join(f"{lv} {n}" for lv, n in f["levels"].items()))
    if res["top_messages"]:
        lines.append("   🔝 Top messages (N: a number, <hex> / <uuid>: an identifier)")
        for m in res["top_messages"]:
            lines.append(f"      {m['count']:>6}× {m['level'] or '-':<5} {m['pattern']}")
    if res["top_loggers"]:
        lines.append("   🏷️ Top loggers")
        for lg in res["top_loggers"]:
            lines.append(f"      {lg['count']:>6}× {lg['logger']}")
    if res["hints"]:
        lines.append("   👉 What to ask for next")
        for h in res["hints"]:
            lines.append(f"      {h}")
    return "\n".join(lines)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--records", help="records file of summarize_log_errors (@@PGFILE@@ lines)")
    ap.add_argument("--unleveled", action="store_true", help="only print the labels of the --sources without any line "
                    "with a log level (not logs: host captures, command outputs), one per line")
    ap.add_argument("--sources", required=True, help="label<tab>path of each file analyzed")
    ap.add_argument("--exports", help="label<tab>format<tab>events of the JSON / CSV exports converted")
    ap.add_argument("--levels", default="ERROR/FATAL", help="levels of the digest, for the title")
    ap.add_argument("--top", type=int, default=10, help="number of messages")
    ap.add_argument("--json", action="store_true", help="print the overview as JSON")
    ap.add_argument("--json-out", metavar="FILE", help="also write the JSON there (one pass for the text and the JSON)")
    args = ap.parse_args()
    if args.unleveled:
        for label in unleveled(args.sources):
            print(label)
        return 0
    if not args.records:
        ap.error("--records is required")
    res = overview(args.records, args.sources, args.exports, args.top)
    if args.json_out:
        with open(args.json_out, "w", encoding="utf-8") as fh:
            json.dump(res, fh, indent=2, ensure_ascii=False)
    if args.json:
        print(json.dumps(res, indent=2, ensure_ascii=False))
    else:
        print(text(res, args.levels))
    return 0


if __name__ == "__main__":
    sys.exit(main())
