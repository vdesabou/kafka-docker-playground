#!/usr/bin/env python3
"""
HTML report and JSON of the ERROR/FATAL (and WARN) digest of log files, written by playground analyze logs.

The records come from summarize_log_errors (scripts/cli/src/lib/cli_function.sh), the same parser as
playground container logs --errors, run with PG_LOG_DIGEST_RECORDS_FILE set:

  @@PGFILE@@<tab>label<tab>lines<tab>distinct records<tab>occurrences<tab>first timestamp of the file<tab>last one
  @@PGREC@@<tab>level<tab>count<tab>first line<tab>last line<tab>first timestamp<tab>last timestamp
  <the record as printed in the digest, on one or more lines>
  @@PGTS@@<tab>timestamps of the occurrences, space separated
  @@PGCTX@@<tab>raw lines around the first occurrence (2 before, the record, 2 after), one per line
  @@PGCFG@@<tab>config class<tab>[connector|task-0] context ("file" for a config file)<tab>line<tab>timestamp<tab>client.id or name
  @@PGCFGL@@<tab>key=value, one per line
  @@PGCFGCHG@@<tab>line<tab>timestamp<tab>key=previous value<tab>key=new value (a key whose value changed between two
                dumps of the same config: a restart with another config)

Also used by playground get-ci-result --logs, container logs --errors --html and container display-error-all --html,
and imported by tools/connector-diagnose/diagnose_report.py for the errors section of the connector report.
"""

import argparse
import json
import os
import re
import sys
from collections import Counter, OrderedDict
import calendar
from datetime import datetime, timedelta, timezone
from typing import Dict, List, Optional, Sequence, Tuple
from urllib.parse import quote

# no __pycache__ left in the repository
sys.dont_write_bytecode = True
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "report-common"))
from report_html import (SERIES_1, SERIES_2, SEVERITY_ORDER, badge, card, charts_grid, e, findings_html, log_html,  # noqa: E402
                         kpi, kpis_html, page, svg_hbars, time_chart, verdict_html, dark)
import known_causes  # noqa: E402
import log_viewer  # noqa: E402
from known_causes import KILLED_TASK_TITLE  # noqa: E402

LEVEL_ORDER = {"FATAL": 0, "ERROR": 1, "WARN": 2}

# well-known causes: (regex on the record, severity, title, what to do), shared with the CFK analyzer
# (tools/report-common/known_causes.py)
HINTS = known_causes.hints()

# an exception line of the chain: Java (org.x.FooException, after "Caused by:"), .NET (Confluent.Kafka.ProduceException`2[…],
# after " ---> " for an inner exception), Python (ValueError, cimpl.KafkaException), Node.js (KafkaJSConnectionError, after
# "[cause]:")
EXCEPTION_RE = re.compile(r"^(?:(?:Caused by:|--->|\[cause\]:)\s*)?((?:[a-zA-Z_$][\w$]*\.)*[A-Z][\w$]*(?:Exception|Error|Throwable)"
                          r"(?:`\d+\[[^\]]*\])?)(?::\s*(.*))?$")
# connector of a record: the [connector|task-0] / [connector|worker] MDC context of Connect, with an optional scope
# ([connector|task-0|offsets], Oracle CDC [connector|task-0|redoLog]), or the id of the task
CONNECTOR_RE = re.compile(r"\[([^\s|\]]+)\|(?:task-\d+|worker)(?:\|[^\s|\]]+)?\]|Worker(?:Source|Sink)Task\{id=(\S+)-\d+\}")


TS_FORMAT = "%Y-%m-%dT%H:%M:%S"
# a timestamp of the digest with the offset written in the log (2026-10-13T10:00:05+02:00, Z written +00:00)
_OFFSET_TS_RE = re.compile(r"^(\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d)([+-])(\d\d):(\d\d)$")


def epoch(ts: str) -> int:
    """a timestamp of the digest (wall clock time, as written in the logs) as a UTC epoch: never shifted by the time zone
    of the machine or by a DST change; zoom_chart.js and pgStamp() show it back with the UTC fields"""
    return calendar.timegm(datetime.strptime(ts[:19], TS_FORMAT).timetuple())


def iso(seconds: float) -> str:
    """the inverse of epoch()"""
    return datetime.fromtimestamp(int(seconds), timezone.utc).strftime(TS_FORMAT)


class Files(list):
    """the files of a records file, with time_zone: the offsets of their timestamps (see normalize_times)"""
    time_zone: Optional[dict] = None


def normalize_times(files: List[dict]) -> dict:
    """timestamps with the offset of the log (summarize_log_errors keeps it): with one offset in the whole input (or
    none), stripped, the times stay as written in the logs; with several (UTC broker logs and local time Connect logs),
    the times with an offset are converted to UTC, else they would be hours apart. Every timestamp is then 19
    characters, as the rest of this module expects"""
    def stamps():
        for f in files:
            yield f.get("log_first_ts")
            yield f.get("log_last_ts")
            for r in f["records"]:
                yield r.get("first_ts")
                yield r.get("last_ts")
                yield from r.get("timestamps") or []
            for c in f.get("configs") or []:
                yield c.get("time")
                for ch in c.get("changes") or []:
                    yield ch.get("time")
            for ev in f.get("events") or []:
                yield ev.get("time")
    offsets, naive = set(), False
    for t in stamps():
        if not t:
            continue
        m = _OFFSET_TS_RE.match(t)
        if m:
            offsets.add(m.group(2) + m.group(3) + ":" + m.group(4))
        else:
            naive = True
    to_utc = len(offsets) > 1

    def fix(t):
        if not t or len(t) <= 19:
            return t
        m = _OFFSET_TS_RE.match(t)
        if not m or not to_utc:
            return t[:19]
        shift = timedelta(hours=int(m.group(3)), minutes=int(m.group(4)))
        local = datetime.strptime(m.group(1), TS_FORMAT)
        return (local - shift if m.group(2) == "+" else local + shift).strftime(TS_FORMAT)
    for f in files:
        f["log_first_ts"], f["log_last_ts"] = fix(f.get("log_first_ts")), fix(f.get("log_last_ts"))
        for r in f["records"]:
            r["first_ts"], r["last_ts"] = fix(r.get("first_ts")), fix(r.get("last_ts"))
            if r.get("timestamps"):
                r["timestamps"] = [fix(t) for t in r["timestamps"]]
        for c in f.get("configs") or []:
            c["time"] = fix(c.get("time"))
            for ch in c.get("changes") or []:
                ch["time"] = fix(ch.get("time"))
        for ev in f.get("events") or []:
            ev["time"] = fix(ev.get("time"))
    return {"offsets": sorted(offsets), "converted_to_utc": to_utc, "without_offset": naive and bool(offsets)}


def parse_records(path: str) -> List[dict]:
    """Files of a records file, each with its records, in the order they were written; their timestamps normalized
    (normalize_times, in .time_zone)"""
    files: List[dict] = Files()
    current: Optional[dict] = None
    rec: Optional[dict] = None
    # last finished record, for its @@PGCTX@@ lines
    done: Optional[dict] = None
    try:
        fh = open(path, encoding="utf-8", errors="replace")
    except OSError:
        return files
    with fh:
        for raw in fh:
            line = raw.rstrip("\n")
            if line.startswith("@@PGFILE@@\t"):
                parts = line.split("\t")
                # the period the file covers (first and last timestamped line) is only in the records files
                # written by a recent summarize_log_errors: an older one has no field 5 and 6
                parts += [""] * (7 - len(parts))
                current = {"label": parts[1], "lines": int(parts[2]), "distinct": int(parts[3]),
                           "occurrences": int(parts[4]), "log_first_ts": parts[5] or None,
                           "log_last_ts": parts[6] or None, "records": [], "configs": [], "events": [],
                           "event_counts": []}
                files.append(current)
                rec = done = None
            elif line.startswith("@@PGREC@@\t") and current is not None:
                parts = line.split("\t")
                rec = {"level": parts[1], "count": int(parts[2]), "first_line": int(parts[3]), "last_line": int(parts[4]),
                       "first_ts": parts[5] or None, "last_ts": parts[6] or None, "lines": [], "timestamps": []}
                current["records"].append(rec)
                done = None
            elif line.startswith("@@PGTS@@\t") and rec is not None:
                # "x<stride> t1 t2 …": the times kept are every stride-th occurrence (summarize_log_errors spreads 1000 of
                # them over the life of the record), each stands for stride occurrences
                times = line.split("\t", 1)[1].split()
                if times and times[0].startswith("x") and times[0][1:].isdigit():
                    rec["ts_stride"] = int(times[0][1:])
                    times = times[1:]
                rec["timestamps"] = times
                finish_record(rec)
                done, rec = rec, None
            elif line.startswith("@@PGCFG@@\t") and current is not None:
                parts = (line.split("\t") + [""] * 6)[1:6]
                current["configs"].append({"title": parts[0], "context": "" if parts[1] == "file" else parts[1],
                                           "source": "file" if parts[1] == "file" else "log",
                                           "line": int(parts[2]) if parts[2].isdigit() else None, "time": parts[3] or None,
                                           "id": parts[4] or None, "lines": []})
                rec = done = None
            elif line.startswith("@@PGCFGL@@\t") and current is not None and current["configs"]:
                current["configs"][-1]["lines"].append(line.split("\t", 1)[1])
            elif line.startswith("@@PGEVT@@\t") and current is not None:
                # an event of the INFO lines: kind, line, timestamp, connector, detail (summarize_log_errors)
                parts = (line.rstrip("\n").split("\t") + [""] * 6)[1:6]
                current["events"].append({"kind": parts[0], "line": int(parts[1]) if parts[1].isdigit() else None,
                                          "time": parts[2] or None, "connector": parts[3] or None, "detail": parts[4]})
            elif line.startswith("@@PGEVTN@@\t") and current is not None:
                # how many events of a kind for a connector or a group in the whole file (only 300 are noted)
                parts = (line.rstrip("\n").split("\t") + [""] * 4)[1:4]
                current["event_counts"].append({"kind": parts[0], "who": parts[1], "count": int(parts[2]) if parts[2].isdigit() else 0})
            elif line.startswith("@@PGCFGCHG@@\t") and current is not None and current["configs"]:
                parts = (line.split("\t") + [""] * 5)[1:5]
                key, _, previous = parts[2].partition("=")
                current["configs"][-1].setdefault("changes", []).append(
                    {"line": int(parts[0]) if parts[0].isdigit() else None, "time": parts[1] or None, "key": key,
                     "previous": previous, "value": parts[3].partition("=")[2]})
            elif line.startswith("@@PGCTX@@\t") and done is not None:
                done["context"] = (done["context"] + "\n" if done.get("context") else "") + line.split("\t", 1)[1]
            elif rec is not None:
                rec["lines"].append(line)
    for f in files:
        f["records"].sort(key=lambda r: (LEVEL_ORDER.get(r["level"], 9), -r["count"]))
    files.time_zone = normalize_times(files)
    return files


def finish_record(rec: dict) -> None:
    lines = rec.pop("lines")
    rec["text"] = "\n".join(lines)
    rec["message"] = lines[0] if lines else ""
    m = CONNECTOR_RE.search(rec["message"])
    rec["connector"] = (m.group(1) or m.group(2)) if m else None
    chain = [l.strip() for l in lines[1:] if l.startswith("    ") and not l.startswith("        ")]
    rec["chain"] = chain
    # deepest cause: last exception of the chain, else an exception named in the message
    rec["root_cause"] = None
    rec["root_cause_message"] = ""
    for candidate in reversed(chain):
        m = EXCEPTION_RE.match(candidate)
        if m:
            rec["root_cause"], rec["root_cause_message"] = m.group(1), (m.group(2) or "")
            break
    if rec["root_cause"] is None:
        m = re.search(r"((?:[a-z_$][\w$]*\.)+[A-Z][\w$]*(?:Exception|Error|Throwable))"
                      r"|^Unhandled exception\. ((?:[A-Z][\w]*\.)+[A-Z]\w*Exception)", rec["message"])
        if m:
            rec["root_cause"] = m.group(1) or m.group(2)
            # its message: what follows it on the line, without the logger at its end ("… (io.confluent.connect.s3.S3SinkTask)").
            # Without it, every AmazonS3Exception of the logs was one root cause: a SlowDown and an AccessDenied together
            msg = rec["message"][m.end():]
            msg = re.sub(r"^[:\s]+", "", msg)
            msg = re.sub(r"\s+\([\w$.]+(?::\d+)?\)\s*$", "", msg)
            rec["root_cause_message"] = msg.strip()


def config_connector(c: dict) -> Optional[str]:
    """connector of a config: its [connector|task-0] context, else the name of a connector config (file or log)"""
    m = re.match(r"\[([^\s|\]]+)\|", c.get("context") or "")
    if m:
        return m.group(1)
    if c["title"].endswith("ConnectorConfig") or c["title"] == "connector config":
        return c.get("id")
    return None


def filter_connectors(files: List[dict], names: List[str], with_worker: bool = False) -> None:
    """Keeps only the records and configs of these connectors (and those without a connector context with_worker),
    in place: --connector of playground analyze logs"""
    wanted = set(names)
    for f in files:
        f["records"] = [r for r in f["records"] if (r["connector"] in wanted) or (with_worker and not r["connector"])]
        f["distinct"] = len(f["records"])
        f["occurrences"] = sum(r["count"] for r in f["records"])
        f["configs"] = [c for c in f.get("configs", [])
                        if (config_connector(c) in wanted) or (with_worker and not config_connector(c))]


def all_records(files: List[dict]):
    for f in files:
        for r in f["records"]:
            yield f, r


def earliest(matches: List[Tuple[int, dict, dict]]) -> Tuple[int, dict, dict]:
    """The (file index, file, record) that happened first: by timestamp, else by file and line"""
    return min(matches, key=lambda m: (m[2]["first_ts"] or "~", m[0], m[2]["first_line"]))


def short_exception(line: str) -> str:
    """'Caused by: org.x.FooException: msg' -> 'FooException: msg'"""
    m = EXCEPTION_RE.match(line)
    if not m:
        return line
    # (a .NET generic type: ProduceException`2[System.String,System.String] -> ProduceException)
    return re.sub(r"`\d+\[.*$", "", m.group(1)).split(".")[-1] + (f": {m.group(2)}" if m.group(2) else "")


def mask_ids(text: str) -> str:
    """digits as #, and ids of letters and digits (AWS Request ID 5PPC305GEXB1A0R9, Extended Request ID, tokens) as one #:
    the same error with another request id, table or partition is the same chain"""
    text = re.sub(r"(?i)(request id: )[^\s,)]+", r"\1#", text)
    text = re.sub(r"(?=[A-Za-z0-9+/]*[0-9])(?=[A-Za-z0-9+/]*[A-Za-z])[A-Za-z0-9+/]{8,}", "#", text)
    return re.sub(r"[0-9]+", "#", text)


def chain_key_text(text: str) -> str:
    text = re.sub(r"(?m)^\[(?:Producer|Consumer|AdminClient|Worker|Admin)[^\]]*\]\s*", "", text)
    text = re.sub(r"\([^()\s]+:\d+\)", "(…)", text)
    return re.sub(r"clientId=[^,\]\s]+", "clientId=…", text)


def killed_task_chains(matches: List[Tuple[int, dict, dict]]) -> List[dict]:
    """Records of killed tasks grouped by exception chain (exception thrown + deepest cause), in order of first occurrence"""
    groups: Dict[str, dict] = {}
    for idx, f, r in matches:
        thrown = r["chain"][0] if r["chain"] else short_message(r["message"])
        cause = r["chain"][-1] if len(r["chain"]) > 1 else ""
        # same chain on another table, topic or partition: {ORACDC.REDO.DB1-0=OffsetAndMetadata{offset=1}} and digits ignored;
        # a message without exception is the same for every client and broker: "[Producer clientId=connector-producer-X-0]"
        # and "(broker-1.example.com/10.0.0.1:9092)" ignored (the connectors are listed with the chain)
        key = mask_ids(re.sub(r"\{.*\}", "{…}", chain_key_text(f"{thrown}\n{cause}")))
        g = groups.setdefault(key, {"exception": short_exception(thrown), "caused_by": short_exception(cause) if cause else "",
                                    "occurrences": 0, "connectors": OrderedDict(), "matches": []})
        g["occurrences"] += r["count"]
        if r["connector"]:
            g["connectors"][r["connector"]] = True
        g["matches"].append((idx, f, r))
    out = []
    for g in groups.values():
        _, f, r = earliest(g.pop("matches"))
        out.append(dict(g, connectors=list(g["connectors"]), first_file=f["label"], first_line=r["first_line"],
                        first_timestamp=r["first_ts"]))
    out.sort(key=lambda g: (g["first_timestamp"] or "~", g["first_line"]))
    return out


def reading_links(h: dict) -> List[tuple]:
    """(label, url) of what to read about a known cause: its knowledge-base article, then its docs page"""
    out = []
    if h.get("kb"):
        out.append((f"KB: {h.get('kb_title') or 'knowledge base article'}", h["kb"]))
    if h.get("docs"):
        out.append(("Docs", h["docs"]))
    return out


def reading_list(h: dict) -> List[str]:
    """Lines of the text summary: what to read about a known cause"""
    return [f"{label}: {url}" for label, url in reading_links(h)]


def match_hints(files: List[dict], unit: str = "file") -> List[dict]:
    out = []
    for pattern, severity, title, advice in HINTS:
        rx = re.compile(pattern)
        matches = [(i, f, r) for i, f in enumerate(files) for r in f["records"] if rx.search(r["text"])]
        if not matches:
            continue
        occurrences = sum(r["count"] for _, _, r in matches)
        labels = list(OrderedDict((f["label"], True) for _, f, _ in matches))
        _, first_f, first_r = earliest(matches)
        first = f"line {first_r['first_line']}" + (f", {first_r['first_ts'].replace('T', ' ')}" if first_r["first_ts"] else "")
        where = (f"in {len(labels)} {unit}s (first at {first_f['label']} {first})" if len(labels) > 1
                 else f"in {first_f['label']} (first at {first})")
        hint = {"severity": severity, "title": title, "occurrences": occurrences, "files": labels, "where": where,
                "advice": advice, "text": f"{title}: {occurrences} occurrence(s) {where}: {advice}",
                "first": {"file": first_f["label"], "line": first_r["first_line"], "timestamp": first_r["first_ts"]},
                # the records it matched (index set by analyze()): how much of it is in the current selection
                "records": [r["index"] for _, _, r in matches if r.get("index") is not None]}
        # what to read about it: a knowledge-base article and / or a docs page
        hint.update(known_causes.links(title))
        # the exception chains of every known cause, for the cards of the HTML report (not in --json: only the killed
        # tasks have them there, as before)
        hint["_chains"] = killed_task_chains(matches)
        if title == KILLED_TASK_TITLE:
            # the exception that killed the tasks is what to fix: one line per distinct chain
            chains = hint["_chains"]
            hint["chains"] = chains
            hint["text"] = (f"{title}: {occurrences} occurrence(s) {where}, {len(chains)} distinct exception chain(s) "
                            f"(below, in order of first occurrence): {advice}")
            details = []
            for c in chains:
                who = ", ".join(c["connectors"][:5]) + (f" (+{len(c['connectors']) - 5} more)" if len(c["connectors"]) > 5 else "")
                details.append(f"×{c['occurrences']} {c['exception'][:250]}"
                               + (f" ⬅️ Caused by: {c['caused_by'][:250]}" if c["caused_by"] else "")
                               + (f" · {len(c['connectors'])} connector(s): {who}" if c["connectors"] else "")
                               + f" · first at {c['first_file'] + ' ' if len(labels) > 1 else ''}line {c['first_line']}"
                               + (f" ({c['first_timestamp'].replace('T', ' ')})" if c["first_timestamp"] else ""))
            hint["details"] = details
        out.append(hint)
    out.sort(key=lambda h: SEVERITY_ORDER.index(h["severity"]))
    return out


def short_message(message: str) -> str:
    """The message of a record without its timestamp, level, [connector|task] context and (logger:line)."""
    # journalctl prefix: "Oct 06 07:35:50 host connect-distributed[1080]: "
    m = re.sub(r"^[A-Z][a-z]{2} [ \d]\d \d\d:\d\d:\d\d \S+ [^\s:]+: ", "", message)
    # a structured JSON log line (KafkaJS: {"level":"ERROR","timestamp":…,"logger":"kafkajs","message":"[Connection] …"}): its
    # message (the record may be cut, no json.loads)
    j = re.match(r'^\{.*?"(?:message|msg)"\s*:\s*"((?:[^"\\]|\\.)*)"', m)
    if j:
        m = j.group(1).replace('\\"', '"')
    # (UTC timestamps end with Z: "2026-11-05T16:30:02.123456Z ERROR …" of the tracing logs of the Rust client)
    m = re.sub(r"^\[?\d{4}-\d{2}-\d{2}[ T][\d:,.]*(?:Z|[+-]\d\d:?\d\d)?\]?\s*", "", m)
    m = re.sub(r"^(\[[^]]*\]\s*)?(TRACE|DEBUG|INFO|WARN|WARNING|ERROR|FATAL|SEVERE)\b:?\s*", "", m)
    # librdkafka (C/C++, Python, Go, .NET, JavaScript clients): "%3|1793896102.923|FAIL|rdkafka#producer-1| [thrd:…]: msg"
    # -> "FAIL [rdkafka#producer-1] msg"; .NET console logger: "fail: Program[0] msg" -> "msg"
    m = re.sub(r"^%\d\|[\d.]+\|([^|]*)\|([^|]*)\|\s*(?:\[thrd:[^\]]*\]:\s*)?", r"\1 [\2] ", m)
    m = re.sub(r"^(?:crit|fail|warn): \S+\[\d+\]\s*", "", m)
    m = re.sub(r"^\[[^]]*\|[^]]*\]\s*", "", m)
    return re.sub(r"\s*\([\w$.]+:\d+\)\s*$", "", m)


def epochs(timestamps: List[str]) -> List[int]:
    """Sorted epoch seconds of the timestamps that parse, the same conversion as the occurrences chart."""
    out = []
    for ts in timestamps:
        try:
            out.append(epoch(ts))
        except ValueError:
            pass
    out.sort()
    return out


B36 = "0123456789abcdefghijklmnopqrstuvwxyz"


def encode_times(times: List[int]) -> str:
    """The epoch seconds of the occurrences of one record: the first value then the deltas, in base 36 (the plain
    numbers would add megabytes to the report). Decoded by pgTimes() of FILTER_SCRIPT."""
    parts, prev = [], 0
    for t in times:
        d, s = t - prev, ""
        prev = t
        while d:
            d, rem = divmod(d, 36)
            s = B36[rem] + s
        parts.append(s or "0")
    return " ".join(parts)


def root_causes(files: List[dict]) -> List[dict]:
    """Records grouped by their deepest exception, or by their message when they have none."""
    causes: Dict[str, dict] = {}
    for f, r in all_records(files):
        # same exception with another message is another cause (ConnectException wraps everything)
        # a message without exception: the client context ([Producer clientId=…]) and (host/ip:port) left out, as for the
        # exception chains of the findings: one root cause for all the clients, the connectors are listed with it
        plain = chain_key_text(short_message(r["message"]))
        label = (f"{r['root_cause']}: {mask_ids(r['root_cause_message'])[:100]}" if r["root_cause"] else plain[:160])
        # the same message with other numbers is the same cause ("(after 1ms in state CONNECT)" of librdkafka, in two files)
        key = label if r["root_cause"] else mask_ids(label)
        c = causes.setdefault(key, {"root_cause": r["root_cause"], "label": label, "occurrences": 0, "records": 0, "files": OrderedDict(),
                                    "connectors": OrderedDict(), "example": r["root_cause_message"] or plain, "level": r["level"],
                                    "records_meta": []})
        c["occurrences"] += r["count"]
        c["records"] += 1
        c["files"][f["label"]] = True
        # level, connector, count and epoch seconds of each record, for the filters of the HTML report
        c["records_meta"].append((r["level"], r.get("connector") or "", r["count"], epochs(r["timestamps"]),
                                  r.get("index", -1), r.get("file_index", -1), r.get("ts_stride", 1)))
        if r["connector"]:
            c["connectors"][r["connector"]] = c["connectors"].get(r["connector"], 0) + r["count"]
        else:
            c["no_connector"] = True
        if LEVEL_ORDER.get(r["level"], 9) < LEVEL_ORDER.get(c["level"], 9):
            c["level"] = r["level"]
    out = []
    for c in causes.values():
        c["files"] = list(c["files"])
        # most frequent first
        c["connectors"] = sorted(c["connectors"], key=lambda n: -c["connectors"][n])
        out.append(c)
    out.sort(key=lambda c: (LEVEL_ORDER.get(c["level"], 9), -c["occurrences"]))
    return out


def root_cause_chains(c: dict, by_index: Dict[int, Tuple[dict, dict]]) -> dict:
    """the exception chains and the first occurrence of a root cause, as for a known cause"""
    matches = [(m[4], *by_index[m[4]]) for m in c["records_meta"] if m[4] in by_index]
    if not matches:
        return {}
    _, f, r = earliest(matches)
    return {"_chains": killed_task_chains(matches),
            "first": {"file": f["label"], "line": r["first_line"], "timestamp": r["first_ts"]}}


def findings(files: List[dict], hints: List[dict], causes: List[dict], top: int = 5, unit: str = "file") -> List[dict]:
    """Known causes first, then the most frequent root causes no known cause explains."""
    # _view: what the HTML report renders (count, first occurrence linked, exception chains), not in --json
    res = [dict({k: h[k] for k in ("severity", "text", "details", "records") if k in h}, _view=dict(h, kind="known"))
           for h in hints]
    # record index -> (file, record): the exception chains and the first occurrence of a root cause
    by_index = {r["index"]: (f, r) for f in files for r in f["records"] if r.get("index") is not None}
    explained = [(re.compile(p), title) for p, _, title, _ in HINTS]
    # the known causes of each root cause (also in --json: root_causes[].explained_by): the ones sharing its records,
    # the most shared first, else the first whose pattern matches it; the 🌳 table of the HTML report links them to
    # their cards
    hint_records = [(h["title"], set(h.get("records") or [])) for h in hints]
    for c in causes:
        mine = {m[4] for m in c["records_meta"] if m[4] >= 0}
        shared = sorted(((len(recs & mine), t) for t, recs in hint_records if recs & mine), key=lambda x: -x[0])
        c["explained_by"] = ([t for _, t in shared]
                             or [t for rx, t in explained if rx.search(c["label"] + " " + c["example"])][:1])
    added = 0
    for i, c in enumerate(causes):
        if added >= top:
            break
        # explained by a known cause (records in common, or its pattern): already a card
        if c["explained_by"]:
            continue
        # shown as a finding (🌳 card): the table links to it
        c["in_findings"] = True
        sev = "CRITICAL" if c["level"] == "FATAL" else "HIGH" if c["level"] == "ERROR" else "MEDIUM"
        where = f"{len(c['files'])} {unit}s" if len(c["files"]) > 1 else c["files"][0]
        what = f"{c['root_cause']}: {c['example']}" if c["root_cause"] else c["example"]
        res.append({"severity": sev, "text": f"{c['level']} ×{c['occurrences']} in {where}: {what[:300]}",
                    "records": [m[4] for m in c["records_meta"] if m[4] >= 0],
                    "_view": dict({"kind": "root", "cause_index": i, "level": c["level"], "occurrences": c["occurrences"], "files": c["files"],
                                   "root_cause": c["root_cause"], "example": c["example"]},
                                  **root_cause_chains(c, by_index))})
        added += 1
    res.sort(key=lambda x: SEVERITY_ORDER.index(x["severity"]))
    return res


# a period shorter than this is flagged in the report: the logs were cut too narrow to hold the context of an
# incident (a customer bundle of 3 minutes, a log rotated right after the error)
SHORT_PERIOD_SECONDS = 10 * 60


def duration_seconds(first: Optional[str], last: Optional[str]) -> Optional[int]:
    """Seconds between two "2026-10-22T14:51:20" timestamps, None when one is missing or unparsable."""
    if not first or not last:
        return None
    try:
        a = datetime.strptime(first[:19], "%Y-%m-%dT%H:%M:%S")
        b = datetime.strptime(last[:19], "%Y-%m-%dT%H:%M:%S")
    except ValueError:
        return None
    return max(0, int((b - a).total_seconds()))


def human_duration(seconds: Optional[int]) -> str:
    """59 s, 12 min 30 s, 6 h 28 min, 3 d 4 h"""
    if seconds is None:
        return "unknown"
    if seconds < 60:
        return f"{seconds} s"
    if seconds < 3600:
        return f"{seconds // 60} min" + (f" {seconds % 60} s" if seconds % 60 else "")
    if seconds < 86400:
        return f"{seconds // 3600} h" + (f" {seconds % 3600 // 60} min" if seconds % 3600 // 60 else "")
    return f"{seconds // 86400} d" + (f" {seconds % 86400 // 3600} h" if seconds % 86400 // 3600 else "")


def period_text(first: Optional[str], last: Optional[str]) -> str:
    """"2026-10-22 14:51:20 → 15:40:32", the date of the end repeated only when it is another day"""
    if not first:
        return "-"
    out = first.replace("T", " ")
    if last and last != first:
        out += " → " + (last[11:] if last[:10] == first[:10] else last.replace("T", " "))
    return out


def summary(files: List[dict]) -> dict:
    by_level = {"FATAL": 0, "ERROR": 0, "WARN": 0}
    by_connector: Dict[str, int] = {}
    first, last = None, None
    for _, r in all_records(files):
        by_level[r["level"]] = by_level.get(r["level"], 0) + r["count"]
        if r["connector"]:
            by_connector[r["connector"]] = by_connector.get(r["connector"], 0) + r["count"]
        for ts in (r["first_ts"], r["last_ts"]):
            if ts:
                first = ts if first is None or ts < first else first
                last = ts if last is None or ts > last else last
    # period the logs themselves cover: the first and the last timestamped line of every file scanned, findings or
    # not (a short window is a bundle that may not even contain the incident)
    log_first, log_last = None, None
    for f in files:
        for ts in (f.get("log_first_ts"), f.get("log_last_ts")):
            if not ts:
                continue
            log_first = ts if log_first is None or ts < log_first else log_first
            log_last = ts if log_last is None or ts > log_last else log_last
    # a records file written before the period was recorded: fall back to the span of the records
    if log_first is None:
        log_first, log_last = first, last
    return {"files_scanned": len(files), "files_with_findings": sum(1 for f in files if f["records"]),
            "lines": sum(f["lines"] for f in files), "distinct": sum(f["distinct"] for f in files),
            "occurrences": sum(f["occurrences"] for f in files), "by_level": by_level,
            "by_connector": dict(sorted(by_connector.items(), key=lambda kv: (-kv[1], kv[0]))),
            "first_timestamp": first, "last_timestamp": last,
            "log_first_timestamp": log_first, "log_last_timestamp": log_last,
            "log_duration_seconds": duration_seconds(log_first, log_last),
            "findings_duration_seconds": duration_seconds(first, last)}


def shorten_labels(files: List[dict]) -> None:
    """Labels without the folder they all share (the absolute path given on the command line); "path" keeps the full one."""
    if not files:
        return
    # only the part before the first ":" (inside an archive) is a path on disk
    heads = [f["label"].split(":", 1)[0] for f in files]
    prefix = heads[0].rsplit("/", 1)[0] + "/" if "/" in heads[0] else ""
    while prefix and not all(h.startswith(prefix) for h in heads):
        prefix = prefix[:-1].rsplit("/", 1)[0] + "/" if "/" in prefix[:-1] else ""
    for f in files:
        f["path"] = f["label"]
        f["label"] = f["label"][len(prefix):]


def drop_alternating_changes(config: dict, window: int = 60) -> None:
    """Two configs logged with the same identity (two consumers with one client.id) look like a value going back and
    forth: a change undone within `window` seconds (or 500 lines without timestamps) is not a restart with another
    config, both are dropped"""
    changes = config.get("changes") or []

    def seconds(ch):
        try:
            return epoch(ch["time"]) if ch.get("time") else None
        except ValueError:
            return None

    drop = set()
    for i, a in enumerate(changes):
        for j in range(i + 1, len(changes)):
            b = changes[j]
            if a["key"] != b["key"] or (a["previous"], a["value"]) != (b["value"], b["previous"]):
                continue
            ta, tb = seconds(a), seconds(b)
            close = (abs(tb - ta) <= window) if ta is not None and tb is not None else \
                (a.get("line") is not None and b.get("line") is not None and abs(b["line"] - a["line"]) <= 500)
            if close:
                drop.update((i, j))
    if drop:
        config["changes"] = [ch for k, ch in enumerate(changes) if k not in drop]
        if not config["changes"]:
            del config["changes"]


# a period of a folder that no log file covers, between two files of it: shown from this length
COVERAGE_GAP_SECONDS = 10 * 60


def ts_seconds(ts: Optional[str]) -> Optional[float]:
    if not ts:
        return None
    try:
        return epoch(ts)
    except ValueError:
        return None


def coverage(files: List[dict]) -> dict:
    """🕰️ Log coverage: the time range of each file (first and last timestamped line), grouped by folder (a folder of
    rotated logs, one per worker or pod), and the periods of a folder that none of its files covers (a missing hour of
    rotated logs): what happened then is not in the input. Also in --json: .coverage"""
    out_files = []
    for f in files:
        first, last = f.get("log_first_ts"), f.get("log_last_ts")
        a, b = ts_seconds(first), ts_seconds(last)
        label = f["label"]
        folder = label.rsplit("/", 1)[0] if "/" in label else ""
        out_files.append({"label": label, "folder": folder, "first": first, "last": last,
                          "seconds": int(b - a) if a is not None and b is not None else None, "lines": f["lines"],
                          "occurrences": sum(r["count"] for r in f["records"])})
    gaps = []
    folders: "OrderedDict[str, List[dict]]" = OrderedDict()
    for x in out_files:
        folders.setdefault(x["folder"], []).append(x)
    timed = [x for x in out_files if x["seconds"] is not None]
    t0 = min((ts_seconds(x["first"]) for x in timed), default=None)
    t1 = max((ts_seconds(x["last"]) for x in timed), default=None)

    def gap(folder: str, a: float, b: float, where: str) -> dict:
        return {"folder": folder, "from": iso(a), "to": iso(b), "seconds": int(b - a), "where": where}
    for folder, xs in folders.items():
        spans = sorted((ts_seconds(x["first"]), ts_seconds(x["last"])) for x in xs if x["seconds"] is not None)
        if not spans:
            continue
        # a folder (a worker, a pod) that starts after or ends before the other logs of the input: its first or last
        # hours are missing (several folders only)
        if len(folders) > 1 and spans[0][0] - t0 >= COVERAGE_GAP_SECONDS:
            gaps.append(gap(folder, t0, spans[0][0], "start"))
        end = spans[0][1]
        for a, b in spans[1:]:
            if a - end >= COVERAGE_GAP_SECONDS:
                gaps.append(gap(folder, end, a, "between"))
            end = max(end, b)
        if len(folders) > 1 and t1 - end >= COVERAGE_GAP_SECONDS:
            gaps.append(gap(folder, end, t1, "end"))
    return {"first": min((x["first"] for x in timed), default=None), "last": max((x["last"] for x in timed), default=None),
            "files": out_files, "gaps": gaps}


def analyze(files: List[dict], unit: str = "file") -> dict:
    """unit: what a label is (file, container, script), for the texts of the findings"""
    shorten_labels(files)
    # the records and the files with findings are numbered in the order they are rendered: data-rec of each block and
    # data-file of each row of the files table, indexes 5 and 6 of occurrences_json
    index = 0
    for file_index, f in enumerate(x for x in files if x["records"]):
        for r in f["records"]:
            r["index"], r["file_index"] = index, file_index
            index += 1
    hints = match_hints(files, unit)
    causes = root_causes(files)
    # the "<Class>Config values:" dumps of the logs and the config files of the input (.properties, connector JSON)
    configuration = [dict({k: v for k, v in c.items() if k != "lines"}, file=f["label"], text="\n".join(c["lines"]))
                     for f in files for c in f.get("configs", []) if c["lines"]]
    for c in configuration:
        drop_alternating_changes(c)
    for f in files:
        f.pop("configs", None)
    res = {"summary": summary(files), "findings": findings(files, hints, causes, unit=unit), "known_causes": hints,
           "root_causes": causes, "files": [f for f in files if f["records"]],
           "files_without_findings": [f["label"] for f in files if not f["records"]],
           "coverage": coverage(files),
           "configuration": configuration}
    res["timeline"] = incident_timeline(res, files)
    res["connectors"] = connector_health(res, files)
    res["summary"]["kafka_versions"] = kafka_versions(files)
    res["lifecycle"] = lifecycle(res, files)
    res["config_lint"] = config_lint(res)
    for c in res["connectors"]:
        c["config_lint"] = [x for x in res["config_lint"] if x["connector"] == c["connector"]]
    # the counts on the 🔌 card of each connector
    for c in res["connectors"]:
        for r in res["lifecycle"]["rows"]:
            if r["kind"] in ("connector_start", "task_start") and r["who"] == c["connector"]:
                c[r["kind"] + "s"] = r["count"]
            elif r["kind"] == "consumer_rejoin" and (r["who"] == "connect-" + c["connector"] or r.get("connector") == c["connector"]):
                c["consumer_rejoins"] = c.get("consumer_rejoins", 0) + r["count"]
    return res


# the config classes logged when a component starts: the dump is a (re)start of the worker, broker, registry…
START_CONFIGS = {"DistributedConfig": "Connect worker", "StandaloneConfig": "Connect worker (standalone)",
                 "KafkaConfig": "broker", "KafkaRestConfig": "REST Proxy", "SchemaRegistryConfig": "Schema Registry",
                 "KsqlConfig": "ksqlDB server", "KsqlRestConfig": "ksqlDB server"}
CONNECTOR_CONFIGS = {"SourceConnectorConfig", "SinkConnectorConfig", "ConnectorConfig"}
TIMELINE_LIMIT = 200


def record_label(r: dict) -> str:
    """the deepest exception of a record and its own message (not the example of its root cause, which can come from
    another record), without the class name repeated at the start of the message"""
    rc = r.get("root_cause") or ""
    msg = r.get("root_cause_message") or short_message(r["message"])
    if rc:
        i = msg.find(rc + ":", 0, 300)
        if i >= 0:
            msg = msg[i + len(rc) + 1:].lstrip()
        return f"{rc.split('.')[-1]}: {msg}"
    return msg


def incident_timeline(res: dict, files: List[dict]) -> List[dict]:
    """one chronological list, all files merged: the first occurrence of each root cause and of each known cause, the
    (re)starts of the components (their startup config dump), the connectors (re)configured and the config keys changed
    between restarts. Answers "what happened first?"; only what has a timestamp, the first TIMELINE_LIMIT events"""
    by_index = {r.get("index"): (f, r) for f in files for r in f["records"] if r.get("index") is not None}
    events: Dict[Tuple[str, int], dict] = {}

    def add(time, file, line, kind, level, text, connector=None, count=None, record=None):
        if not time:
            return
        key = (file, line or 0)
        ev = events.get(key)
        # the keys changed are what matters on the line of a config dump: they replace "(re)configured", and add up
        if ev and kind == "config_change" and ev["kind"] in ("connector_config", "config_change"):
            ev["text"] = text if ev["kind"] == "connector_config" else ev["text"] + "; " + text.split(": ", 1)[-1]
            ev["kind"] = "config_change"
            return
        if ev and kind == "known_cause":
            # the first occurrence of a known cause is often the first occurrence of a root cause: one row, both texts
            ev["known_causes"] = ev.get("known_causes", []) + [text]
            return
        if ev:
            return
        events[key] = {"time": time, "kind": kind, "level": level, "text": text, "file": file, "line": line,
                       "connector": connector, "count": count, "record": record}
        if kind == "known_cause":
            events[key]["known_causes"] = [text]

    for c in res["root_causes"]:
        first = None
        for meta in c["records_meta"]:
            fr = by_index.get(meta[4])
            if fr and fr[1].get("first_ts") and (first is None or fr[1]["first_ts"] < first[1]["first_ts"]):
                first = fr
        if first:
            f, r = first
            add(r["first_ts"], f["label"], r["first_line"], "first_error", r["level"], record_label(r)[:200],
                r.get("connector"), c["occurrences"], r.get("index"))
    for h in res["known_causes"]:
        first = h.get("first") or {}
        add(first.get("timestamp"), first.get("file"), first.get("line"), "known_cause", h["severity"], h["title"])
    seen_connector = set()
    for c in res["configuration"]:
        if c.get("source") != "log" or not c.get("time"):
            continue
        if c["title"] in START_CONFIGS:
            add(c["time"], c["file"], c.get("line"), "start", None, f"🔄 {START_CONFIGS[c['title']]} started ({c['title']} logged)")
        elif c["title"] in CONNECTOR_CONFIGS:
            name = config_connector(c) or ""
            if (name, c["time"][:16]) not in seen_connector:
                seen_connector.add((name, c["time"][:16]))
                add(c["time"], c["file"], c.get("line"), "connector_config", None,
                    f"🔌 connector {name or '?'} (re)configured", name or None)
        for ch in c.get("changes") or []:
            add(ch.get("time"), c["file"], ch.get("line"), "config_change", None,
                f"⚙️ {c['title']}: {ch['key']} {ch['previous'] or '∅'} → {ch['value'] or '∅'}"[:200], config_connector(c))
    # the lifecycle of the INFO lines: every (re)start of a worker or a broker, the first rebalances of the worker groups
    nrebalances = 0
    for f in files:
        for ev in f.get("events") or []:
            if ev["kind"] == "process_start":
                add(ev.get("time"), f["label"], ev.get("line"), "lifecycle", None, f"🚀 {ev.get('detail') or 'started'}")
            elif ev["kind"] == "worker_rebalance" and nrebalances < 20:
                nrebalances += 1
                add(ev.get("time"), f["label"], ev.get("line"), "lifecycle", None, f"🔄 rebalance of the worker group {ev.get('detail') or ''}".strip())
    out = sorted(events.values(), key=lambda ev: (ev["time"], ev["file"] or "", ev["line"] or 0))
    link_causes(out)
    return out[:TIMELINE_LIMIT]


# a first error this soon after a change (a config key changed, a connector reconfigured, a worker / broker restarted) is
# marked as following it: the question behind most "it broke after…" tickets
CAUSE_WINDOW_SECONDS = 600


def link_causes(events: List[dict]) -> None:
    """marks each first ERROR / FATAL and known cause that comes within CAUSE_WINDOW_SECONDS after a change (a config key
    changed, a worker / broker restarted), the latest one before it, of the same connector when both have one (a restart
    counts for every connector): ev["after"]"""
    changes: List[dict] = []
    started = set()
    for ev in events:
        # a change: a config key changed, or a worker / broker restarted (not its first start in a file, nor a connector
        # created: everything after the creation of a connector would follow it)
        if ev["kind"] == "config_change":
            changes.append(ev)
            continue
        if ev["kind"] == "lifecycle" and ev["text"].startswith("🚀"):
            if ev["file"] in started:
                changes.append(ev)
            started.add(ev["file"])
            continue
        # what follows: the first ERROR / FATAL of a root cause, a known cause (not a WARN)
        if ev["kind"] not in ("first_error", "known_cause") or (ev["kind"] == "first_error" and ev.get("level") == "WARN"):
            continue
        t = epoch(ev["time"])
        for ch in reversed(changes):
            delta = t - epoch(ch["time"])
            if delta > CAUSE_WINDOW_SECONDS:
                break
            if ev.get("connector") and ch.get("connector") and ev["connector"] != ch["connector"]:
                continue
            ev["after"] = {"seconds": int(delta), "text": ch["text"], "time": ch["time"], "file": ch["file"], "line": ch["line"]}
            break


def after_text(ev: dict) -> str:
    a = ev.get("after")
    return f" ⏱️ {human_duration(a['seconds']) if a['seconds'] else 'right'} after {a['text']}" if a else ""


def connector_health(res: dict, files: List[dict]) -> List[dict]:
    """one card per connector of the logs: its errors and warnings (by level, first and last time), whether a task was
    killed, the known causes of its records, its configuration logged (dumps, keys changed between restarts) and the
    clients it owns (connector-producer-<name>-0…), most errors first"""
    titles_of: Dict[int, List[str]] = {}
    for h in res["known_causes"]:
        for i in h.get("records") or []:
            titles_of.setdefault(i, []).append(h["title"])
    cards: "OrderedDict[str, dict]" = OrderedDict()

    def card(name):
        return cards.setdefault(name, {"connector": name, "by_level": {"FATAL": 0, "ERROR": 0, "WARN": 0}, "records": 0,
                                       "first_timestamp": None, "last_timestamp": None, "task_killed": 0,
                                       "known_causes": [], "config_dumps": 0, "config_changes": [], "clients": []})
    for f in files:
        for r in f["records"]:
            name = r.get("connector")
            if not name:
                continue
            c = card(name)
            c["by_level"][r["level"]] = c["by_level"].get(r["level"], 0) + r["count"]
            c["records"] += 1
            if r.get("first_ts") and (not c["first_timestamp"] or r["first_ts"] < c["first_timestamp"]):
                c["first_timestamp"] = r["first_ts"]
            if r.get("last_ts") and (not c["last_timestamp"] or r["last_ts"] > c["last_timestamp"]):
                c["last_timestamp"] = r["last_ts"]
            titles = titles_of.get(r.get("index"), [])
            if KILLED_TASK_TITLE in titles:
                c["task_killed"] += r["count"]
            for t in titles:
                if t not in c["known_causes"]:
                    c["known_causes"].append(t)
    for cfg in res["configuration"]:
        name = config_connector_of(cfg)
        if not name or name not in cards:
            continue
        c = cards[name]
        c["config_dumps"] += 1
        client = cfg.get("id") or ""
        if re.match(r"^connector-(?:producer|consumer|dlq-producer|admin)-", client) and client not in c["clients"]:
            c["clients"].append(client)
        for ch in cfg.get("changes") or []:
            c["config_changes"].append({"time": ch.get("time"), "config": cfg["title"], "key": ch["key"],
                                        "previous": ch["previous"], "value": ch["value"]})
    # the version of each connector, from "Instantiated connector|task <name> with version <v> of type <class>" (oldest
    # first: an upgrade during the logs shows both)
    for f in files:
        for ev in sorted(f.get("events") or [], key=lambda x: (x.get("time") or "", x.get("line") or 0)):
            if ev["kind"] != "plugin_version" or ev.get("connector") not in cards:
                continue
            version, _, cls = ev["detail"].partition(" ")
            c = cards[ev["connector"]]
            c.setdefault("versions", [])
            if version not in c["versions"]:
                c["versions"].append(version)
            # the class of the connector, not of its task (Instantiated task … of type …SourceTask): the one of the plugin
            if not c.get("class") or not cls.endswith("Task"):
                c["class"] = cls
    out = list(cards.values())
    out.sort(key=lambda c: (-(c["by_level"]["FATAL"] + c["by_level"]["ERROR"]), -c["by_level"]["WARN"], c["connector"]))
    return out


# a group that rebalances this often is a storm: at least STORM_MIN of them, and STORM_PER_HOUR per hour or more
STORM_MIN = 10
STORM_PER_HOUR = 6
LIFECYCLE_KINDS = {"worker_rebalance": "worker group rebalances", "consumer_rejoin": "consumer group rejoins",
                   "connector_start": "connector starts", "task_start": "task starts", "process_start": "process starts"}


def lifecycle(res: dict, files: List[dict]) -> dict:
    """the lifecycle of the INFO lines: rebalances of the worker groups, rejoins of the consumer groups, connectors and
    tasks started, workers and brokers (re)started; counted per group / connector (all of them) with the first and last
    time (of the 300 noted per kind and file), the rate per hour of the period covered, and the storms"""
    hours = (res["summary"].get("log_duration_seconds") or 0) / 3600
    rows: Dict[Tuple[str, str], dict] = {}
    for f in files:
        for c in f.get("event_counts") or []:
            r = rows.setdefault((c["kind"], c["who"]), {"kind": c["kind"], "who": c["who"], "count": 0, "first": None,
                                                       "last": None, "connectors": Counter(), "reasons": Counter()})
            r["count"] += c["count"]
        for ev in f.get("events") or []:
            if ev["kind"] not in LIFECYCLE_KINDS:
                continue
            group = (ev.get("detail") or "").split(" · ")[0]
            who = group if ev["kind"] in ("worker_rebalance", "consumer_rejoin") else \
                ("connect" if "Connect" in (ev.get("detail") or "") else "broker") if ev["kind"] == "process_start" else ev.get("connector") or ""
            r = rows.get((ev["kind"], who))
            if not r:
                continue
            if ev.get("time"):
                r["first"] = min(r["first"] or ev["time"], ev["time"])
                r["last"] = max(r["last"] or ev["time"], ev["time"])
            if ev.get("connector"):
                r["connectors"][ev["connector"]] += 1
            if " · " in (ev.get("detail") or ""):
                r["reasons"][ev["detail"].split(" · ", 1)[1].strip()] += 1
    out = []
    for r in rows.values():
        per_hour = round(r["count"] / hours, 1) if hours > 0 else None
        out.append({"kind": r["kind"], "who": r["who"], "count": r["count"], "first": r["first"], "last": r["last"],
                    "per_hour": per_hour, "connector": r["connectors"].most_common(1)[0][0] if r["connectors"] else None,
                    "reason": r["reasons"].most_common(1)[0][0] if r["reasons"] else None,
                    # a consumer that leaves on purpose (closed: "pro-actively leaving the group", the schema history
                    # consumer of Debezium every few seconds) is not a storm
                    "storm": r["kind"] in ("worker_rebalance", "consumer_rejoin") and r["count"] >= STORM_MIN
                             and per_hour is not None and per_hour >= STORM_PER_HOUR
                             and "pro-actively leaving" not in (r["reasons"].most_common(1)[0][0] if r["reasons"] else "")})
    order = list(LIFECYCLE_KINDS)
    out.sort(key=lambda r: (not r["storm"], order.index(r["kind"]), -r["count"]))
    return {"rows": out, "storms": [r for r in out if r["storm"]]}


def lifecycle_text(lc: Optional[dict], top: int = 6) -> List[str]:
    if not lc or not lc.get("rows"):
        return []
    out = ["🔄 Restarts and rebalances (INFO lines)"]
    for r in lc["rows"][:top]:
        rate = f", {r['per_hour']:g}/h" if r.get("per_hour") is not None else ""
        out.append(f"   {'🌀 STORM ' if r['storm'] else ''}{r['who'] or '?'}: {r['count']:,} {LIFECYCLE_KINDS[r['kind']]}{rate}"
                   + (f" · {r['reason']}" if r.get("reason") else "")
                   + (f" · {period_text(r['first'], r['last'])}" if r.get("first") else ""))
    if len(lc["rows"]) > top:
        out.append(f"   … {len(lc['rows']) - top} more in the HTML report and .lifecycle of --json")
    return out


def rate_cell(r: dict) -> str:
    return "" if r.get("per_hour") is None else f"{r['per_hour']:g}"


def lifecycle_html(lc: Optional[dict]) -> str:
    if not lc or not lc.get("rows"):
        return ""
    rows = "".join(
        f"<tr class='{'lc-storm' if r['storm'] else ''}'><td>{'🌀 storm' if r['storm'] else ''}</td><td>{e(LIFECYCLE_KINDS[r['kind']])}</td>"
        f"<td class='mono'>{e(r['who'] or '?')}</td><td class='num'>{r['count']:,}</td>"
        f"<td class='num'>{rate_cell(r)}</td>"
        f"<td class='mono'>{e(period_text(r['first'], r['last'])) if r.get('first') else ''}</td>"
        f"<td>{e(r.get('reason') or '')}{(' <span class=fi-conn>' + e(r['connector']) + '</span>') if r.get('connector') else ''}</td></tr>"
        for r in lc["rows"])
    return ("<style>tr.lc-storm td{background:#fef2f2}html[data-theme=dark] tr.lc-storm td{background:#3b1515}</style>"
            "<div class='table-card'><h2>🔄 Restarts and rebalances</h2><p class='legend'>From the INFO lines: the rebalances of "
            "the Connect worker groups, the rejoins of the consumer groups (a sink connector, a client), the connectors and tasks "
            f"started, the workers and brokers (re)started. 🌀 a group that rebalanced at least {STORM_MIN} times, {STORM_PER_HOUR} "
            "per hour or more: each rebalance stops the processing (look at the members that join and leave, session.timeout.ms, "
            "heartbeat.interval.ms, max.poll.interval.ms, scheduled.rebalance.max.delay.ms).</p><table><tr><th></th><th>What</th>"
            "<th>Group / connector</th><th class='num'>Count</th><th class='num'>Per hour</th><th>When</th><th>Reason, connector</th></tr>"
            f"{rows}</table></div>")


def config_lint(res: dict) -> List[dict]:
    """risky or unusual values in the configuration each connector and its clients logged at startup (the last dump of
    each): a sink skipping bad records without a dead letter queue, a poll loop that can exceed max.poll.interval.ms, a
    source producer without acks=all…, with what to do"""
    latest: Dict[Tuple[str, str], Tuple["OrderedDict[str, str]", dict]] = {}
    for c in res.get("configuration") or []:
        name = config_connector_of(c)
        if not name:
            continue
        cid = c.get("id") or ""
        if c["title"] in ("SinkConnectorConfig", "SourceConnectorConfig", "ConnectorConfig", "connector config"):
            kind = "sink" if c["title"] == "SinkConnectorConfig" else "connector"
        elif c["title"] == "ConsumerConfig" and cid.startswith("connector-consumer-"):
            kind = "consumer"
        elif c["title"] == "ProducerConfig" and cid.startswith("connector-producer-"):
            kind = "producer"
        else:
            continue
        values = config_values(c)
        if kind == "connector" and (values.get("topics") or values.get("topics.regex")):
            kind = "sink"
        latest[(name, kind)] = (values, c)
    out: List[dict] = []

    def add(name, c, severity, key, value, message):
        out.append({"connector": name, "severity": severity, "key": key, "value": value, "message": message,
                    "file": c.get("file"), "line": c.get("line")})
    empty = ("", "null", "[]")
    for (name, kind), (v, c) in latest.items():
        if kind == "sink":
            if v.get("errors.tolerance") == "all" and v.get("errors.deadletterqueue.topic.name", "") in empty:
                add(name, c, "MEDIUM", "errors.tolerance", "all", "bad records are skipped and lost: no dead letter queue "
                    "(errors.deadletterqueue.topic.name), set one to keep them and read it with playground topic dlq inspect")
            if v.get("errors.deadletterqueue.topic.name", "") not in empty and v.get("errors.deadletterqueue.topic.replication.factor") == "1":
                add(name, c, "LOW", "errors.deadletterqueue.topic.replication.factor", "1",
                    "the dead letter queue has one replica: its records are lost with that broker")
        if kind in ("sink", "connector"):
            if v.get("errors.tolerance") == "all" and v.get("errors.log.enable") == "false" and not (
                    kind == "sink" and v.get("errors.deadletterqueue.topic.name", "") not in empty):
                add(name, c, "LOW", "errors.log.enable", "false", "with errors.tolerance=all, the records skipped are not "
                    "even logged: set errors.log.enable=true (and errors.log.include.messages=true to see them)")
        if kind == "consumer":
            try:
                records, interval = int(v.get("max.poll.records", "0")), int(v.get("max.poll.interval.ms", "300000"))
            except ValueError:
                records, interval = 0, 300000
            if records >= 5000 and interval <= 300000:
                add(name, c, "MEDIUM", "max.poll.records", str(records), f"{records} records per poll with "
                    f"max.poll.interval.ms={interval}: a slow put() of the batch makes the consumer leave its group (rebalances, "
                    "commits failing): lower consumer.override.max.poll.records or raise consumer.override.max.poll.interval.ms")
            if v.get("auto.offset.reset") == "latest":
                add(name, c, "LOW", "auto.offset.reset", "latest", "without committed offsets (a new connector, offsets "
                    "deleted), the records already in the topic are skipped: Connect sinks default to earliest")
        if kind == "producer" and v.get("acks") not in (None, "", "all", "-1"):
            add(name, c, "MEDIUM", "acks", v.get("acks"), "the source producer does not wait for all the in-sync replicas: "
                "records can be lost when a broker fails; Connect defaults to acks=all")
    order = {"HIGH": 0, "MEDIUM": 1, "LOW": 2}
    out.sort(key=lambda x: (order.get(x["severity"], 9), x["connector"]))
    return out


def config_lint_text(items: List[dict], top: int = 8) -> List[str]:
    if not items:
        return []
    out = [f"🧪 Config lint ({len(items)}, the configuration logged at startup)"]
    for x in items[:top]:
        out.append(f"   [{x['severity']}] {x['connector']}: {x['key']}={x['value']} → {x['message']}")
    if len(items) > top:
        out.append(f"   … {len(items) - top} more on the 🔌 cards of the HTML report and in .config_lint of --json")
    return out


def kafka_versions(files: List[dict]) -> List[str]:
    """the Kafka / Confluent Platform versions of the logs ("Kafka version: 8.3.2-ce" of AppInfoParser), in order"""
    out: List[str] = []
    for f in files:
        for ev in f.get("events") or []:
            if ev["kind"] == "kafka_version" and ev["detail"] and ev["detail"] not in out:
                out.append(ev["detail"])
    return out


def changelog_command(c: dict) -> str:
    """what changed in the connector plugin since the version it runs (is it fixed in a newer version?)"""
    return (f"playground connector-plugin changelog --connector-plugin {c['class']} --from {c['versions'][-1]}"
            if c.get("class") and c.get("versions") else "")


# connector cards shown before "show the other N connectors" (a worker with 485 connectors: a wall of cards)
CONN_CARDS_SHOWN = 30


def connectors_health_html(cards: List[dict]) -> str:
    """the 🔌 Connectors section: a card per connector, ▶ only this connector sets the connector filter"""
    if not cards:
        return ""
    items = []
    for c in cards:
        errors = c["by_level"]["FATAL"] + c["by_level"]["ERROR"]
        state = ("danger", "🧨 task killed") if c["task_killed"] else ("danger", "🔴 errors") if errors else \
            ("warn", "🟠 warnings only") if c["by_level"]["WARN"] else ("ok", "✅")
        counts = " · ".join(f"{icon} {c['by_level'][lvl]:,} {lvl}" for lvl, icon in LEVEL_PILLS if c["by_level"].get(lvl))
        period = period_text(c["first_timestamp"], c["last_timestamp"]) if c["first_timestamp"] else "no timestamp"
        changes = "".join(f"<li class='mono'>{e((ch['time'] or '').replace('T', ' '))} {e(ch['config'])}: {e(ch['key'])} "
                          f"{e(ch['previous'] or '∅')} → {e(ch['value'] or '∅')}</li>" for ch in c["config_changes"][:8])
        more = f"<li class='fi-meta'>+{len(c['config_changes']) - 8} more</li>" if len(c["config_changes"]) > 8 else ""
        items.append(
            f"<div class='conn-card {state[0]}' data-conn='{e(c['connector'])}'><div class='conn-head'><span class='fi-conn'>{e(c['connector'])}</span> "
            f"<span class='conn-state'>{state[1]}</span><button type='button' class='pill conn-only' data-conn='{e(c['connector'])}' "
            f"title='show only the records, root causes, timeline and chart of this connector'>▶ only this connector</button></div>"
            f"<div class='fi-meta'>{counts} in {c['records']} distinct record(s) · {e(period)}"
            + (f" · 🧨 {c['task_killed']} task kill(s)" if c["task_killed"] else "") + "</div>"
            + (f"<div class='fi-meta'>🏷️ {e(' → '.join(c['versions']))} · <span class='mono' title='{e(c.get('class', ''))}'>"
               f"{e(c.get('class', '').split('.')[-1])}</span> · <button type='button' class='pill conn-changelog' "
               f"data-cmd='{e(changelog_command(c))}' title='copy the command that lists what changed in the plugin since "
               f"this version: is it fixed in a newer version?'>📋 changelog since {e(c['versions'][-1])}</button></div>"
               if c.get("versions") else "")
            + (f"<div>🧠 {e(' · '.join(c['known_causes'][:6]))}</div>" if c["known_causes"] else "")
            + (f"<details class='conn-lint'><summary>🧪 {len(c['config_lint'])} config warning(s)</summary><ul>"
               + "".join(f"<li><span class='st {x['severity'].lower()}'>{x['severity']}</span> <span class='mono'>{e(x['key'])}={e(x['value'])}</span>: {e(x['message'])}</li>"
                         for x in c["config_lint"]) + "</ul></details>" if c.get("config_lint") else "")
            + ("<div class='fi-meta'>🔄 " + " · ".join(x for x in [
                f"{c['connector_starts']} connector start(s)" if c.get("connector_starts") else "",
                f"{c['task_starts']} task start(s)" if c.get("task_starts") else "",
                f"{c['consumer_rejoins']} consumer group rejoin(s)" if c.get("consumer_rejoins") else ""] if x) + "</div>"
               if c.get("connector_starts") or c.get("task_starts") or c.get("consumer_rejoins") else "")
            + (f"<div class='fi-meta'>⚙️ {c['config_dumps']} configuration dump(s)"
               + (f", clients: <span class='mono'>{e(', '.join(c['clients'][:6]))}</span>" if c["clients"] else "") + "</div>"
               if c["config_dumps"] else "")
            + (f"<details><summary>🔁 {len(c['config_changes'])} key(s) changed between restarts</summary><ul>{changes}{more}</ul></details>"
               if c["config_changes"] else "")
            + "</div>")
    return ("<style>.conn-cards{display:grid;grid-template-columns:repeat(auto-fill,minmax(330px,1fr));gap:10px}"
            ".conn-card{border:1px solid #e2e8f0;border-left:5px solid #94a3b8;border-radius:8px;padding:8px 12px;font-size:.84rem}"
            ".conn-card.danger{border-left-color:#dc2626}.conn-card.warn{border-left-color:#d97706}.conn-card.ok{border-left-color:#16a34a}"
            ".conn-head{display:flex;align-items:center;gap:8px;flex-wrap:wrap;margin-bottom:4px}.conn-only{margin-left:auto;font-size:.72rem}"
            "html[data-theme=dark] .conn-card{border-color:#334155}.conn-card[hidden]{display:none}"
            ".conn-note{font-weight:600}.conn-note[hidden],.conn-more[hidden]{display:none}.conn-more{margin-top:10px}</style>"
            f"<div class='table-card'><h2>🔌 Connectors ({len(cards)})</h2><p class='legend'>One card per connector of the logs "
            "(the [connector|task-0] context of the lines): its errors and warnings, the known causes of its records, a task "
            "killed, its configuration and the keys changed between restarts. ▶ only this connector filters the report on it (and "
            f"hides the other cards), ⤺ goes back to all of them; the search box filters the cards too. The {CONN_CARDS_SHOWN} "
            "with the most errors are shown first.</p><p class='legend conn-note' hidden></p>"
            f"<div class='conn-cards'>{''.join(items)}</div>"
            "<button type='button' class='pill conn-more' hidden></button></div>")


def connectors_text(cards: List[dict], top: int = 6) -> List[str]:
    if not cards:
        return []
    out = [f"🔌 Connectors ({len(cards)}, most errors first)"]
    for c in cards[:top]:
        lv = c["by_level"]
        bits = [f"{lv['FATAL'] + lv['ERROR']} ERROR/FATAL", f"{lv['WARN']} WARN"]
        if c["task_killed"]:
            bits.append(f"🧨 {c['task_killed']} task kill(s)")
        if c["config_changes"]:
            bits.append(f"🔁 {len(c['config_changes'])} config key(s) changed")
        if c.get("versions"):
            bits.append(f"🏷️ {' → '.join(c['versions'])} ({c.get('class', '').split('.')[-1]})")
        out.append(f"   {c['connector']}: {', '.join(bits)}" + (f" · {', '.join(c['known_causes'][:3])}" if c["known_causes"] else ""))
        if changelog_command(c) and (lv["FATAL"] + lv["ERROR"]):
            out.append(f"      👉 fixed in a newer version? {changelog_command(c)}")
    return out


# a root cause, a known cause or a connector changed when its count (per hour when both inputs have a period) is at
# least this ratio higher or lower; and at least COMPARE_MIN_DELTA occurrences apart (1 → 2 is not "growing")
COMPARE_RATIO = 1.5
COMPARE_MIN_DELTA = 3


def compare_reports(res: dict, prev: dict, label: str) -> dict:
    """what changed between the analysis of another input (prev, the JSON of analyze logs: the logs before a fix, another
    worker, the day before) and this one: root causes, known causes and connectors new, gone, growing or shrinking, and
    the totals by level. Counts per hour when both inputs have a period (an input of 2 h against one of 10 min)"""
    s, ps = res["summary"], prev.get("summary") or {}
    hours, phours = (s.get("log_duration_seconds") or 0) / 3600, (ps.get("log_duration_seconds") or 0) / 3600
    per_hour = hours > 0 and phours > 0 and abs(hours - phours) / max(hours, phours) > 0.1

    def rate(n, h):
        return n / h if per_hour else n

    def classify(now, before, h_now, h_before):
        if before == 0 and now > 0:
            return "new"
        if now == 0 and before > 0:
            return "gone"
        a, b = rate(now, h_now), rate(before, h_before)
        if abs(now - before) >= COMPARE_MIN_DELTA and a >= b * COMPARE_RATIO:
            return "growing"
        if abs(now - before) >= COMPARE_MIN_DELTA and a * COMPARE_RATIO <= b:
            return "shrinking"
        return "same"

    def diff(cur: Dict[str, dict], old: Dict[str, dict], extra=lambda c: {}) -> List[dict]:
        out = []
        for key in list(cur) + [k for k in old if k not in cur]:
            n, b = (cur.get(key) or {}).get("occurrences", 0), (old.get(key) or {}).get("occurrences", 0)
            item = dict({"key": key, "status": classify(n, b, hours, phours), "occurrences": n, "before": b},
                        **extra(cur.get(key) or old.get(key)))
            if per_hour:
                item["per_hour"], item["before_per_hour"] = round(n / hours, 2), round(b / phours, 2)
            out.append(item)
        order = {"new": 0, "growing": 1, "shrinking": 2, "gone": 3, "same": 4}
        out.sort(key=lambda x: (order[x["status"]], -max(x["occurrences"], x["before"])))
        return out

    root_causes = diff({c["label"]: c for c in res["root_causes"]}, {c["label"]: c for c in prev.get("root_causes") or []},
                       lambda c: {"level": c.get("level"), "root_cause": c.get("root_cause"), "example": c.get("example", "")[:300],
                                  "index": next((i for i, x in enumerate(res["root_causes"]) if x["label"] == c["label"]), None)})
    known = diff({h["title"]: h for h in res["known_causes"]}, {h["title"]: h for h in prev.get("known_causes") or []},
                 lambda h: {"severity": h.get("severity")})
    connectors = diff({n: {"occurrences": v} for n, v in (s.get("by_connector") or {}).items()},
                      {n: {"occurrences": v} for n, v in (ps.get("by_connector") or {}).items()})
    totals = {lvl: {"now": (s.get("by_level") or {}).get(lvl, 0), "before": (ps.get("by_level") or {}).get(lvl, 0)}
              for lvl in ("FATAL", "ERROR", "WARN")}
    count = lambda items, st: sum(1 for x in items if x["status"] == st)
    return {"label": label, "per_hour": per_hour,
            "period": {"now": period_text(s.get("log_first_timestamp"), s.get("log_last_timestamp")),
                       "now_seconds": s.get("log_duration_seconds"),
                       "before": period_text(ps.get("log_first_timestamp"), ps.get("log_last_timestamp")),
                       "before_seconds": ps.get("log_duration_seconds")},
            "totals": totals,
            "counts": {st: count(root_causes, st) for st in ("new", "gone", "growing", "shrinking", "same")},
            "root_causes": root_causes, "known_causes": known, "connectors": connectors}


COMPARE_ICONS = {"new": "🆕", "growing": "📈", "shrinking": "📉", "gone": "✅", "same": "＝"}
TREND_ROWS = 12


def trend(res: dict, prevs: List[dict], labels: List[str], title: str) -> dict:
    """the totals and the main root causes of every input, oldest first (--compare given several times, then this one):
    per hour when their periods differ by more than 10 %"""
    points = [(labels[i], p.get("summary") or {}, p.get("root_causes") or []) for i, p in enumerate(prevs)]
    points.append((title or "now", res["summary"], res["root_causes"]))
    hours = [(s.get("log_duration_seconds") or 0) / 3600 for _, s, _ in points]
    per_hour = all(h > 0 for h in hours) and (max(hours) - min(hours)) / max(hours) > 0.1

    def value(n, h):
        return round(n / h, 2) if per_hour else n
    totals = {lvl: [value((s.get("by_level") or {}).get(lvl, 0), hours[i]) for i, (_, s, _) in enumerate(points)]
              for lvl in ("FATAL", "ERROR", "WARN")}
    counts: Dict[str, List[float]] = {}
    meta: Dict[str, dict] = {}
    for i, (_, _, causes) in enumerate(points):
        for c in causes:
            counts.setdefault(c["label"], [0] * len(points))[i] = value(c.get("occurrences", 0), hours[i])
            meta.setdefault(c["label"], {"root_cause": c.get("root_cause"), "example": c.get("example", ""), "level": c.get("level")})
    rows = [dict(meta[k], key=k, values=v) for k, v in counts.items()]
    # the most frequent now first, then the ones that were frequent before (gone)
    rows.sort(key=lambda r: (-r["values"][-1], -max(r["values"])))
    return {"labels": [p[0] for p in points], "per_hour": per_hour, "totals": totals, "root_causes": rows[:TREND_ROWS],
            "more": max(0, len(rows) - TREND_ROWS)}


def trend_values(values: List[float]) -> str:
    return " → ".join(f"{v:g}" for v in values)


def trend_text(tr: Optional[dict], top: int = 6) -> List[str]:
    if not tr:
        return []
    out = [f"📈 Trend over {len(tr['labels'])} inputs (oldest first: {' → '.join(tr['labels'])})" + (" per hour" if tr["per_hour"] else "")]
    out.append("   " + " · ".join(f"{lvl} {trend_values(tr['totals'][lvl])}" for lvl in ("FATAL", "ERROR", "WARN")))
    for r in tr["root_causes"][:top]:
        what = f"{r['root_cause'].split('.')[-1]}: {r['example']}" if r.get("root_cause") else r.get("example") or r["key"]
        out.append(f"   {trend_values(r['values'])}  {what[:140]}")
    return out


def trend_html(tr: Optional[dict]) -> str:
    if not tr:
        return ""
    head = "".join(f"<th class='num' title='{e(l)}'>{e(l.split('/')[-1][:24])}</th>" for l in tr["labels"])

    def cells(values):
        out, prev = [], None
        for v in values:
            arrow = "" if prev is None else (" 📈" if v > prev else " 📉" if v < prev else "")
            out.append(f"<td class='num'>{v:g}{arrow}</td>")
            prev = v
        return "".join(out)
    rows = "".join(f"<tr><td><b>{lvl}</b></td>{cells(tr['totals'][lvl])}</tr>" for lvl in ("FATAL", "ERROR", "WARN"))
    rows += "".join(f"<tr><td class='mono'>{e((r.get('root_cause') or '—').split('.')[-1])} {e((r.get('example') or r['key'])[:160])}</td>{cells(r['values'])}</tr>"
                    for r in tr["root_causes"])
    return (f"<div class='table-card'><h2>📈 Trend over {len(tr['labels'])} inputs</h2><p class='legend'>Oldest first (the inputs of "
            "--compare in the order given, then this one): the totals by level and the main root causes"
            + (", per hour (the periods differ)" if tr["per_hour"] else "") + (f"; {tr['more']} more root causes in .trend of --json" if tr["more"] else "")
            + f".</p><table><tr><th>What</th>{head}</tr>{rows}</table></div>")


def compare_counts(x: dict) -> str:
    """the counts before and now (1 → 7), and the rates when the comparison is per hour (6.7/h → 0.3/h)"""
    out = f"{x['before']:,} → {x['occurrences']:,}"
    if "per_hour" in x:
        out += f" ({x['before_per_hour']:g}/h → {x['per_hour']:g}/h)"
    return out


def compare_verdict(cmp: dict) -> str:
    c = cmp["counts"]
    kc_new = [x["key"] for x in cmp["known_causes"] if x["status"] == "new"]
    kc_gone = [x["key"] for x in cmp["known_causes"] if x["status"] == "gone"]
    out = (f"🔁 Compared with {cmp['label']}: {c['new']} new root cause(s), {c['growing']} growing, {c['shrinking']} "
           f"shrinking, {c['gone']} gone, {c['same']} unchanged" + (" (per hour: the periods differ)" if cmp["per_hour"] else ""))
    if kc_new:
        out += f" · new known cause(s): {', '.join(kc_new[:4])}"
    if kc_gone:
        out += f" · gone: {', '.join(kc_gone[:4])}"
    return out


def compare_text(cmp: Optional[dict], top: int = 6) -> List[str]:
    if not cmp:
        return []
    out = [compare_verdict(cmp)]
    t = cmp["totals"]
    out.append("   " + " · ".join(f"{lvl} {t[lvl]['before']} → {t[lvl]['now']}" for lvl in ("FATAL", "ERROR", "WARN"))
               + f" · period {human_duration(cmp['period']['before_seconds'])} → {human_duration(cmp['period']['now_seconds'])}")
    for x in [x for x in cmp["root_causes"] if x["status"] != "same"][:top]:
        what = f"{x['root_cause'].split('.')[-1]}: {x['example']}" if x.get("root_cause") else x["example"] or x["key"]
        out.append(f"   {COMPARE_ICONS[x['status']]} {x['status']:<9} {compare_counts(x)} {what[:160]}")
    return out


def compare_html(cmp: Optional[dict]) -> str:
    """the 🔁 Comparison section, right after the verdict"""
    if not cmp:
        return ""

    def rows(items, link):
        out = []
        for x in items:
            what = (f"<span class='mono'>{e((x.get('root_cause') or '—').split('.')[-1])}</span> {e(x.get('example') or x['key'])}"
                    if "example" in x else e(x["key"]))
            if link and x.get("index") is not None:
                what = f"<a href='#root-cause-{x['index']}' title='its row in 🌳 All root causes'>{what}</a>"
            rates = "per_hour" in x
            out.append(f"<tr class='cmp-{x['status']}'><td>{COMPARE_ICONS[x['status']]} {x['status']}</td>"
                       f"<td class='num'>{x['before']:,}" + (f"<br><span class='fi-meta'>{x['before_per_hour']:g}/h</span>" if rates else "") + "</td>"
                       f"<td class='num'>{x['occurrences']:,}" + (f"<br><span class='fi-meta'>{x['per_hour']:g}/h</span>" if rates else "") + "</td>"
                       f"<td>{what}</td></tr>")
        return "".join(out)

    def table(title, items, link=False):
        changed, same = [x for x in items if x["status"] != "same"], [x for x in items if x["status"] == "same"]
        if not items:
            return ""
        head = "<tr><th></th><th class='num'>Before</th><th class='num'>Now</th><th>What</th></tr>"
        out = f"<h3>{title}</h3>"
        out += f"<table>{head}{rows(changed, link)}</table>" if changed else "<p class='legend'>No change.</p>"
        if same:
            out += f"<details><summary>{len(same)} unchanged</summary><table>{head}{rows(same, link)}</table></details>"
        return out
    t = cmp["totals"]
    tiles = "".join(f"<span class='cmp-tile'>{lvl} <b>{t[lvl]['before']:,} → {t[lvl]['now']:,}</b></span>" for lvl in ("FATAL", "ERROR", "WARN"))
    return ("<style>.cmp-tile{display:inline-block;margin:0 14px 6px 0;font-size:.85rem}tr.cmp-new td,tr.cmp-growing td{background:#fef2f2}"
            "tr.cmp-gone td,tr.cmp-shrinking td{background:#f0fdf4}html[data-theme=dark] tr.cmp-new td,html[data-theme=dark] tr.cmp-growing td{background:#3b1515}"
            "html[data-theme=dark] tr.cmp-gone td,html[data-theme=dark] tr.cmp-shrinking td{background:#0f2a1a}.cmp h3{font-size:.92rem;margin:14px 0 4px}</style>"
            f"<div class='table-card cmp'><h2>🔁 Comparison with {e(cmp['label'])}</h2><p class='legend'>{e(compare_verdict(cmp))}. "
            f"Before: {e(cmp['period']['before'])} ({e(human_duration(cmp['period']['before_seconds']))}); now: "
            f"{e(cmp['period']['now'])} ({e(human_duration(cmp['period']['now_seconds']))})."
            + (" Growing and shrinking compare the counts per hour, the two inputs covering different periods." if cmp["per_hour"] else "")
            + f" A change is at least ×{COMPARE_RATIO} and {COMPARE_MIN_DELTA} occurrences.</p><div>{tiles}</div>"
            + table("🌳 Root causes", cmp["root_causes"], link=True) + table("🧠 Known causes", cmp["known_causes"])
            + table("🔌 Connectors", cmp["connectors"]) + "</div>")


TIMELINE_ICONS = {"FATAL": "💀", "ERROR": "🔴", "WARN": "🟠", "CRITICAL": "🧠", "HIGH": "🧠", "MEDIUM": "🧠", "LOW": "🧠"}


def timeline_what(ev: dict) -> str:
    """the text of an event: the known causes first (what it means), then the error itself"""
    if ev["kind"] == "known_cause":
        return " · ".join(ev["known_causes"])
    if ev["kind"] == "first_error":
        icon = TIMELINE_ICONS.get(ev["level"], "")
        what = f"{icon} first {ev['level']}: {ev['text']}"
        return (" · ".join(ev["known_causes"]) + " ⬅️ " + what) if ev.get("known_causes") else what
    return ev["text"]


def timeline_html(events: List[dict], viewers: Dict[str, str], shown: int = 30) -> str:
    """the 🗓️ Incident timeline card: the first `shown` events, the others in a <details>"""
    if not events:
        return ""

    def row(ev):
        where = log_viewer.link(viewers, ev["file"], e(f"{ev['file'].split('/')[-1]}:{ev['line']}"), ev["line"]) if ev.get("line") else e(ev["file"])
        cls = "tl-known" if ev.get("known_causes") else f"tl-{ev['kind']}"
        # what the filters of the report need: level, connector, time, record (the search reads the record block)
        attrs = (f" data-level='{LEVEL_ORDER.get(ev['level'], '')}'" if ev["kind"] == "first_error" else "") \
            + (f" data-conn='{e(ev['connector'])}'" if ev.get("connector") else "") \
            + f" data-t='{epoch(ev['time'])}'" + (f" data-rec='{ev['record']}'" if ev.get("record") is not None else "")
        return (f"<tr class='tl-row {cls}' data-component='{file_component(ev['file'])}'{attrs}><td class='mono'>{e(ev['time'].replace('T', ' '))}</td>"
                f"<td>{component_chips([ev['file']])}</td><td>{e(timeline_what(ev))}"
                + (f" <span class='fi-conn'>{e(ev['connector'])}</span>" if ev.get("connector") else "")
                + (f" <span class='fi-meta'>×{ev['count']}</span>" if ev.get("count") else "")
                + (f"<div class='tl-after'>🔗{e(after_text(ev))}</div>" if ev.get("after") else "")
                + f"</td><td class='mono'>{where}</td></tr>")
    head = "<tr><th>Time</th><th>Component</th><th>What</th><th>Where</th></tr>"
    first = "".join(row(ev) for ev in events[:shown])
    more = ""
    if len(events) > shown:
        more = (f"<details><summary>{len(events) - shown} more event(s)</summary><table>{head}"
                + "".join(row(ev) for ev in events[shown:]) + "</table></details>")
    return ("<style>.tl-after{font-size:.8rem;font-weight:600;color:#b45309}html[data-theme=dark] .tl-after{color:#fcd34d}tr.tl-known td{background:#fff7ed}tr.tl-start td,tr.tl-connector_config td{background:#f0f9ff}"
            "tr.tl-config_change td{background:#fefce8}html[data-theme=dark] tr.tl-known td{background:#3a2406}"
            "html[data-theme=dark] tr.tl-start td,html[data-theme=dark] tr.tl-connector_config td{background:#0c2a3a}"
            "html[data-theme=dark] tr.tl-config_change td{background:#33300a}</style>"
            "<div class='table-card'><h2>🗓️ Incident timeline</h2><p class='legend'>What happened first, all files merged: "
            "the first occurrence of each error and of each known cause, the (re)starts of the components (their config "
            "logged at startup), the connectors (re)configured and the config keys changed between restarts. It follows the "
            "filters above (levels, component, connector, search, period): the rows of the other connectors are hidden, "
            "the restarts and configurations without connector stay.</p><p class='legend tl-none' hidden>No event in this selection.</p>"
            f"<table>{head}{first}</table>{more}</div>")


def causes_text(events: List[dict], top: int = 5) -> List[str]:
    linked = [ev for ev in events if ev.get("after")]
    if not linked:
        return []
    out = [f"🔗 Errors right after a change ({len(linked)})"]
    for ev in linked[:top]:
        out.append(f"   {ev['time'].replace('T', ' ')} {timeline_what(ev)[:150]}{after_text(ev)}")
    return out


def timeline_text(events: List[dict], top: int = 8) -> List[str]:
    if not events:
        return []
    out = [f"🗓️ Timeline (first {min(top, len(events))} of {len(events)} event(s), all files merged)"]
    for ev in events[:top]:
        out.append(f"   {ev['time'].replace('T', ' ')} {timeline_what(ev)[:160]} ({ev['file'].split('/')[-1]}:{ev['line']})")
    return out


# ── Text (terminal digest of playground analyze logs) ────────────────────────

def config_inventory(configs: List[dict]) -> List[str]:
    """one line per group of configs (connector, components, clients, files): what was logged"""
    groups: Dict[Tuple[int, str], List[dict]] = {}
    for c in configs:
        groups.setdefault(config_group(c), []).append(c)
    out = []
    for group in sorted(groups):
        titles = OrderedDict()
        for c in groups[group]:
            titles[c["title"]] = titles.get(c["title"], 0) + 1
        names = [t + (f" ×{n}" if n > 1 else "") for t, n in titles.items()]
        out.append(f"{group[1]}: " + ", ".join(names[:8]) + (f" (+{len(names) - 8} more)" if len(names) > 8 else ""))
    return out


def config_changes_lines(configs: List[dict], top: int = 10) -> List[str]:
    """keys whose value changed between two dumps of the same config (a restart with another config), the same change
    of the same config once, with the number of times and the first one"""
    groups: Dict[Tuple[str, str, str, str], dict] = OrderedDict()
    for c in configs:
        who = " ".join(x for x in (c.get("context"), c.get("id")) if x)
        for ch in c.get("changes", []):
            g = groups.setdefault((f"{c['title']} {who}", ch["key"], ch["previous"], ch["value"]), {"n": 0, "first": ch})
            g["n"] += 1
    out = []
    for (config, key, previous, value), g in groups.items():
        ch = g["first"]
        where = f"line {ch['line']}" if ch.get("line") else ""
        if ch.get("time"):
            where += f" ({ch['time'].replace('T', ' ')})"
        out.append(f"{config}: {key} {previous[:80]} → {value[:80]}" + (f" ×{g['n']}" if g["n"] > 1 else "")
                   + (f" · first {where}" if where else ""))
    if len(out) > top:
        out = out[:top] + [f"… {len(out) - top} more (--show-config <connector|config class|client id>, or the HTML report)"]
    return out


def time_zone_note(s: dict) -> str:
    """"" when the times are as written in the logs, else what normalize_times did"""
    tz = s.get("time_zone") or {}
    if not tz.get("converted_to_utc"):
        return ""
    return (f"🌐 times in UTC: the files mix the offsets {', '.join(tz['offsets'])}"
            + (" (the lines without an offset are as written)" if tz.get("without_offset") else ""))


def text_summary(res: dict, connectors: List[str], top: int = 5) -> str:
    """bounded summary printed after the per-file digests: what the HTML report says first (time range, connectors,
    known causes with what to do, root causes no known cause explains, configuration logged and its changes)"""
    s = res["summary"]
    out = []
    span = ""
    if s["first_timestamp"]:
        span = ", " + s["first_timestamp"].replace("T", " ")
        if s["last_timestamp"] and s["last_timestamp"] != s["first_timestamp"]:
            span += " → " + s["last_timestamp"].replace("T", " ")
    scope = f" (--connector {' '.join(connectors)})" if connectors else ""
    out.append(f"🧭 Summary{scope}: {s['occurrences']} occurrence(s) of {s['distinct']} distinct record(s) in "
               f"{s['files_with_findings']} file(s){span}")
    # what the logs themselves cover, and whether that window is wide enough to hold the context of an incident
    if s["log_duration_seconds"] is not None:
        covered = f"   🕐 Period covered: {period_text(s['log_first_timestamp'], s['log_last_timestamp'])} ({human_duration(s['log_duration_seconds'])})"
        if s["log_duration_seconds"] < SHORT_PERIOD_SECONDS:
            covered += f" ⚠️ shorter than {human_duration(SHORT_PERIOD_SECONDS)}: the logs may not cover the incident"
        out.append(covered)
    if time_zone_note(s):
        out.append("   " + time_zone_note(s))
    if s.get("kafka_versions"):
        out.append(f"   🏷️ Kafka {' → '.join(s['kafka_versions'])} (the version the components log at startup)")
    gaps = (res.get("coverage") or {}).get("gaps") or []
    if gaps:
        biggest = max(gaps, key=lambda g: g["seconds"])
        out.append(f"   🕰️ {len(gaps)} period(s) without logs in a folder of rotated logs, the longest "
                   f"{period_text(biggest['from'], biggest['to'])} ({human_duration(biggest['seconds'])}) in "
                   f"{biggest['folder'] or 'the input'}: what happened then is not in the input (🕰️ Log coverage of the HTML report)")
    if s["by_connector"]:
        without = sum(r["count"] for f in res["files"] for r in f["records"] if not r.get("connector"))
        names = list(s["by_connector"].items())
        line = ", ".join(f"{n} {c}" for n, c in names[:10]) + (f" (+{len(names) - 10} more)" if len(names) > 10 else "")
        out.append(f"   🔌 by connector: {line}" + (f" · no connector context {without}" if without else ""))
    if res["known_causes"]:
        out.append("🧠 Known causes")
        for h in res["known_causes"][:8]:
            out.append(f"   [{h['severity']}] {h['title']} ×{h['occurrences']} {h['where']}")
            out.append(f"      → {h['advice']}")
            for read in reading_list(h):
                out.append(f"      📚 {read}")
            for d in h.get("details", [])[:5]:
                out.append(f"      {d}")
    # same test as the 🌳 cards of the HTML report: not explained by a known cause (records in common, or its pattern)
    others = [c for c in res["root_causes"] if not c.get("explained_by")]
    if others:
        out.append("🌳 Root causes not explained by a known cause" + (f" (top {top} of {len(others)})" if len(others) > top else ""))
        for c in others[:top]:
            what = f"{c['root_cause'].split('.')[-1]}: {c['example']}" if c["root_cause"] else c["example"]
            who = f" · {len(c['connectors'])} connector(s): {first_names(c['connectors'])}" if c["connectors"] else ""
            out.append(f"   {c['level']} ×{c['occurrences']} {what[:220]}{who}")
    # what changed against the input of --compare (🔁 Comparison of the HTML report, .comparison of --json)
    out += compare_text(res.get("comparison"))
    # several --compare: the trend over all the inputs (📈 Trend of the HTML report, .trend of --json)
    out += trend_text(res.get("trend"))
    # the errors that came right after a change (🔗 in the timeline of the HTML report, .timeline[].after of --json)
    out += causes_text(res.get("timeline") or [])
    # what happened first, all files merged (🗓️ Incident timeline of the HTML report, .timeline of --json)
    out += timeline_text(res.get("timeline") or [])
    # one line per connector (🔌 Connectors of the HTML report, .connectors of --json)
    out += connectors_text(res.get("connectors") or [])
    # rebalances and restarts of the INFO lines (🔄 of the HTML report, .lifecycle of --json)
    out += lifecycle_text(res.get("lifecycle"))
    # risky values of the configuration logged (🧪 on the 🔌 cards, .config_lint of --json)
    out += config_lint_text(res.get("config_lint") or [])
    configs = res.get("configuration") or []
    if configs:
        out.append(f"⚙️ Configuration logged ({len(configs)}), the last dump of each: --show-config <connector|config class|client id> prints one")
        out += [f"   {line}" for line in config_inventory(configs)]
        changes = config_changes_lines(configs)
        if changes:
            out.append("   🔁 changed between restarts:")
            out += [f"      {line}" for line in changes]
    return "\n".join(out)


def config_block_text(c: dict, also: List[str] = ()) -> List[str]:
    """one config as key = value lines, with its changes"""
    where = c["file"] + (f":{c['line']}" if c.get("line") else "") + (f" ({c['time'].replace('T', ' ')})" if c.get("time") else "")
    who = " ".join(x for x in (c.get("context"), c.get("id")) if x)
    keys = c["text"].splitlines()
    out = [f"⚙️ {c['title']} {who} · {len(keys)} keys · {where}"]
    if also:
        out.append(f"   (also logged, contained in this one: {', '.join(also)})")
    out += [f"   {k.replace('=', ' = ', 1)}" for k in keys]
    out += [f"   🔁 {line}" for line in config_changes_lines([c], top=50)]
    return out + [""]


def show_config(res: dict, name: str) -> str:
    """--show-config: for a connector, its own configs (the ones contained in a bigger one with the same values are
    only named, its clients summed up in one line); for a config class (ProducerConfig) or a client id, every match"""
    wanted = name.lower()
    every = res.get("configuration") or []
    mine = [c for c in every if (config_connector(c) or "").lower() == wanted]
    if mine:
        own = [c for c in mine if c["title"] not in CLIENT_CONFIGS]
        clients = [c for c in mine if c["title"] in CLIENT_CONFIGS]
        items = [(c, dict(line.split("=", 1) for line in c["text"].splitlines() if "=" in line)) for c in own]
        # biggest first: a config whose keys and values are all in a bigger one is the same config logged again
        items.sort(key=lambda it: -len(it[1]))
        kept: List[Tuple[dict, dict, List[str]]] = []
        for c, kv in items:
            container = next((k for k in kept if all(k[1].get(key) == v for key, v in kv.items())), None)
            if container is not None and not c.get("changes"):
                container[2].append(" ".join(x for x in (c["title"], c.get("context")) if x))
            else:
                kept.append((c, kv, []))
        out = []
        for c, _, also in sorted(kept, key=lambda k: (k[0]["file"], k[0].get("line") or 0)):
            out += config_block_text(c, also)
        if clients:
            ids = [f"{c['title']} {c.get('id') or c.get('context') or ''}".strip() for c in clients]
            out.append(f"📡 {len(clients)} client config(s) of {name}: {', '.join(ids[:10])}"
                       + (f" (+{len(ids) - 10} more)" if len(ids) > 10 else "")
                       + " · --show-config <client id> or <config class> prints one")
        return "\n".join(out).rstrip()
    configs = [c for c in every
               if wanted in ((c.get("id") or "").lower(), c["title"].lower()) or wanted in (c.get("context") or "").lower()]
    if not configs:
        known = sorted({x for c in every for x in (config_connector(c), c["title"]) if x})
        return f"⚙️ no configuration logged for {name}" + (f" (known: {', '.join(known[:30])})" if known else "")
    out = []
    for c in configs:
        out += config_block_text(c)
    return "\n".join(out).rstrip()


# ── HTML ──────────────────────────────────────────────────────────────────────

def timeline(files: List[dict]) -> Tuple[List[tuple], bool]:
    """Occurrences, errors (ERROR + FATAL) and warnings, with their time and weight (the stride of the record: each time
    kept stands for that many occurrences); and whether the times of a record were sampled."""
    points: List[tuple] = []
    sampled = False
    for _, r in all_records(files):
        stride = r.get("ts_stride", 1)
        if stride > 1:
            sampled = True
        for ts in r["timestamps"]:
            try:
                points.append((datetime.strptime(ts, "%Y-%m-%dT%H:%M:%S"), "warnings" if r["level"] == "WARN" else "errors", stride))
            except ValueError:
                pass
    return points, sampled


def cause_label(c: dict) -> str:
    return f"{c['root_cause'].split('.')[-1]}: {c['example']}" if c["root_cause"] else c["label"]


# the component a log file belongs to, from its path and name (the folders of a bundle, the name of a rotated log):
# the Component chips of the filter bar. The first match wins: the specific ones before kafka
FILE_COMPONENTS = [
    ("operator", "☸️ Operator", r"confluent-operator|(^|[/_-])operator([/_.-]|$)"),
    ("ksqldb", "🧮 ksqlDB", r"ksql"),
    ("schemaregistry", "📜 Schema Registry", r"schema[-_]?registry|(^|[/_-])sr[-_]"),
    ("controlcenter", "🛰️ Control Center", r"control[-_]?center|(^|[/_-])c3([/_.-]|$)"),
    ("restproxy", "🌐 REST Proxy", r"rest[-_]?proxy|kafka[-_]rest"),
    ("zookeeper", "🦓 ZooKeeper", r"zookeeper|(^|[/_-])zk([/_.-]|\d|$)"),
    ("streams", "🌊 Kafka Streams", r"kafka[-_]?streams|(^|[/_.-])streams?\d*([/_.-]|$)"),
    ("connect", "🔌 Connect", r"connect|(^|[/_-])cw\d|worker"),
    ("clients", "📡 Clients", r"producer|consumer|client|librdkafka|kafkajs|confluent[-_]kafka|panic|uncaught|python|dotnet|golang|"
                             r"^go[-_](app|client)|rust|node[-_.]?js|^node[-_](app|client)"),
    ("kafka", "🗄️ Kafka", r"kafka|broker|server\.log|controller|state-change|kraft"),
]


def component_chips(labels: List[str]) -> str:
    """the components of the files of a finding or a root cause, as chips (🔌 Connect, 📡 Clients…)"""
    names = {code: name for code, name, _ in FILE_COMPONENTS}
    names["other"] = "📄 Other"
    codes = list(OrderedDict((file_component(x), True) for x in labels or []))
    return "".join(f"<span class='fi-comp' data-component='{code}'>{e(names[code])}</span>" for code in codes)


def file_component(label: str) -> str:
    """the parts of the label from the deepest: the file name (server.log, connect.log), then its folders, then the
    archive it comes from and the folders of the input. The whole label was matched at once: the clients pattern (node)
    took kafka-node-1/server.log, and the name of an archive (acme-connect-bundle.zip:broker/server.log) its brokers"""
    for part in reversed([p for p in re.split(r"[/\\:]", label.lower()) if p]):
        for code, _, pattern in FILE_COMPONENTS:
            if re.search(pattern, part):
                return code
    return "other"


def occurrences_json(causes: List[dict], files: Optional[List[dict]] = None) -> str:
    """Every record of the report as [root cause index, level, connector index, occurrences, epoch seconds, record
    index (data-rec of its block), file index (data-file of its row of the files table), stride (each time stands for
    that many occurrences)]: what the
    📈 occurrences chart, the 🔝 top causes chart, the 🌳 root causes table and the records are all counted again from
    when a level,
    a connector or a period is selected (pgRecords() of FILTER_SCRIPT). The timestamps are here once, not in the chart
    (its "times" is empty, window.pgChartTimes fills it) nor on the rows of the table."""
    names: Dict[str, int] = {}
    records = []
    for i, c in enumerate(causes):
        for level, connector, count, times, index, file_index, stride in c["records_meta"]:
            if connector and connector not in names:
                names[connector] = len(names)
            records.append([i, LEVEL_ORDER.get(level, 9), names[connector] if connector else -1, count,
                            encode_times(times), index, file_index, stride])
    # the component of each file with findings (file index -> code): the Component chips of the filter bar
    components = [file_component(f["label"]) for f in files or []]
    return json.dumps({"connectors": list(names), "records": records, "components": components}, separators=(",", ":"))


def charts_html(files: List[dict], causes: List[dict]) -> str:
    points, capped = timeline(files)
    rows = [(cause_label(c), c["occurrences"], f"{cause_label(c)}: {c['occurrences']} occurrence(s)") for c in causes[:10]]
    # the series are built by pgChartTimes() from the records of the selected levels and connector, not embedded here
    chart = time_chart(points, [("errors", "ERROR/FATAL", SERIES_1), ("warnings", "WARN", SERIES_2)],
                       " · a record of more than 1000 occurrences is sampled over its whole period" if capped else "",
                       # which record levels each series counts, by label (a series without any point is left out)
                       chart_id=TIME_CHART_ID, embed_times=False,
                       extra={"pgLevels": {"ERROR/FATAL": [LEVEL_ORDER["FATAL"], LEVEL_ORDER["ERROR"]],
                                           "WARN": [LEVEL_ORDER["WARN"]]}})
    return charts_grid([("📈 Occurrences over time", chart),
                        ("🔝 Root causes (occurrences)", f"<div class='top-causes'>{svg_hbars(rows)}</div>" if rows else "")])


def level_badge(level: str) -> str:
    return badge(level, level.lower())


NO_CONNECTOR = "-"


def connectors_attr(names: List[str], none: bool = False) -> str:
    """data-connectors of a record or a root cause, for the connector filter: names (no space in them), "-" for none"""
    return " data-connectors='" + e(" ".join(list(names) + ([NO_CONNECTOR] if none or not names else []))) + "'"


def records_html(records: List[dict], open_first: int = 3, highlight: Optional[str] = None,
                 viewers: Optional[Dict[str, str]] = None, label: str = "") -> str:
    """One collapsible block per distinct record; highlight: name that marks the records mentioning it; viewers: label ->
    page of the file (log_viewer), its line numbers link to it. A record with an "index" (set by analyze()) carries it
    as data-rec, and its count is in a .rec-count span: the filters of the report hide it and count it again."""
    viewers = viewers or {}
    out = []
    for i, r in enumerate(records):
        # as the findings: count chip, connector chip, the client context dimmed, the exception class in color, the first
        # and last occurrences as their time with 📄 / ✏️
        when = first_html(viewers, label, r["first_line"], r["first_ts"])
        if r["count"] > 1:
            when += " → " + first_html(viewers, label, r["last_line"], r["last_ts"]).replace(">first ", ">last ", 1)
        mine = " <span class='st mine'>this connector</span>" if highlight and highlight in r["text"] else ""
        conn = f"<span class='fi-conn'>{e(r['connector'])}</span>" if r.get("connector") else ""
        sev = {"FATAL": "critical", "ERROR": "high", "WARN": "medium"}.get(r["level"], "info")
        out.append(f"<details class='rec' data-level='{e(r['level'])}'{connectors_attr([r['connector']] if r.get('connector') else [])}"
                   + (f" data-rec='{r['index']}'" if r.get("index") is not None else "")
                   + f"{' open' if i < open_first else ''}><summary>{level_badge(r['level'])}"
                   f"<span class='fi-count {sev} rec-count'>{r['count']:,}×</span>{conn}{mine} <span class='rec-when'>{when}</span>"
                   # folded: the first line of the record as in the log block (timestamp, level, context, logger in
                   # color), on one line; open: only the log block below (not twice)
                   + f"<div class='rec-line'>{log_html(r['text'].split(chr(10), 1)[0][:600])}</div></summary>"
                   f"<pre>{log_html(r['text'])}</pre>"
                   # the raw lines around it: only when the file has no page (📄 opens it at the line)
                   + (f"<details><summary>📋 Show context</summary><pre>{log_html(r['context'])}</pre></details>"
                      if r.get("context") and not viewers.get(label) else "")
                   + "</details>")
    return "".join(out)


def md_cell(text) -> str:
    """a value in a cell of a Markdown table: one line, | escaped"""
    return str(text).replace("\n", " ").replace("|", "\\|").strip()


def ticket_markdown(res: dict, title: str, levels: str, unit: str = "file") -> str:
    """the summary to paste in a Zendesk or Jira ticket, as Markdown: verdict, period, known causes with what to do, the
    root causes no known cause explains, the timeline, the connectors and the comparison. Always sanitized (best effort):
    a ticket can leave Confluent"""
    s = res["summary"]
    out = [f"## 🔥 Log analysis: {title}", ""]
    out.append(f"**Verdict:** {verdict(res, levels, unit)[1]}")
    covered = period_text(s.get("log_first_timestamp"), s.get("log_last_timestamp"))
    dur = s.get("log_duration_seconds")
    out.append(f"**Period covered:** {covered}" + (f" ({human_duration(dur)})" if dur is not None else "")
               + f" · {s['files_scanned']} {unit}(s), {s['occurrences']} occurrence(s) of {s['distinct']} distinct record(s)"
               + f" (FATAL {s['by_level']['FATAL']} · ERROR {s['by_level']['ERROR']} · WARN {s['by_level']['WARN']})")
    if s.get("kafka_versions"):
        out.append(f"**Kafka version:** {' → '.join(s['kafka_versions'])}")
    for i in s.get("incomplete_inputs") or []:
        out.append(f"**⚠️ Not fully read:** `{i['file']}`: {i['reason']}")
    if res["known_causes"]:
        out += ["", "### What to look at first", "", "| Severity | Known cause | Occurrences | First | What to do |", "| --- | --- | --- | --- | --- |"]
        for h in res["known_causes"][:10]:
            first = h.get("first") or {}
            where = f"{first.get('file', '').split('/')[-1]}:{first.get('line', '')}" + (f" {first['timestamp'].replace('T', ' ')}" if first.get("timestamp") else "")
            reads = "".join(f" · 📚 [{md_cell(label)}]({url})" for label, url in reading_links(h))
            out.append(f"| {h['severity']} | {md_cell(h['title'])} | {h['occurrences']:,} | {md_cell(where)} | {md_cell(h['advice'])}{reads} |")
    others = [c for c in res["root_causes"] if not c.get("explained_by")][:5]
    if others:
        out += ["", "### Errors no known cause explains (most frequent)", ""]
        for c in others:
            what = f"{c['root_cause'].split('.')[-1]}: {c['example']}" if c.get("root_cause") else c.get("example") or c["label"]
            out.append(f"- `{c['level']} ×{c['occurrences']:,}` {md_cell(what[:240])}" + (f" ({md_cell(first_names(c['connectors']))})" if c.get("connectors") else ""))
    cmp = res.get("comparison")
    if cmp:
        c = cmp["counts"]
        out += ["", f"### Compared with {cmp['label']}", "",
                f"{c['new']} new, {c['growing']} growing, {c['shrinking']} shrinking, {c['gone']} gone, {c['same']} unchanged"
                + (" (per hour: the periods differ)" if cmp["per_hour"] else ""), ""]
        for x in [x for x in cmp["root_causes"] if x["status"] != "same"][:8]:
            what = f"{x['root_cause'].split('.')[-1]}: {x['example']}" if x.get("root_cause") else x.get("example") or x["key"]
            out.append(f"- {COMPARE_ICONS[x['status']]} {x['status']} {compare_counts(x)}: {md_cell(what[:200])}")
    events = res.get("timeline") or []
    linked = [ev for ev in events if ev.get("after")]
    if linked:
        out += ["", "### Errors right after a change", ""]
        for ev in linked[:5]:
            out.append(f"- {ev['time'].replace('T', ' ')} {md_cell(timeline_what(ev)[:160])} —{md_cell(after_text(ev))}")
    if events:
        out += ["", "### Timeline (what happened first)", "", "| Time | Event | Where |", "| --- | --- | --- |"]
        for ev in events[:10]:
            out.append(f"| {ev['time'].replace('T', ' ')} | {md_cell(timeline_what(ev)[:200] + after_text(ev))} | {md_cell(ev['file'].split('/')[-1])}:{ev['line']} |")
    tr = res.get("trend")
    if tr:
        out += ["", f"### Trend over {len(tr['labels'])} inputs" + (" (per hour)" if tr["per_hour"] else ""), "",
                "| What | " + " | ".join(md_cell(l.split('/')[-1]) for l in tr["labels"]) + " |", "| --- |" + " --- |" * len(tr["labels"])]
        for lvl in ("FATAL", "ERROR", "WARN"):
            out.append(f"| **{lvl}** | " + " | ".join(f"{v:g}" for v in tr["totals"][lvl]) + " |")
        for r in tr["root_causes"][:8]:
            what = f"{(r.get('root_cause') or '').split('.')[-1]} {r.get('example') or r['key']}".strip()
            out.append(f"| {md_cell(what[:120])} | " + " | ".join(f"{v:g}" for v in r["values"]) + " |")
    lint = res.get("config_lint") or []
    if lint:
        out += ["", "### Config lint (configuration logged at startup)", "", "| Severity | Connector | Key | What to do |", "| --- | --- | --- | --- |"]
        for x in lint[:10]:
            out.append(f"| {x['severity']} | `{md_cell(x['connector'])}` | `{md_cell(x['key'] + '=' + x['value'])}` | {md_cell(x['message'])} |")
    lc_rows = (res.get("lifecycle") or {}).get("rows") or []
    if lc_rows:
        out += ["", "### Restarts and rebalances", "", "| What | Group / connector | Count | Per hour |", "| --- | --- | --- | --- |"]
        for r in lc_rows[:8]:
            out.append(f"| {'🌀 ' if r['storm'] else ''}{LIFECYCLE_KINDS[r['kind']]} | `{md_cell(r['who'] or '?')}` | {r['count']:,} | {rate_cell(r)} |")
    conns = res.get("connectors") or []
    if conns:
        out += ["", f"### Connectors ({len(conns)}, most errors first)", "", "| Connector | Version | ERROR/FATAL | WARN | Task kills | Known causes |", "| --- | --- | --- | --- | --- | --- |"]
        for c in conns[:8]:
            lv = c["by_level"]
            version = (" → ".join(c["versions"]) + f" ({c.get('class', '').split('.')[-1]})") if c.get("versions") else ""
            out.append(f"| `{md_cell(c['connector'])}` | {md_cell(version)} | {lv['FATAL'] + lv['ERROR']:,} | {lv['WARN']:,} | {c['task_killed'] or ''} | {md_cell(', '.join(c['known_causes'][:3]))} |")
    out += ["", "_Generated by `playground analyze logs` (kafka-docker-playground). Secrets, IPs and hostnames replaced by "
            "placeholders (best effort): review before sending._"]
    text = "\n".join(out) + "\n"
    try:
        from sanitizer import DataSanitizer
        text = DataSanitizer().sanitize_text(text)
    except ImportError:
        pass
    return text


def share_html(summary: str, share_zip: str, sanitized: bool, title: str, ticket: str = "") -> str:
    """📤 Share, in the header: the .zip of the report and its file pages (written next to it by analyze logs), the text
    summary to paste in Slack or a ticket, the path, an email with the summary; the sanitization state first"""
    # every < encoded, not only </: a log line with <!--<script> would put the parser in the double escaped state of a
    # script element, and the rest of the page (the dialog, its script, the footer) would become text of this one
    safe = summary.replace("<", "\\u003c")
    state = ("<p class='share-ok'>🔒 Sanitized (--sanitize): secrets, IPs and hostnames are replaced by placeholders. Review it "
             "before sending it outside Confluent.</p>" if sanitized else
             "<p class='share-warn'>⚠️ Not sanitized: it can contain passwords, IPs and hostnames of the logs. For someone outside "
             "Confluent, run the same command again with <span class='mono'>--sanitize</span>.</p>")
    zip_item = (f"<li><a class='share-btn' href='{e(quote(share_zip))}' download>📦 Download the report and its file pages (.zip)</a>"
                "<span class='fi-meta'> send it: your colleague unzips it and opens the .html (📄 and the line links keep working)</span>"
                "<div class='fi-meta' style='margin-top:4px'>No .zip next to the report? Its file pages are larger than 200 MB "
                "(a page holds a whole log file): <button type='button' class='share-close' data-share='zipcmd'>📋 Copy the zip "
                "command</button> and run it in a terminal (or send the .html alone: everything but 📄 works)</div></li>"
                if share_zip else
                "<li><span class='fi-meta'>📦 no .zip was written with this report: send the .html together with its "
                "<span class='mono'>-files/</span> folder</span></li>")
    return (SHARE_CSS + f"<script type='text/plain' id='pg-share-summary'>{safe}</script>"
            + (f"<script type='text/plain' id='pg-share-ticket'>{ticket.replace('<', chr(92) + 'u003c')}</script>" if ticket else "") +
            f"<dialog class='share-dlg' data-title='{e(title)}'><h3>📤 Share this report</h3>{state}<ul>{zip_item}"
            "<li><button type='button' class='share-btn' data-share='summary'>📋 Copy the summary</button>"
            "<span class='fi-meta'> the verdict, the period, the known causes and the root causes, as text: paste it in Slack</span></li>"
            + ("<li><button type='button' class='share-btn' data-share='ticket'>📋 Copy for a ticket (Markdown, sanitized)</button>"
               "<span class='fi-meta'> verdict, period, known causes with what to do, timeline, connectors and comparison as Markdown "
               "tables, secrets / IPs / hostnames replaced: paste it in Zendesk or Jira</span></li>" if ticket else "") +
            "<li><button type='button' class='share-btn' data-share='path'>🔗 Copy the path of the report</button></li>"
            "<li><button type='button' class='share-btn' data-share='mail'>✉️ Email the summary</button>"
            "<span class='fi-meta'> a new mail with the summary, attach the .zip</span></li></ul>"
            "<p class='share-done fi-meta' aria-live='polite'></p><button type='button' class='share-close'>Close</button></dialog>"
            + SHARE_SCRIPT)


SHARE_CSS = """<style>
.share-open{position:absolute;top:2px;right:120px;font:inherit;font-size:.72rem;line-height:1.4;color:#475569;background:#fff;border:1px solid #cbd5e1;border-radius:6px;padding:1px 9px;cursor:pointer}
.share-dlg{border:0;border-radius:12px;padding:20px 24px;max-width:640px;box-shadow:0 10px 40px rgba(0,0,0,.3);background:#fff;color:#1e293b}
.share-dlg::backdrop{background:rgba(15,23,42,.55)}
.share-dlg h3{font-size:1.05rem;margin-bottom:10px}.share-dlg ul{list-style:none;margin:12px 0}.share-dlg li{margin:10px 0}
.share-btn{display:inline-block;font:inherit;font-size:.85rem;font-weight:600;padding:5px 12px;border-radius:8px;border:1px solid #2563eb;background:#2563eb;color:#fff;cursor:pointer;text-decoration:none}
.share-btn:hover{background:#1d4ed8}
.share-warn{background:#fef3c7;color:#92400e;border-radius:8px;padding:8px 12px;font-size:.84rem}
.share-ok{background:#dcfce7;color:#166534;border-radius:8px;padding:8px 12px;font-size:.84rem}
.share-close{font:inherit;font-size:.8rem;padding:3px 12px;border-radius:6px;border:1px solid #cbd5e1;background:transparent;color:inherit;cursor:pointer}
html[data-theme=dark] .share-open{color:#cbd5e1;background:#1e293b;border-color:#334155}
html[data-theme=dark] .share-dlg{background:#1e293b;color:#e2e8f0}
html[data-theme=dark] .share-warn{background:#422006;color:#fcd34d}html[data-theme=dark] .share-ok{background:#052e16;color:#86efac}
html[data-theme=dark] .share-close{border-color:#334155}
</style>"""

SHARE_SCRIPT = """<script>
document.addEventListener("DOMContentLoaded", function () {
  const dlg = document.querySelector(".share-dlg");
  if (!dlg) return;
  const open = document.createElement("button");
  open.type = "button"; open.className = "share-open"; open.textContent = "📤 Share";
  open.title = "send this report to a colleague: .zip, summary to paste, email";
  open.addEventListener("click", () => dlg.showModal());
  document.body.appendChild(open);
  const done = dlg.querySelector(".share-done");
  const summary = document.getElementById("pg-share-summary").textContent.replace(/\\\\u003c/g, "<");
  function copy(text, what) {
    const ok = () => { done.textContent = "✅ " + what + " copied to the clipboard"; };
    if (navigator.clipboard && navigator.clipboard.writeText) {
      navigator.clipboard.writeText(text).then(ok, () => fallback(text, what));
    } else fallback(text, what);
  }
  function fallback(text, what) {
    const ta = document.createElement("textarea");
    ta.value = text; dlg.appendChild(ta); ta.select();
    try { document.execCommand("copy"); done.textContent = "✅ " + what + " copied to the clipboard"; }
    catch (e) { done.textContent = "select the text below and copy it"; return; }
    ta.remove();
  }
  dlg.addEventListener("click", function (ev) {
    const b = ev.target.closest("[data-share]");
    if (ev.target.closest(".share-close") || ev.target === dlg) { dlg.close(); return; }
    if (!b) return;
    const path = decodeURIComponent(location.pathname);
    const dir = path.slice(0, path.lastIndexOf("/")), page = path.split("/").pop();
    const q = x => "'" + x.replace(/'/g, "'\\''") + "'";
    if (b.dataset.share === "zipcmd") {
      const zip = dlg.querySelector("a[download]").getAttribute("href");
      copy("cd " + q(dir) + " && zip -qr " + q(zip) + " " + q(page) + " " + q(page.replace(/\\.html$/, "-files")), "the zip command");
    }
    else if (b.dataset.share === "summary") copy(summary, "the summary");
    else if (b.dataset.share === "ticket") copy(document.getElementById("pg-share-ticket").textContent.replace(/\\\\u003c/g, "<"), "the summary for a ticket");
    else if (b.dataset.share === "path") copy(path, "the path");
    else if (b.dataset.share === "mail") {
      const body = "Log analysis report: " + path.split("/").pop() + " (attached .zip)\\n\\n" + summary;
      location.href = "mailto:?subject=" + encodeURIComponent("🔥 Log analysis: " + dlg.dataset.title)
        // cut by code points: a cut in the middle of an emoji (a surrogate pair) made encodeURIComponent throw (URIError)
        + "&body=" + encodeURIComponent(Array.from(body).length > 1800 ? Array.from(body).slice(0, 1800).join("") + "\\n…" : body);
    }
  });
});
</script>"""


# every section of the report folds by a click on its title (▾ / ▸): the findings, the root causes, the files, each
# file card, the configuration, the sections of other tools; the buttons, links and pickers of a title keep working.
# "Fold all" / "Unfold all" at the top of the findings
SECTION_TOGGLE = """<style>
.sec-toggle{cursor:pointer;user-select:none}.sec-caret{display:inline-block;width:1.1em;color:#64748b;font-size:.85em}
.sec-collapsed>:not(h2):not(.section-title):not(style):not(script){display:none!important}
.sec-collapsed{padding-bottom:6px}
.sec-all{font-family:inherit;font-size:.72rem;margin-left:8px;padding:1px 8px;border-radius:6px;border:1px solid #cbd5e1;background:#fff;color:#475569;cursor:pointer;font-weight:400}
html[data-theme=dark] .sec-all{background:#0f172a;color:#cbd5e1;border-color:#334155}
html[data-theme=dark] .sec-caret,html[data-theme=dark] .rc-range,html[data-theme=dark] .cov-when{color:#94a3b8}
</style><script>
document.addEventListener("DOMContentLoaded", function () {
  const heads = document.querySelectorAll(".table-card > h2, .chart-card > h2, .findings > .section-title");
  function fold(h, collapsed) {
    h.parentElement.classList.toggle("sec-collapsed", collapsed);
    h.querySelector(".sec-caret").textContent = collapsed ? "▸" : "▾";
    h.setAttribute("aria-expanded", collapsed ? "false" : "true");
  }
  heads.forEach(function (h) {
    h.classList.add("sec-toggle");
    h.title = "click to fold / unfold this section";
    h.insertAdjacentHTML("afterbegin", "<span class='sec-caret' aria-hidden='true'>▾</span>");
    // a button for the keyboard and the screen readers too: Tab to it, Enter or Space folds it
    h.setAttribute("role", "button");
    h.setAttribute("tabindex", "0");
    h.setAttribute("aria-expanded", "true");
    h.addEventListener("click", function (ev) {
      if (ev.target.closest("button, a, select, input, label")) return;
      fold(h, !h.parentElement.classList.contains("sec-collapsed"));
    });
    h.addEventListener("keydown", function (ev) {
      if (ev.target !== h || (ev.key !== "Enter" && ev.key !== " ")) return;
      ev.preventDefault();
      fold(h, !h.parentElement.classList.contains("sec-collapsed"));
    });
  });
  // they fold every section: in the filter bar (on the title of 🔎 Findings they looked like its own buttons), else on
  // the first title of a report without one
  const bar = document.querySelector(".lvl-filter .fb-row");
  const first = bar || document.querySelector(".findings > .section-title") || heads[0];
  if (first) {
    first.insertAdjacentHTML("beforeend", "<button type='button' class='sec-all' data-fold='1' title='fold every section of the report'>▸ Fold all sections</button>"
                                         + "<button type='button' class='sec-all' data-fold='0' title='unfold every section of the report'>▾ Unfold all sections</button>");
    first.querySelectorAll(".sec-all").forEach(b => b.addEventListener("click", function () {
      heads.forEach(h => fold(h, b.dataset.fold === "1"));
    }));
  }
});
</script>"""


# id of the 📈 Occurrences over time chart: the 🌳 Root causes table follows the period selected on it
TIME_CHART_ID = "occurrences-chart"

# filter bar of the log report: hides the root causes and the records of the levels switched off, and of the
# connectors not selected (the [connector|task-0] MDC context of the records)
# the selects of the report (the Connector filter, the connector of the configuration): the look of the report
SELECT_CSS = (".conn-filter,.cfg-conn-select{font-family:inherit;font-size:.8rem;max-width:460px;padding:4px 30px 4px 10px;"
              "border-radius:8px;border:1px solid #cbd5e1;background-color:#fff;color:#1e293b;cursor:pointer;-webkit-appearance:none;"
              "appearance:none;background-image:url(\"data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='10' height='6'%3E"
              "%3Cpath d='M0 0l5 6 5-6z' fill='%2364748b'/%3E%3C/svg%3E\");background-repeat:no-repeat;background-position:right 10px center}"
              ".conn-filter:hover,.cfg-conn-select:hover{border-color:#2563eb}"
              ".conn-filter:focus,.cfg-conn-select:focus{outline:none;border-color:#2563eb;box-shadow:0 0 0 3px rgba(37,99,235,.25)}"
              "html[data-theme=dark] .conn-filter,html[data-theme=dark] .cfg-conn-select{background-color:#0f172a;color:#e2e8f0;"
              "border-color:#334155}html[data-theme=dark] .conn-filter option,html[data-theme=dark] .cfg-conn-select option{background:#0f172a}")


FILTER_CSS = ("<style>::highlight(pg-search){background:#fde047;color:#111}.lvl-filter{position:sticky;top:0;z-index:5;display:flex;flex-direction:column;gap:8px;"
              "padding:10px 14px;margin-bottom:14px;border-radius:10px;background:#fff;box-shadow:0 1px 3px rgba(0,0,0,.08);"
              "font-size:.8rem;color:#475569}.fb-row{display:flex;flex-wrap:wrap;align-items:center;gap:8px}"
              ".fb-label{font-size:.75rem;color:#64748b;margin:0 2px 0 4px}"
              # the pills of the CFK report: level (one at a time), component
              ".pill{font-family:inherit;font-size:.8rem;padding:5px 13px;border-radius:999px;border:1px solid #d1d5db;"
              "background:#fff;color:#374151;cursor:pointer;transition:all .15s}.pill:hover{border-color:#6b7280}"
              ".pill .n{opacity:.7;margin-left:3px;font-variant-numeric:tabular-nums}"
              ".pill.active,.lvl-chip.active{background:#111827;color:#fff;border-color:#111827}"
              ".comp-chip.active{background:#1e3a8a;color:#fff;border-color:#1e3a8a}.rec-card.other-comp{display:none}.fi-others .pill{font-size:.72rem;padding:2px 10px;margin-left:6px}"
              ".pg-search{flex:1;min-width:220px;font-family:inherit;font-size:.8rem;padding:6px 12px;border-radius:8px;"
              "border:1px solid #d1d5db;background:#fff;color:#1e293b}.pg-search:focus{outline:2px solid #2563eb;outline-offset:-1px;border-color:transparent}"
              "html[data-theme=dark] .pill,html[data-theme=dark] .pg-search{background:#1e293b;border-color:#334155;color:#cbd5e1}"
              "html[data-theme=dark] .pill:hover{border-color:#94a3b8}"
              "html[data-theme=dark] .pill.active,html[data-theme=dark] .lvl-chip.active{background:#e2e8f0;color:#0f172a;border-color:#e2e8f0}"
              "html[data-theme=dark] .comp-chip.active{background:#2563eb;color:#fff;border-color:#2563eb}"
              + SELECT_CSS +
              ".lvl-filter .sep{margin-left:10px}"
              "html[data-theme=dark] .lvl-filter{background:#1e293b;color:#94a3b8}</style>")

# always emitted: the level, connector and period filters. Everything below the filter bar is counted again from the
# same index of records (occurrences_json): the 📈 occurrences chart, the 🔝 top causes chart, the 🌳 root causes
# table and the records of each file. The verdict and the tiles above the bar stay the figures of the whole report.
FILTER_SCRIPT = ("<style>[data-level][hidden]{display:none}.file-records[hidden]{display:none}tr.file-row[hidden],tr.file-folder[hidden]{display:none}"
                 "tr.file-folder td{font-weight:600;font-size:.8rem;color:#334155;background:#f1f5f9;padding-top:9px}"
                 "html[data-theme=dark] tr.file-folder td{background:#273449;color:#cbd5e1}.ff-dir{color:#94a3b8;font-weight:400}"
                 ".rc-range{font-weight:400;font-size:.75rem;color:#64748b;margin-left:8px}"
                 ".rc-reset{font-family:inherit;font-size:.72rem;margin-left:8px;padding:1px 7px;border-radius:6px;"
                 "border:1px solid #cbd5e1;background:#fff;color:#475569;cursor:pointer}"
                 "html[data-theme=dark] .rc-reset{background:#0f172a;color:#cbd5e1;border-color:#334155}"
                 ".rec-scope:not(:empty){display:block;margin-top:4px;font-size:.75rem;color:#64748b}"
                 ".rec-card.out{opacity:.45}.rec-card.pg-nomatch{display:none}.fi-scope{font-weight:400;font-size:.78rem;opacity:.75}</style>") + """<script>
// ── the filters of the report: levels, connector, and the period selected on the occurrences chart ──────────────
// pgOccurrences: {connectors: [name], records: [[root cause index, level (0 FATAL, 1 ERROR, 2 WARN), connector index
// (-1: none), occurrences, epoch seconds]]} - occurrences_json() of log_report.py. The times of a record are the
// first value then the deltas, in base 36, and are at most the first 1000 occurrences: an occurrence without a time
// of its own counts in the totals but cannot be placed in a period.
var pgOcc = JSON.parse(document.getElementById("pg-occurrences").textContent);
var PG_LEVELS = ["FATAL", "ERROR", "WARN"];
var pgByRecord = null;    // record index -> its entry of pgOcc.records, for the findings
var pgWindow = null;      // [from, to] epoch seconds, null for the whole report
var pgRedrawing = false;  // the chart is being drawn again with other series, its "zoomchange" is not a new period
var pgLevelsOff = null;   // Set of the level codes switched off
var pgConnector = "";     // "" all, "-" the records without a connector context, else a connector name
var pgComponent = "";     // "" all, else the component of the files kept (connect, kafka, clients…)
var pgConnIdx = -1;       // index of pgConnector in pgOcc.connectors
var pgQuery = "";         // the text of the search box
var pgTest = null;        // its test of a text (pgCompile), null without a search
var pgTerms = [];         // its terms: {neg, rx, word}
var pgMatch = null;       // Set of the record indexes whose block passes pgTest, null without a search
// the search: words that must all be in the text (any case), -word for a word that must not be, "a phrase", /a regex/
// (-/regex/ too); an invalid regex is searched as text
function pgCompile(q) {
  const terms = [], re = /(-?)(?:"([^"]+)"|\\/((?:\\\\.|[^\\/])+)\\/|(\\S+))/g;
  let m;
  while ((m = re.exec(q))) {
    const neg = m[1] === "-" && (m[2] !== undefined || m[3] !== undefined || m[4] !== undefined);
    let rx = null, word = null;
    if (m[3] !== undefined) { try { rx = new RegExp(m[3], "i"); } catch (e) { word = m[3].toLowerCase(); } }
    else word = (m[2] !== undefined ? m[2] : m[4] !== undefined ? m[4] : m[1]).toLowerCase();
    if (!rx && !word) continue;
    terms.push({neg: neg, rx: rx, word: word});
  }
  pgTerms = terms;
  if (!terms.length) return null;
  return function (text) {
    const low = text.toLowerCase();
    return terms.every(t => (t.rx ? t.rx.test(text) : low.includes(t.word)) !== t.neg);
  };
}
// the words and regexes searched, highlighted in what is shown (CSS Custom Highlight API: the page is not modified;
// nothing in a browser without it)
function pgHighlight() {
  if (!window.CSS || !CSS.highlights || typeof Highlight === "undefined") return;
  CSS.highlights.delete("pg-search");
  const pos = pgTest ? pgTerms.filter(t => !t.neg) : [];
  if (!pos.length) return;
  const ranges = [], MAX = 3000;
  const roots = document.querySelectorAll("details[data-rec]:not([hidden]), tr.rc-row:not([hidden]), .rec-card:not(.pg-nomatch), tr.tl-row:not([hidden])");
  for (const root of roots) {
    const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT);
    let node;
    while ((node = walker.nextNode()) && ranges.length < MAX) {
      const text = node.nodeValue, low = text.toLowerCase();
      for (const t of pos) {
        if (t.rx) {
          const g = new RegExp(t.rx.source, "gi");
          let m;
          while ((m = g.exec(text)) && ranges.length < MAX) {
            if (!m[0]) { g.lastIndex++; continue; }
            const r = new Range(); r.setStart(node, m.index); r.setEnd(node, m.index + m[0].length); ranges.push(r);
          }
        } else {
          for (let i = low.indexOf(t.word); i >= 0 && ranges.length < MAX; i = low.indexOf(t.word, i + t.word.length)) {
            const r = new Range(); r.setStart(node, i); r.setEnd(node, i + t.word.length); ranges.push(r);
          }
        }
      }
    }
    if (ranges.length >= MAX) break;
  }
  if (ranges.length) CSS.highlights.set("pg-search", new Highlight(...ranges));
}
function pgTimes(rec) {
  if (rec.times === undefined) {
    let t = 0;
    rec.times = rec[4] === "" ? [] : rec[4].split(" ").map(function (d) { t += parseInt(d, 36); return t; });
  }
  return rec.times;
}
function pgKeeps(rec) {
  if (pgLevelsOff && pgLevelsOff.has(rec[1])) return false;
  // the search box: the records whose block contains the text (a record without a block cannot be searched)
  if (pgMatch && (rec[5] < 0 || !pgMatch.has(rec[5]))) return false;
  // the Component chips: the component of the file of the record (pgOcc.components, by file index)
  if (pgComponent && (pgOcc.components || [])[rec[6]] !== pgComponent) return false;
  if (pgConnector === "") return true;
  return pgConnector === "-" ? rec[2] === -1 : rec[2] === pgConnIdx;
}
// occurrences of a record in the selected period, and whether it is in it at all (a record whose occurrences have no
// time of their own cannot be placed: it stays, with its total)
function pgInWindow(rec) {
  if (!pgWindow) return [rec[3], true];
  const times = pgTimes(rec);
  if (!times.length) return [rec[3], true];
  let n = 0;
  // [from, to), as the buckets of the chart
  for (const t of times) if (t >= pgWindow[0] && t < pgWindow[1]) n++;
  // a sampled record (more than 1000 occurrences): each time kept stands for rec[7] of them
  return [Math.min(rec[3], n * (rec[7] || 1)), n > 0];
}
function pgRead() {
  const off = [...document.querySelectorAll(".lvl-chip[aria-pressed=false]")].map(c => +c.dataset.levelCode);
  pgLevelsOff = off.length ? new Set(off) : null;
  const sel = document.querySelector(".conn-filter");
  pgConnector = sel ? sel.value : "";
  pgConnIdx = pgOcc.connectors.indexOf(pgConnector);
  const comp = document.querySelector(".comp-chip.active");
  pgComponent = comp ? comp.dataset.component : "";
  const box = document.querySelector(".pg-search");
  pgQuery = box ? box.value.trim() : "";
  pgTest = pgCompile(pgQuery);
  pgMatch = null;
  if (pgTest) {
    pgMatch = new Set();
    document.querySelectorAll("details[data-rec]").forEach(el => { if (pgTest(el.textContent)) pgMatch.add(+el.dataset.rec); });
  }
}
function pgStamp(t) {
  // wall clock times encoded as UTC epochs (epoch()): the UTC fields give them back as written in the logs
  const d = new Date(Math.round(t * 1000)), p = n => String(n).padStart(2, "0");
  return d.getUTCFullYear() + "-" + p(d.getUTCMonth() + 1) + "-" + p(d.getUTCDate()) + " " +
    p(d.getUTCHours()) + ":" + p(d.getUTCMinutes()) + ":" + p(d.getUTCSeconds());
}
// the series of the occurrences chart, from the records kept: zoom_chart.js asks for them before the first draw
window.pgChartTimes = function (box, chart) {
  if (box.id !== "@@CHART@@") return null;
  const levels = (chart.series || []).map(s => (chart.pgLevels || {})[s.label] || []);
  const pairs = levels.map(() => []);
  let weighted = false;
  for (const rec of pgOcc.records) {
    if (!pgKeeps(rec)) continue;
    const times = pgTimes(rec), w = rec[7] || 1;
    if (!times.length) continue;
    if (w > 1) weighted = true;
    for (let i = 0; i < levels.length; i++) if (levels[i].indexOf(rec[1]) >= 0) { for (const t of times) pairs[i].push([t, w]); break; }
  }
  // the times of each series, sorted; their weights (a sampled record) for zoom_chart.js, as a property of the array
  const out = pairs.map(a => a.sort((x, y) => x[0] - y[0]).map(p => p[0]));
  if (weighted) out.weights = pairs.map(a => a.map(p => p[1]));
  return out;
};
// 🔝 Root causes (occurrences): the same horizontal bars as svg_hbars() of report_html.py, top 10 of what is kept
function pgTopCauses(byCause) {
  const holder = document.querySelector(".top-causes");
  if (!holder) return;
  const rows = [];
  document.querySelectorAll("tr.rc-row").forEach(function (tr) {
    const n = byCause[+tr.dataset.cause];
    if (tr.hidden || !n || !n[0]) return;
    // cells: level, component, root cause, message
    const cls = tr.cells[2].textContent, msg = tr.cells[3].textContent;
    rows.push([cls === "—" ? msg : cls + ": " + msg, n[0], n[2]]);
  });
  rows.sort((a, b) => a[2] - b[2] || b[1] - a[1]);
  const top = rows.slice(0, 10);
  if (!top.length) { holder.innerHTML = "<p class='legend'>No root cause left with these filters.</p>"; return; }
  const W = 600, rowh = 22, L = 300, H = 10 + rowh * top.length, mx = top[0][1] || 1;
  const esc = s => String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
  const o = ['<svg viewBox="0 0 ' + W + " " + H + '" xmlns="http://www.w3.org/2000/svg" role="img" aria-label="' +
    esc("top root causes by occurrences: " + top.map(r => r[0].slice(0, 60) + " " + r[1]).join("; ")) + '">'];
  top.forEach(function (r, i) {
    const y = 5 + i * rowh, w = (W - L - 70) * r[1] / mx;
    o.push('<text x="' + (L - 6) + '" y="' + (y + 14) + '" font-size="10" fill="#334155" text-anchor="end">' + esc(r[0].slice(0, 52)) + "</text>" +
      '<rect x="' + L + '" y="' + (y + 3) + '" width="' + Math.max(1, w).toFixed(1) + '" height="15" rx="2" fill="@@COLOR@@">' +
      "<title>" + esc(r[0] + ": " + r[1] + " occurrence(s)") + "</title></rect>" +
      '<text x="' + (L + w + 5).toFixed(1) + '" y="' + (y + 14) + '" font-size="10" fill="#475569">' + r[1] + "</text>");
  });
  o.push("</svg>");
  holder.innerHTML = o.join("");
}
// the 🌳 root causes table: occurrences and records counted again for the levels, connector and period selected
function pgRootCauses() {
  const byCause = {};
  for (const rec of pgOcc.records) {
    if (!pgKeeps(rec)) continue;
    const n = pgInWindow(rec);
    if (!n[1]) continue;
    const slot = byCause[rec[0]] || (byCause[rec[0]] = [0, 0, 9]);
    slot[0] += n[0];
    slot[1] += 1;
    if (rec[1] < slot[2]) slot[2] = rec[1];
  }
  const note = document.querySelector(".rc-range"), reset = document.querySelector(".rc-reset");
  const rows = document.querySelectorAll("tr.rc-row");
  let kept = 0, occurrences = 0;
  rows.forEach(function (tr) {
    const n = byCause[+tr.dataset.cause];
    tr.hidden = !n;
    if (!n) return;
    tr.querySelector(".rc-occ").textContent = n[0];
    tr.querySelector(".rc-rec").textContent = n[1];
    const badge = tr.querySelector("td .st"), lvl = PG_LEVELS[n[2]];
    if (badge && lvl && badge.textContent !== lvl) { badge.textContent = lvl; badge.className = "st " + lvl.toLowerCase(); }
    kept++;
    occurrences += n[0];
  });
  if (note) {
    const what = kept ? kept + " of " + rows.length + " root cause(s) · " + occurrences + " occurrence(s)"
      : "no root cause left";
    note.textContent = pgWindow ? "⏱ " + pgStamp(pgWindow[0]) + " → " + pgStamp(pgWindow[1]) + " · " + what
      : (pgLevelsOff || pgConnector !== "" || pgComponent !== "" || pgQuery) ? what : "";
    if (reset) reset.hidden = !pgWindow;
  }
  return byCause;
}
// the record blocks of each file: hidden when they are out of the filters, with their ×count in the period
function pgRecordBlocks() {
  const keep = {};
  for (const rec of pgOcc.records) {
    if (rec[5] < 0 || !pgKeeps(rec)) continue;
    const n = pgInWindow(rec);
    if (n[1]) keep[rec[5]] = n[0];
  }
  document.querySelectorAll("details[data-rec]").forEach(function (el) {
    const n = keep[+el.dataset.rec];
    el.hidden = n === undefined;
    const span = el.querySelector(".rec-count");
    if (span) {
      if (span.dataset.all === undefined) span.dataset.all = span.textContent;
      span.textContent = n === undefined ? span.dataset.all : n.toLocaleString("en-US") + "×";
      span.title = n === undefined || !pgWindow ? "" : "in this period · " + span.dataset.all + " in the whole report";
    }
  });
  // a file whose records are all hidden
  document.querySelectorAll(".file-records").forEach(card => { card.hidden = !card.querySelector("details[data-rec]:not([hidden])"); });
}
// 🗂️ the files with findings: distinct records, occurrences and per-level counts of what is kept
function pgFilesTable() {
  const rows = document.querySelectorAll("tr.file-row");
  if (!rows.length) return;
  const by = {};
  for (const rec of pgOcc.records) {
    if (rec[6] < 0 || !pgKeeps(rec)) continue;
    const n = pgInWindow(rec);
    if (!n[1]) continue;
    const slot = by[rec[6]] || (by[rec[6]] = {distinct: 0, occ: 0, 0: 0, 1: 0, 2: 0});
    slot.distinct += 1;
    slot.occ += n[0];
    slot[rec[1]] += n[0];
  }
  rows.forEach(function (tr) {
    const n = by[+tr.dataset.file];
    tr.hidden = !n;
    if (!n) return;
    tr.querySelector(".fr-distinct").textContent = n.distinct;
    tr.querySelector(".fr-occ").textContent = n.occ;
    tr.querySelector(".fr-fatal").textContent = n[0] || "";
    tr.querySelector(".fr-error").textContent = n[1] || "";
    tr.querySelector(".fr-warn").textContent = n[2] || "";
  });
  // a folder row whose files are all hidden by the filters
  document.querySelectorAll("tr.file-folder").forEach(function (tr) {
    let next = tr.nextElementSibling, any = false;
    while (next && !next.classList.contains("file-folder")) { if (!next.hidden) any = true; next = next.nextElementSibling; }
    tr.hidden = !any;
  });
}
// 🔎 Findings: their text stays the figures of the whole report (they are the diagnosis of the bundle, above the
// filter bar, with the verdict and the tiles) - each card only says how much of it is in the current selection
function pgFindings() {
  const cards = document.querySelectorAll(".rec-card[data-recs]");
  if (!cards.length) return;
  if (!pgByRecord) { pgByRecord = {}; for (const rec of pgOcc.records) if (rec[5] >= 0) pgByRecord[rec[5]] = rec; }
  const filtered = pgWindow !== null || pgLevelsOff !== null || pgConnector !== "" || pgComponent !== "" || pgQuery !== "";
  cards.forEach(function (card) {
    const span = card.querySelector(".rec-scope");
    if (!span) return;
    if (!filtered) { span.textContent = ""; card.classList.remove("out", "other-comp"); return; }
    if (card._pgRecs === undefined) card._pgRecs = card.dataset.recs.split(" ").map(Number);
    let here = 0, all = 0;
    for (const i of card._pgRecs) {
      const rec = pgByRecord[i];
      if (!rec) continue;
      all += rec[3];
      if (!pgKeeps(rec)) continue;
      const n = pgInWindow(rec);
      if (n[1]) here += n[0];
    }
    span.textContent = here ? "▸ " + here + " of " + all + " occurrence(s) here" : "▸ nothing in this selection";
    card.classList.toggle("out", here === 0);
    // nothing of it in the selection (another connector, component, level, period, search): hidden, not only dimmed (a
    // worker with hundreds of connectors: the findings of the one picked first); "show them" brings them back, dimmed
    card.classList.toggle("other-comp", here === 0);
  });
  const others = document.querySelectorAll(".rec-card.other-comp").length;
  let note = document.querySelector(".fi-others");
  if (!note) {
    const list = document.querySelector(".findings .recs-list");
    if (list) { note = document.createElement("p"); note.className = "fi-others legend"; list.parentNode.insertBefore(note, list); }
  }
  if (note) {
    note.hidden = !others;
    note.innerHTML = others ? "🙈 " + others + " finding(s) with nothing in this selection hidden "
      + "<button type='button' class='pill fi-show-all'>show them</button>" : "";
  }
  const scope = document.querySelector(".fi-scope");
  if (scope) {
    const bits = [];
    if (pgWindow) bits.push("⏱ " + pgStamp(pgWindow[0]) + " → " + pgStamp(pgWindow[1]));
    if (pgConnector === "-") bits.push("no connector context");
    else if (pgConnector !== "") bits.push(pgConnector);
    if (pgLevelsOff) bits.push([...pgLevelsOff].map(l => PG_LEVELS[l]).join(" + ") + " off");
    if (pgComponent !== "") bits.push(pgComponent);
    if (pgQuery) bits.push("🔎 " + JSON.stringify(pgQuery));
    scope.textContent = bits.length ? " · selection: " + bits.join(" · ") : "";
  }
}
// 🔌 Connectors: a connector picked (▶ only this connector, or the picker) keeps its card only, the search keeps the cards
// that match it; with neither, the first @@CONN_SHOWN@@ cards (most errors first) and "show the other N connectors"
var pgConnAll = false;
function pgConnCards() {
  const cards = document.querySelectorAll(".conn-card");
  if (!cards.length) return;
  const picked = pgConnector !== "" && pgConnector !== "-" ? pgConnector : "";
  const filtered = picked !== "" || pgConnector === "-" || !!pgTest;
  let matching = 0, shown = 0;
  cards.forEach(function (card) {
    let keep = pgConnector !== "-" && (!picked || card.dataset.conn === picked);
    if (keep && pgTest) keep = pgTest(card.textContent);
    if (keep) matching++;
    card.hidden = !keep || (!filtered && !pgConnAll && matching > @@CONN_SHOWN@@);
    if (!card.hidden) shown++;
    const btn = card.querySelector(".conn-only");
    if (btn) {
      const isPicked = picked !== "" && card.dataset.conn === picked;
      btn.textContent = isPicked ? "⤺ all connectors" : "▶ only this connector";
      btn.title = isPicked ? "back to all the connectors" : "show only the records, root causes, timeline, chart and card of this connector";
    }
  });
  const note = document.querySelector(".conn-note");
  if (note) {
    note.hidden = !filtered;
    note.textContent = !filtered ? "" : shown + " of " + cards.length + " connector(s)" +
      (pgConnector === "-" ? ": the records without connector context are selected" : picked ? ": " + picked + " picked" : "") +
      (pgTest ? " · 🔎 " + JSON.stringify(pgQuery) : "");
  }
  const more = document.querySelector(".conn-more");
  if (more) {
    more.hidden = filtered || pgConnAll || matching <= @@CONN_SHOWN@@;
    more.textContent = "show the other " + (matching - @@CONN_SHOWN@@) + " connector(s)";
  }
}
// 🗓️ Incident timeline: its rows follow the filters (a row of another connector, level, component or period is hidden;
// a first error out of the search too, the other rows by their text)
function pgTimeline() {
  const rows = document.querySelectorAll("tr.tl-row");
  if (!rows.length) return;
  let shown = 0;
  rows.forEach(function (tr) {
    const d = tr.dataset;
    let keep = true;
    if (pgComponent && d.component !== pgComponent) keep = false;
    if (keep && pgLevelsOff && d.level !== undefined && d.level !== "" && pgLevelsOff.has(+d.level)) keep = false;
    if (keep && pgConnector === "-" && d.conn) keep = false;
    if (keep && pgConnector !== "" && pgConnector !== "-" && d.conn && d.conn !== pgConnector) keep = false;
    if (keep && pgWindow && d.t && (+d.t < pgWindow[0] || +d.t >= pgWindow[1])) keep = false;
    if (keep && pgTest) keep = d.rec !== undefined ? (pgMatch && pgMatch.has(+d.rec)) : pgTest(tr.textContent);
    tr.hidden = !keep;
    if (keep) shown++;
  });
  const none = document.querySelector(".tl-none");
  if (none) none.hidden = shown > 0;
}
// the filters in the URL (#pg:lvl=1&comp=connect&conn=s3-sink&q=timeout&t=<from>-<to>): a link opens the report on the
// same view (🔗 Link to this view); an anchor of the report (#finding-…) replaces it until the next change
var pgRestoring = false;
// false until the page has read the URL: the first draw of the chart fires a zoomchange before, which wrote an empty
// state over the link being opened
var pgReady = false;
function pgStateWrite() {
  if (pgRestoring || !pgReady) return;
  const p = new URLSearchParams();
  const only = document.querySelector(".lvl-chip.active");
  if (only) p.set("lvl", only.dataset.levelCode);
  if (pgComponent) p.set("comp", pgComponent);
  if (pgConnector) p.set("conn", pgConnector);
  if (pgQuery) p.set("q", pgQuery);
  if (pgWindow) p.set("t", Math.floor(pgWindow[0]) + "-" + Math.ceil(pgWindow[1]));
  const s = p.toString(), url = location.href.split("#")[0] + (s ? "#pg:" + s : "");
  if (url === location.href || (!s && !location.hash.startsWith("#pg:"))) return;
  try { history.replaceState(null, "", url); } catch (e) { if (s) location.replace("#pg:" + s); }
}
function pgStateRead() {
  if (!location.hash.startsWith("#pg:")) return false;
  const p = new URLSearchParams(location.hash.slice(4));
  pgRestoring = true;
  try {
    if (p.has("lvl")) {
      const chip = document.querySelector(".lvl-chip[data-level-code='" + p.get("lvl") + "']");
      if (chip) {
        document.querySelectorAll(".lvl-chip").forEach(c => { c.setAttribute("aria-pressed", c === chip ? "true" : "false"); c.classList.toggle("active", c === chip); });
        const allBtn = document.querySelector(".lvl-all");
        if (allBtn) allBtn.classList.remove("active");
      }
    }
    if (p.has("comp")) {
      const chip = document.querySelector(".comp-chip[data-component='" + CSS.escape(p.get("comp")) + "']");
      if (chip) document.querySelectorAll(".comp-chip").forEach(c => c.classList.toggle("active", c === chip));
    }
    const sel = document.querySelector(".conn-filter");
    if (sel && p.has("conn") && [...sel.options].some(o => o.value === p.get("conn"))) sel.value = p.get("conn");
    const box = document.querySelector(".pg-search");
    if (box && p.has("q")) box.value = p.get("q");
    pgApplyFilters();
    const t = (p.get("t") || "").split("-").map(Number), chart = document.getElementById("@@CHART@@");
    if (t.length === 2 && t.every(Number.isFinite) && chart && chart.zoomTo) chart.zoomTo(t[0], t[1]);
  } finally { pgRestoring = false; }
  pgReady = true;
  pgStateWrite();
  return true;
}
function pgApply() {
  pgTopCauses(pgRootCauses());
  pgRecordBlocks();
  pgFilesTable();
  pgFindings();
  pgSearch();
  pgTimeline();
  pgConnCards();
  pgHighlight();
  pgAria();
  pgStateWrite();
}
// the state of the chips for the screen readers: aria-pressed on the component chips and on 📋 All
function pgAria() {
  document.querySelectorAll(".comp-chip, .lvl-all").forEach(c => c.setAttribute("aria-pressed", c.classList.contains("active") ? "true" : "false"));
}
// the search box filters the records in pgKeeps() (chart, top causes, root causes, files, records follow); a card of the
// findings whose text does not contain it is hidden too, with a class: the hidden attribute is the severity chips'
function pgSearch() {
  document.querySelectorAll(".rec-card").forEach(c => {
    c.classList.toggle("pg-nomatch", !!pgTest && !pgTest(c.textContent));
  });
}
function pgApplyFilters() {
  pgRead();
  pgApply();
  const box = document.getElementById("@@CHART@@");
  if (box && box.setTimes) {
    pgRedrawing = true;  // its "zoomchange" is this redraw, not a new period
    try { box.setTimes(window.pgChartTimes(box, JSON.parse(box.dataset.chart))); } finally { pgRedrawing = false; }
  }
}
// drag over the occurrences chart (or ◀ ▶ / double-click): everything below the filter bar follows
document.addEventListener("zoomchange", function (ev) {
  if (!ev.target || ev.target.id !== "@@CHART@@" || pgRedrawing) return;
  pgWindow = ev.detail.all ? null : [ev.detail.from, ev.detail.to];
  pgRead();
  pgApply();
});
document.addEventListener("click", function (ev) {
  if (ev.target.closest(".rc-reset")) {
    const all = document.querySelector("#@@CHART@@ [data-zoom='all']");
    if (all) all.click(); else { pgWindow = null; pgApplyFilters(); }
    return;
  }
  // the Component chips: one at a time, remembered for the next reports (🧩 All components forgets it)
  const comp = ev.target.closest(".comp-chip");
  if (comp) {
    document.querySelectorAll(".comp-chip").forEach(c => c.classList.toggle("active", c === comp));
    try { if (comp.dataset.component) localStorage.setItem("pg-log-report-component", comp.dataset.component); else localStorage.removeItem("pg-log-report-component"); } catch (e) {}
    const hint = document.querySelector(".comp-remembered");
    if (hint) hint.hidden = true;
    pgApplyFilters();
    return;
  }
  if (ev.target.closest(".conn-only")) {
    const sel = document.querySelector(".conn-filter"), name = ev.target.closest(".conn-only").dataset.conn;
    const card = ev.target.closest(".conn-card");
    if (sel && [...sel.options].some(o => o.value === name)) {
      // ⤺ on the card of the connector picked: back to all the connectors
      sel.value = sel.value === name ? "" : name;
      pgApplyFilters();
      if (card) card.scrollIntoView({block: "nearest"});
    }
    return;
  }
  if (ev.target.closest(".conn-changelog")) {
    const btn = ev.target.closest(".conn-changelog"), cmd = btn.dataset.cmd, label = btn.textContent;
    const done = () => { btn.textContent = "✅ copied: run it in a terminal"; setTimeout(() => { btn.textContent = label; }, 2000); };
    if (navigator.clipboard && navigator.clipboard.writeText) navigator.clipboard.writeText(cmd).then(done, () => window.prompt("Command:", cmd));
    else window.prompt("Command:", cmd);
    return;
  }
  if (ev.target.closest(".conn-more")) {
    pgConnAll = true;
    pgConnCards();
    return;
  }
  if (ev.target.closest(".pg-copy-view")) {
    const btn = ev.target.closest(".pg-copy-view"), url = location.href, done = () => { const t = btn.textContent; btn.textContent = "✅ Link copied"; setTimeout(() => { btn.textContent = t; }, 1500); };
    if (navigator.clipboard && navigator.clipboard.writeText) navigator.clipboard.writeText(url).then(done, () => window.prompt("Link to this view:", url));
    else window.prompt("Link to this view:", url);
    return;
  }
  if (ev.target.closest(".fi-show-all")) {
    document.querySelectorAll(".rec-card.other-comp").forEach(c => c.classList.remove("other-comp"));
    const note = document.querySelector(".fi-others");
    if (note) note.hidden = true;
    return;
  }
  // the levels, as in the CFK report: 📋 All, or one level at a time (a click on the selected one goes back to All)
  const all = ev.target.closest(".lvl-all"), chip = ev.target.closest(".lvl-chip");
  if (!all && !chip) return;
  const only = chip && !chip.classList.contains("active") ? chip : null;
  document.querySelectorAll(".lvl-chip").forEach(c => {
    c.setAttribute("aria-pressed", !only || c === only ? "true" : "false");
    c.classList.toggle("active", c === only);
  });
  const allBtn = document.querySelector(".lvl-all");
  if (allBtn) allBtn.classList.toggle("active", !only);
  pgApplyFilters();
});
let pgSearchTimer = null;
document.addEventListener("input", function (ev) {
  if (!ev.target.closest(".pg-search")) return;
  clearTimeout(pgSearchTimer);
  pgSearchTimer = setTimeout(pgApplyFilters, 200);
});
document.addEventListener("change", function (ev) { if (ev.target.closest(".conn-filter")) pgApplyFilters(); });
document.addEventListener("DOMContentLoaded", function () {
  // a link to a view (#pg:…) wins over the component remembered from the last report
  if (pgStateRead()) return;
  pgReady = true;
  // the component picked in a previous report (🔌 Connect for someone who works on Connect), when this one has it
  let saved = null;
  try { saved = localStorage.getItem("pg-log-report-component"); } catch (e) {}
  const chip = saved ? document.querySelector(".comp-chip[data-component='" + saved + "']") : null;
  if (chip) {
    document.querySelectorAll(".comp-chip").forEach(c => c.classList.toggle("active", c === chip));
    const hint = document.createElement("span");
    hint.className = "comp-remembered fb-label";
    hint.textContent = "· remembered from your last report (🧩 All components to forget it)";
    chip.after(hint);
    // drawn before this handler (zoom_chart.js listens first): drawn again for the component
    pgApplyFilters();
    return;
  }
  pgRead(); pgApply();
});
</script>""".replace("@@CHART@@", TIME_CHART_ID).replace("@@COLOR@@", SERIES_1).replace("@@CONN_SHOWN@@", str(CONN_CARDS_SHOWN))


CONFIG_CSS = ("<style>" + SELECT_CSS + ".cfg-kind{font-size:.92rem;margin:18px 0 6px}.cfg-class>summary,.cfg>summary{padding:6px 0}"
              ".cfg-class{border-top:1px solid #e2e8f0}.cfg-class>details,.cfg-class>p,.cfg-class>table{margin-left:18px}"
              ".cfg-val{display:inline-block;margin:2px 10px 2px 0}tr.cfg-diff td{background:#fef3c7}tr.cfg-diff td:first-child{border-left:3px solid #d97706}"
              "html[data-theme=dark] tr.cfg-diff td{background:#3a2a06}.cfg-compare[hidden]{display:none}"
              ".cfg-changed li[hidden]{display:none}.cfg-classes[hidden],.cfg-conn-card[hidden]{display:none}"
              ".cfg-conn-card h3{font-size:1rem;margin:14px 0 4px}.cfg-conn-card h4{font-size:.88rem;margin:14px 0 4px}"
              "tr.cfg-group td{font-weight:600;font-size:.78rem;color:#475569;background:#f1f5f9;padding-top:9px}"
              "html[data-theme=dark] tr.cfg-group td{background:#273449;color:#cbd5e1}.cfg-srcs{margin:0 0 6px}.cfg-pick{margin:18px 0 6px;padding:10px 14px;border-radius:8px;background:#eff6ff;font-size:.88rem}"
              "html[data-theme=dark] .cfg-pick{background:#172554}.cfg-src{display:inline-block;font-size:.8rem;margin-right:14px}.cfg-dump[hidden],.cfg-class[hidden]{display:none}"
              ".cfg-changed{background:#fffbeb;border-left:4px solid #d97706;border-radius:8px;padding:10px 14px;margin:8px 0}"
              ".cfg-changed h3{font-size:.9rem;margin-bottom:4px}.cfg-changed li{font-size:.82rem;margin:3px 0 3px 16px}"
              "html[data-theme=dark] .cfg-class{border-top-color:#334155}html[data-theme=dark] .cfg-changed{background:#2a1f06}"
              ".cfg-search{font-family:inherit;font-size:.8rem;padding:4px 8px;border-radius:6px;border:1px solid #cbd5e1;"
              "width:100%;max-width:420px;margin:4px 0 10px}table.cfg td:first-child{width:36%}table.cfg td{word-break:break-all}"
              "html[data-theme=dark] .cfg-search{background:#0f172a;color:#cbd5e1;border-color:#334155}</style>")
CONFIG_SCRIPT = """<script>
// the configuration of one connector (its card), or all of them compared by config class
function cfgShow(v) {
  document.querySelectorAll(".cfg-conn-card").forEach(c => { c.hidden = c.dataset.connector !== v; });
  const classes = document.querySelector(".cfg-classes");
  if (classes) classes.hidden = v !== "__all__";
}
document.addEventListener("change", function (ev) {
  if (ev.target.closest(".cfg-conn-select")) cfgShow(ev.target.value);
});
// the Connector picker of the filter bar also keeps the configs of that connector
document.addEventListener("change", function (ev) {
  if (!ev.target.closest(".conn-filter")) return;
  const v = ev.target.value;
  document.querySelectorAll("[data-cfg-connectors]").forEach(el => {
    el.hidden = v !== "" && !el.dataset.cfgConnectors.split(" ").includes(v);
  });
  // the Connector filter of the report picks the connector of the configuration too ("all": back to the first one)
  const sel = document.querySelector(".cfg-conn-select");
  if (sel) {
    if (v !== "" && sel.querySelector("option[value='" + CSS.escape(v) + "']")) sel.value = v;
    else if (v === "") sel.selectedIndex = 0;
    cfgShow(sel.value);
  }
});
document.querySelectorAll(".cfg-search").forEach(function (input) {
  input.addEventListener("input", function () {
    const q = input.value.toLowerCase().trim();
    const card = input.closest(".table-card");
    card.querySelectorAll("tr.cfg-row").forEach(tr => { tr.hidden = q !== "" && !tr.textContent.toLowerCase().includes(q); });
    card.querySelectorAll("details.cfg").forEach(d => {
      if (q) d.open = !!d.querySelector("tr.cfg-row:not([hidden])") || d.querySelector("summary").textContent.toLowerCase().includes(q);
    });
  });
});
</script>"""


CLIENT_CONFIGS = ("ProducerConfig", "ConsumerConfig", "AdminClientConfig")


def config_group(c: dict) -> Tuple[int, str]:
    """(order, title) of the group of a config: config files, components, one group per connector, clients"""
    m = re.match(r"\[([^\s|\]]+)\|", c.get("context") or "")
    connector = m.group(1) if m else (c.get("id") if c["title"].endswith("ConnectorConfig") or c["title"] == "connector config" else None)
    if connector:
        return 2, f"🧩 {connector}"
    if c["source"] == "file":
        return 0, "📄 Config files"
    if c["title"] in CLIENT_CONFIGS:
        return 3, "📡 Clients"
    return 1, "🧱 Components"


# keys that name the instance (they differ from one client or connector to the next): not a difference worth reading
IDENTITY_KEYS = re.compile(r"^(client\.id|group\.instance\.id|transactional\.id|name|task\.id|metrics\.context\..*)$")


def config_kind(c: dict) -> Tuple[int, str]:
    """(order, title) of the kind of a config: config files, components, connectors, clients"""
    m = re.match(r"\[([^\s|\]]+)\|", c.get("context") or "")
    if c["source"] == "file":
        return 0, "📄 Config files"
    if c["title"] in CLIENT_CONFIGS:
        return 3, "📡 Clients (producers, consumers and admin clients of the connectors and the worker)"
    if m or c["title"].endswith("ConnectorConfig") or c["title"] == "connector config":
        return 2, "🧩 Connectors"
    return 1, "🧱 Components"


def config_connector_of(c: dict) -> str:
    m = re.match(r"\[([^\s|\]]+)\|", c.get("context") or "")
    if m:
        return m.group(1)
    if c["title"].endswith("ConnectorConfig") or c["title"] == "connector config":
        return c.get("id") or ""
    # a client of a connector: connector-producer-<name>-<task>
    cid = re.match(r"^connector-(?:producer|consumer|dlq-producer|admin)-(.+?)(?:-\d+)?$", c.get("id") or "")
    return cid.group(1) if cid else ""


def config_values(c: dict) -> "OrderedDict[str, str]":
    out: "OrderedDict[str, str]" = OrderedDict()
    for line in c["text"].splitlines():
        key, _, value = line.partition("=")
        out[key] = value
    return out


def config_html(configs: List[dict], viewers: Optional[Dict[str, str]] = None, ranked: Sequence[str] = ()) -> str:
    """⚙️ Configuration: one block per config class (ProducerConfig, JdbcSourceConnectorConfig…) instead of one per dump:
    how many dumps, the keys whose value differs between them (with their values), the keys that are the same in all of
    them, then the dumps themselves; the keys changed between restarts first. The Connector picker of the report keeps the
    configs of a connector; ranked: the connectors by occurrences, the first one with configs is shown first"""
    if not configs:
        return ""
    classes: Dict[Tuple[int, str], "OrderedDict[str, List[dict]]"] = {}
    for c in configs:
        name = c["title"] + (f" {c['id']}" if c.get("id") in ("key", "value") else "")
        classes.setdefault(config_kind(c), OrderedDict()).setdefault(name, []).append(c)
    blocks = []
    changed = [c for c in configs if c.get("changes")]
    if changed:
        items = "".join(f"<li data-cfg-connectors='{e(config_connector_of(c) or '-')}'><strong>{e(c['title'])}</strong> <span class='mono'>{e(config_connector_of(c) or c.get('id') or '')}</span>: "
                        + ", ".join(f"<span class='mono'>{e(ch['key'])}</span> {e(ch['previous'])} → <strong class='mono'>{e(ch['value'])}</strong>"
                                    for ch in c["changes"][:6])
                        + (f" <span class='fi-meta'>(+{len(c['changes']) - 6} more)</span>" if len(c["changes"]) > 6 else "") + "</li>"
                        for c in changed[:40])
        blocks.append(f"<div class='cfg-changed'><h3>🔁 Changed between restarts ({len(changed)})</h3><ul>{items}</ul></div>")
    def kind_html(kind) -> str:
        names = classes[kind]
        return (f"<h3 class='cfg-kind'>{e(kind[1])} <span class='fi-meta'>· {len(names)} class(es), "
                f"{sum(len(v) for v in names.values())} dump(s)</span></h3>"
                + "".join(config_class_html(name, dumps, viewers) for name, dumps in sorted(names.items(), key=lambda kv: (-len(kv[1]), kv[0]))))
    # config files and components (the worker, the broker…): always shown, they belong to no connector
    blocks += [kind_html(k) for k in sorted(classes) if k[0] < 2]
    cards, connectors = connector_config_cards(classes, viewers)
    per_kind = [k for k in sorted(classes) if k[0] >= 2]
    if connectors:
        # the connectors: one at a time (its card), the one with the most occurrences first, or all of them compared by
        # config class
        first = next((c for c in ranked if c in connectors), connectors[0])
        order = [first] + [c for c in ranked if c in connectors and c != first] + sorted(c for c in connectors if c not in ranked and c != first)
        options = "".join(f"<option value='{e(c)}'{' selected' if c == first else ''}>{e(c)}</option>" for c in order)
        blocks.append(f"<div class='cfg-pick'><strong>🧩 Connector configuration:</strong> <select class='cfg-conn-select'>{options}"
                      f"<option value='__all__'>🔍 compare all the {len(connectors)} connector(s), by config class</option></select>"
                      "<span class='fi-meta'> · the connector with the most occurrences first; the Connector filter of the report "
                      "picks one here too</span></div>")
        blocks.append(cards.replace(f"data-connector='{e(first)}' hidden>", f"data-connector='{e(first)}'>", 1))
        blocks.append("<div class='cfg-classes' hidden><p class='legend'>Every connector and client config, one block per config "
                      "class: the keys whose value differs between the dumps first, with each value and in how many dumps.</p>"
                      + "".join(kind_html(k) for k in per_kind) + "</div>")
    else:
        blocks += [kind_html(k) for k in per_kind]
    return (f"{CONFIG_CSS}<div class='table-card'><h2>⚙️ Configuration <span class='fi-meta'>· "
            f"{sum(len(v) for v in classes.values())} config class(es), {len(configs)} dump(s)</span></h2>"
            "<p class='legend'>🪵 the configs the components log when they start (<span class='mono'>KafkaConfig values:</span>, "
            "<span class='mono'>DistributedConfig</span>, a connector config, the <span class='mono'>ProducerConfig</span> of each "
            "client…, defaults included, the last one of each), 📄 the config files of the input. The components first, then "
            "the configuration of one connector at a time (pick it below), or all the connectors compared by config class.</p>"
            "<input class='cfg-search' type='search' placeholder='Filter keys and values…'>"
            f"{''.join(blocks)}</div>{CONFIG_SCRIPT}")


# a value that says nothing: folded in the card of a connector
UNSET_VALUES = ("", "null", "[]", "{}", "None")
# the configs of the plugins around a connector (converters, serializers, tracer…): folded under its own config
AUX_CONFIG = re.compile(r"Converter|Serializer|Deserializer|AvroData|ProtobufData|JsonSchemaData|Tracer|^TaskConfig|"
                        r"Interceptor|Transformation|Predicate|HeaderConverter")


def prefix_rows(items: List[tuple], render) -> str:
    """rows grouped by the first part of their key (database.*, snapshot.*…) with a header row per group of 2 keys or more"""
    groups: "OrderedDict[str, List[tuple]]" = OrderedDict()
    for it in sorted(items, key=lambda x: x[0]):
        head = it[0].split(".")[0] if "." in it[0] else ""
        groups.setdefault(head, []).append(it)
    out = []
    singles = []
    for head, its in groups.items():
        if head and len(its) >= 2:
            out.append(f"<tr class='cfg-group'><td colspan='2'>{e(head)}.* <span class='fi-meta'>{len(its)}</span></td></tr>")
            out.append(render(its))
        else:
            singles.extend(its)
    return (render(singles) if singles else "") + "".join(out)


def latest_dump(dumps: List[dict]) -> dict:
    return max(dumps, key=lambda c: (c.get("time") or "", c["file"], c.get("line") or 0))


def class_modes(dumps: List[dict]) -> Dict[str, str]:
    """key -> the value most dumps of a class have (several dumps only)"""
    if len(dumps) < 2:
        return {}
    counts: Dict[str, Counter] = {}
    for c in dumps:
        for k, v in config_values(c).items():
            counts.setdefault(k, Counter())[v] += 1
    return {k: n.most_common(1)[0][0] for k, n in counts.items()}


def connector_config_cards(classes: Dict[Tuple[int, str], "OrderedDict[str, List[dict]]"],
                           viewers: Optional[Dict[str, str]]) -> Tuple[str, List[str]]:
    """the configuration of each connector, shown when it is picked in the Connector filter: its connector config merged
    from the latest dump of each connector class (each key once, the values other connectors do not have first, the
    unset ones folded), then its clients with only the keys that differ from the other clients"""
    modes = {name: class_modes(dumps) for kind in classes for name, dumps in classes[kind].items()}
    nclasses = {name: len({config_connector_of(c) for c in dumps} - {""}) for kind in classes for name, dumps in classes[kind].items()}
    per: Dict[str, List[Tuple[int, str, dict]]] = {}
    for kind in classes:
        for name, dumps in classes[kind].items():
            for c in dumps:
                conn = config_connector_of(c)
                if conn:
                    per.setdefault(conn, []).append((kind[0], name, c))
    cards = []
    for conn in sorted(per):
        by_class: "OrderedDict[str, List[dict]]" = OrderedDict()
        kinds: Dict[str, int] = {}
        for kind, name, c in per[conn]:
            by_class.setdefault(name, []).append(c)
            kinds[name] = kind
        # connector config: each key once, from the latest dump of each connector class
        merged: "OrderedDict[str, Tuple[str, str, Optional[str]]]" = OrderedDict()
        sources = []
        aux = []
        for name, dumps in by_class.items():
            if kinds[name] != 2:
                continue
            if AUX_CONFIG.search(name):
                aux.append((name, dumps))
                continue
            last = latest_dump(dumps)
            same = len({c["text"] for c in dumps}) == 1
            where = log_viewer.link(viewers or {}, last["file"], "📄", last.get("line"))
            sources.append(f"<span class='cfg-src'>{e(name)} <span class='fi-meta'>{len(dumps)} dump(s)"
                           f"{', identical' if same or len(dumps) == 1 else ', see 🔁'}</span> {where}</span>")
            for k, v in config_values(last).items():
                if k in merged:
                    continue
                mode = modes[name].get(k)
                merged[k] = (v, name, mode if mode is not None and v != mode and nclasses[name] > 1 else None)
        specific = [(k, v, n, m) for k, (v, n, m) in merged.items() if m is not None]
        unset = [(k, v, n, m) for k, (v, n, m) in merged.items() if m is None and v in UNSET_VALUES]
        rest = [(k, v, n, m) for k, (v, n, m) in merged.items() if m is None and v not in UNSET_VALUES]

        def rows(items, cls=""):
            return "".join(f"<tr class='cfg-row{cls}'" + (f" title='most connectors: {e(m[:200])}'" if m is not None else "")
                           + f"><td class='mono'>{e(k)}</td><td class='mono'>{e(v)}</td></tr>" for k, v, n, m in items)
        body = ""
        if merged:
            body += ("<h4>Connector config <span class='fi-meta'>· " + str(len(merged)) + " keys"
                     + (f", {len(specific)} with a value most connectors do not have (highlighted, first)" if specific else "")
                     + "</span></h4><div class='cfg-srcs'>" + " ".join(sources) + "</div>"
                     + f"<table class='cfg'><tr><th>Key</th><th>Value</th></tr>{rows(specific, ' cfg-diff')}{prefix_rows(rest, rows)}</table>"
                     + (f"<details class='cfg'><summary>{len(unset)} key(s) unset (null, empty)</summary>"
                        f"<table class='cfg'>{rows(unset)}</table></details>" if unset else ""))
        if aux:
            parts = []
            for name, dumps in aux:
                last = latest_dump(dumps)
                vals = [(k, v, name, None) for k, v in config_values(last).items() if v not in UNSET_VALUES]
                where = log_viewer.link(viewers or {}, last["file"], "📄", last.get("line"))
                parts.append(f"<details class='cfg'><summary>{e(name)} <span class='fi-meta'>· {len(vals)} keys set · "
                             f"{len(dumps)} dump(s)</span> {where}</summary><table class='cfg'>{rows(vals)}</table></details>")
            body += (f"<details class='cfg'><summary><strong>🔧 Converters, serializers and other plugin configs</strong> "
                     f"<span class='fi-meta'>· {len(aux)}: {', '.join(e(n) for n, _ in aux)}</span></summary>{''.join(parts)}</details>")
        # clients: only what differs from the other clients of the class
        for name, dumps in by_class.items():
            if kinds[name] != 3:
                continue
            last = latest_dump(dumps)
            values = config_values(last)
            diff = [(k, v, name, modes[name].get(k)) for k, v in values.items()
                    if modes[name].get(k) is not None and v != modes[name][k] and not IDENTITY_KEYS.match(k)]
            where = log_viewer.link(viewers or {}, last["file"], "📄", last.get("line"))
            others = nclasses[name] - 1
            body += (f"<h4>{e(name)} <span class='fi-meta'>· {e(last.get('id') or '')} · {len(dumps)} dump(s) {where}</span></h4>"
                     + (f"<table class='cfg'><tr><th>Key</th><th>Value</th></tr>{rows(diff, ' cfg-diff')}</table>"
                        f"<p class='legend'>the {len(values) - len(diff)} other keys: the same as most clients</p>" if diff
                        else f"<p class='legend'>✅ the same as the other {others} client(s) of this class "
                             f"(apart from {', '.join(sorted({k for k in values if IDENTITY_KEYS.match(k)})) or 'their name'})</p>"))
        changes = [(name, ch) for name, dumps in by_class.items() for c in dumps for ch in c.get("changes", [])]
        if changes:
            body = ("<div class='cfg-changed'><h3>🔁 Changed between restarts</h3><ul>"
                    + "".join(f"<li><strong>{e(n)}</strong> <span class='mono'>{e(ch['key'])}</span> {e(ch['previous'])} → "
                              f"<strong class='mono'>{e(ch['value'])}</strong></li>" for n, ch in changes[:30])
                    + "</ul></div>" + body)
        others_kinds = [name for name in by_class if kinds[name] not in (2, 3)]
        if others_kinds:
            body += (f"<p class='legend'>Also logged for this connector: {', '.join(e(n) for n in others_kinds)} "
                     "(pick “all” to see them in their class)</p>")
        cards.append(f"<div class='cfg-conn-card' data-connector='{e(conn)}' hidden><h3>🧩 {e(conn)}</h3>{body}</div>")
    return "".join(cards), sorted(per)


def config_class_html(name: str, dumps: List[dict], viewers: Optional[Dict[str, str]]) -> str:
    """one config class: its dumps compared"""
    connectors = sorted({config_connector_of(c) for c in dumps} - {""})
    attr = f" data-cfg-connectors='{e(' '.join(connectors + (['-'] if any(not config_connector_of(c) for c in dumps) else [])))}'"
    icon = "📄" if dumps[0]["source"] == "file" else "🪵"
    nchanged = sum(1 for c in dumps if c.get("changes"))
    flag = f" <span class='st warn'>🔁 {nchanged} with keys changed between restarts</span>" if nchanged else ""
    if len(dumps) == 1:
        c = dumps[0]
        return (f"<div class='cfg-dump'{attr}>" + config_block_html(c, viewers) + "</div>")
    values = [config_values(c) for c in dumps]
    keys = list(OrderedDict((k, True) for v in values for k in v))
    differ, same, identity = [], [], []
    for k in keys:
        seen = Counter(v.get(k, "∅ (not set)") for v in values)
        if len(seen) == 1:
            same.append((k, next(iter(seen))))
        elif IDENTITY_KEYS.match(k):
            identity.append(k)
        else:
            differ.append((k, seen))
    # the value most dumps have, for the keys that differ: a dump with another value has it highlighted
    common = {k: seen.most_common(1)[0][0] for k, seen in differ}
    rows = "".join(f"<tr class='cfg-row'><td class='mono'>{e(k)}</td><td>"
                   + " ".join(f"<span class='cfg-val'><span class='mono'>{e(val[:120]) or '″″'}</span> <span class='fi-meta'>×{n}</span></span>"
                              for val, n in seen.most_common(6))
                   + (f" <span class='fi-meta'>+{len(seen) - 6} other value(s)</span>" if len(seen) > 6 else "") + "</td></tr>"
                   for k, seen in differ)
    same_rows = "".join(f"<tr class='cfg-row'><td class='mono'>{e(k)}</td><td class='mono'>{e(v)}</td></tr>" for k, v in same)
    who = (f" · {len(connectors)} connector(s)" if connectors else "")
    return (f"<details class='cfg cfg-class'{attr}><summary>{icon} <strong>{e(name)}</strong> "
            f"<span class='fi-count info'>{len(dumps):,} dumps</span><span class='fi-meta cfg-all'>{who} · "
            f"{len(differ)} key(s) differ · {len(same)} the same everywhere</span><span class='fi-meta cfg-sel'></span>{flag}</summary>"
            # hidden when a connector is picked: the block then shows the dumps of that connector
            + "<div class='cfg-compare'>"
            + (f"<p class='legend'>Keys whose value differs between the dumps (the value, then in how many dumps)"
               + (f"; not shown: {', '.join(identity)}, which name each instance" if identity else "") + ":</p>"
               f"<table class='cfg'><tr><th>Key</th><th>Values</th></tr>{rows}</table>" if differ
               else "<p class='legend'>✅ the same value in every dump" + (f" (except {', '.join(identity)}, which name each instance)" if identity else "") + "</p>")
            + f"<details class='cfg'><summary>{len(same)} key(s) with the same value in every dump</summary>"
              f"<table class='cfg'><tr><th>Key</th><th>Value</th></tr>{same_rows}</table></details></div>"
            + f"<details class='cfg cfg-dumps'><summary>The {len(dumps)} dumps, one by one "
              "<span class='fi-meta'>(a value other than the one of most dumps is highlighted)</span></summary>"
            + "".join(f"<div class='cfg-dump' data-cfg-connectors='{e(config_connector_of(c) or '-')}'>{config_block_html(c, viewers, common)}</div>"
                      for c in sorted(dumps, key=lambda c: (config_connector_of(c), c["file"], c.get("line") or 0)))
            + "</details></details>")


def config_block_html(c: dict, viewers: Optional[Dict[str, str]] = None, common: Optional[Dict[str, str]] = None) -> str:
    """one config: its key / value table, collapsed; viewers: label -> page of the file (log_viewer); common: key -> the
    value most dumps of its class have, a different value is highlighted"""
    rows = []
    for line in c["text"].splitlines():
        key, _, value = line.partition("=")
        if common and key in common and value != common[key]:
            rows.append(f"<tr class='cfg-row cfg-diff' title='most dumps of this class: {e(common[key][:200])}'>"
                        f"<td class='mono'>{e(key)}</td><td class='mono'>{e(value)}</td></tr>")
        else:
            rows.append(f"<tr class='cfg-row'><td class='mono'>{e(key)}</td><td class='mono'>{e(value)}</td></tr>")
    where = (log_viewer.link(viewers or {}, c["file"], e(c["file"] + (f":{c['line']}" if c.get("line") else "")), c.get("line"))
             + e(f" ({c['time'].replace('T', ' ')})" if c.get("time") else ""))
    what = " ".join(x for x in (c.get("context"), c.get("id")) if x)
    icon = "📄" if c["source"] == "file" else "🪵"
    changes = "".join(f"<li class='mono'>{e(ch['key'])}: {e(ch['previous'])} → {e(ch['value'])}"
                      + (f" <span class='legend'>· line {ch['line']}</span>" if ch.get("line") else "") + "</li>"
                      for ch in c.get("changes", []))
    changed = f" <span class='st warn'>🔁 {len(c['changes'])} key(s) changed between restarts</span>" if c.get("changes") else ""
    return (f"<details class='cfg'><summary>{icon} <strong>{e(c['title'])}</strong> <span class='mono'>{e(what)}</span> "
            f"<span class='legend'>· {len(rows)} keys · {where}</span>{changed}</summary>"
            + (f"<p class='legend'>🔁 changed between two dumps of this config (a restart with another config):</p><ul>{changes}</ul>" if changes else "")
            + f"<table class='cfg'><tr><th>Key</th><th>Value</th></tr>{''.join(rows)}</table></details>")


LEVEL_PILLS = (("FATAL", "💀"), ("ERROR", "🔴"), ("WARN", "🟠"))


def filter_html(by_level: Dict[str, int], by_connector: Dict[str, int], without_connector: int,
                files: Optional[List[dict]] = None) -> str:
    """The filter bar, in the look of the CFK report: 📋 All / 💀 FATAL / 🔴 ERROR / 🟠 WARN (one level at a time), a search
    box, the Component chips (from the path of each file, with 2 components or more) and the connector picker (records
    with a connector context). FILTER_SCRIPT, which applies them, is emitted by html_report()."""
    present = [lvl for lvl, _ in LEVEL_PILLS if by_level.get(lvl)]
    rows = []
    first = ["<button type='button' class='pill lvl-all active' title='every level'>📋 All</button>"]
    if len(present) >= 2:
        first += [f"<button type='button' class='pill lvl-chip' data-level='{lvl}' data-level-code='{LEVEL_ORDER[lvl]}' "
                  f"aria-pressed='true' title='only the {lvl} records'>{icon} {lvl} <span class='n'>{by_level[lvl]:,}</span></button>"
                  for lvl, icon in LEVEL_PILLS if by_level.get(lvl)]
    first.append("<input class='pg-search' type='search' placeholder='Search: words, -exclude, \"a phrase\", /regex/' "
                 "title='the records, root causes, findings and timeline rows whose text has all the words (any case); "
                 "-word: without it; \"two words\": that phrase; /regex/ (or -/regex/): a regular expression. The matches are highlighted'>")
    first.append("<button type='button' class='pill pg-copy-view' title='the filters are in the URL of the page: copy the link "
                 "that opens this report on the same view'>🔗 Link to this view</button>")
    rows.append("<div class='fb-row'>" + "".join(first if len(present) >= 2 else first[1:]) + "</div>")
    second = []
    counts: "OrderedDict[str, int]" = OrderedDict()
    for f in files or []:
        code = file_component(f["label"])
        counts[code] = counts.get(code, 0) + f["occurrences"]
    if len(counts) >= 2:
        names = {code: name for code, name, _ in FILE_COMPONENTS}
        names["other"] = "📄 Other"
        second.append("<span class='fb-label'>Component</span><button type='button' class='pill comp-chip active' data-component=''>"
                      f"🧩 All components <span class='n'>{sum(counts.values()):,}</span></button>")
        second += [f"<button type='button' class='pill comp-chip' data-component='{code}' title='only the files of {e(names[code][2:].strip())} (occurrences)'>"
                   f"{names[code]} <span class='n'>{n:,}</span></button>"
                   for code, n in sorted(counts.items(), key=lambda kv: -kv[1])]
    if by_connector:
        options = [f"<option value=''>all ({len(by_connector)} connector(s){' + no connector' if without_connector else ''})</option>"]
        options += [f"<option value='{e(name)}'>{e(name)} ({n})</option>" for name, n in by_connector.items()]
        if without_connector:
            options.append(f"<option value='{NO_CONNECTOR}'>— no connector context — ({without_connector})</option>")
        second.append("<span class='fb-label'>Connector</span><select class='conn-filter' "
                      "title='only the root causes and the records of this connector ([connector|task-0] context of the log line)'>"
                      + "".join(options) + "</select>")
    if second:
        rows.append("<div class='fb-row'>" + "".join(second) + "</div>")
    return FILTER_CSS + "<div class='lvl-filter'>" + "".join(rows) + "</div>"


def verdict(res: dict, levels: str, unit: str = "file") -> Tuple[str, str]:
    s = res["summary"]
    incomplete = s.get("incomplete_inputs") or []
    if not s["files_with_findings"] and incomplete:
        return "warn", (f"⚠️ No {levels} record in the {s['files_scanned']} {unit}(s) read ({s['lines']} lines), but "
                        f"{len(incomplete)} input(s) were not fully read: the missing part may hold errors (⚠️ Not fully read below).")
    if not s["files_with_findings"]:
        return "ok", f"✅ No {levels} record in the {s['files_scanned']} {unit}(s) scanned ({s['lines']} lines)."
    errors = s["by_level"]["FATAL"] + s["by_level"]["ERROR"]
    if errors:
        # the first known cause, else the most frequent root cause
        start = ""
        if res["known_causes"]:
            start = f": start with {res['known_causes'][0]['title']}"
        elif res["root_causes"]:
            c = res["root_causes"][0]
            what = f"{c['root_cause'].split('.')[-1]}: {c['example']}" if c["root_cause"] else c["label"]
            start = f": start with {what[:160].rstrip('.')}"
        return "danger", (f"🚨 {errors} ERROR/FATAL occurrence(s), {s['distinct']} distinct record(s) in "
                          f"{s['files_with_findings']} {unit}(s){start}.")
    return "warn", f"⚠️ {s['by_level']['WARN']} WARN occurrence(s) in {s['files_with_findings']} {unit}(s), no ERROR/FATAL."


def read_incomplete(path: Optional[str]) -> List[dict]:
    """label<tab>reason lines written by analyze logs: the inputs not fully read (digest failed, truncated gzip, archive
    not fully extracted)"""
    if not path or not os.path.exists(path):
        return []
    out = []
    with open(path, encoding="utf-8", errors="replace") as fh:
        for line in fh:
            label, _, reason = line.rstrip("\n").partition("\t")
            if label:
                out.append({"file": label, "reason": reason})
    return out


def incomplete_html(items: List[dict]) -> str:
    """the inputs not fully read, right below the verdict: what the report says is only true of what could be read"""
    if not items:
        return ""
    rows = "".join(f"<li><code>{e(i['file'])}</code>: {e(i['reason'])}</li>" for i in items)
    return (f"<div class='verdict warn'>⚠️ Not fully read: {len(items)} input(s). The findings below only cover what "
            f"could be read; ask for a complete copy.<ul style='margin:6px 0 0 18px;font-weight:400'>{rows}</ul></div>")


def first_names(names: List[str], top: int = 3) -> str:
    return ", ".join(names[:top]) + (f" (+{len(names) - top} more)" if len(names) > top else "")


# the findings of the log report: count chips, exception names in color, the first occurrence as a 📄 / ✏️ link to the
# line instead of the path of the file, the exception chains of the killed tasks most frequent first
FINDINGS_CSS = """<style>
.fi-title{font-weight:600}
details.rec>summary{padding:6px 0;line-height:1.7}.rec-when{margin-left:6px}
.rec-line{display:block;margin:4px 0 0 18px;padding:5px 10px;border-radius:6px;background:#f8fafc;color:#1e293b;font-family:'SFMono-Regular',Consolas,Menlo,monospace;font-size:.76rem;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
details.rec[open]>summary .rec-line{display:none}
.fi-count{display:inline-block;font-size:.78rem;font-weight:700;padding:1px 8px;border-radius:12px;margin:0 4px;font-variant-numeric:tabular-nums;background:#e2e8f0;color:#334155}
.fi-count.critical{background:#fee2e2;color:#b91c1c}.fi-count.high{background:#ffedd5;color:#c2410c}.fi-count.medium{background:#fef3c7;color:#b45309}
.fi-count.low{background:#dcfce7;color:#15803d}.fi-count.info{background:#dbeafe;color:#1d4ed8}
.fi-meta{font-size:.8rem;color:#64748b}
.fi-advice{font-size:.84rem;color:#475569;margin-top:4px}
.fi-read a{color:#2563eb;text-decoration:none;margin-right:4px}.fi-read a:hover{text-decoration:underline}
.rec-details li.fi-chain{font-family:inherit;font-size:.84rem;margin:8px 0;list-style:none;margin-left:-18px;padding:8px 10px;border-radius:8px;background:#f8fafc}
.fi-exc{font-family:ui-monospace,SFMono-Regular,Menlo,monospace;font-weight:600;color:#c2410c}
.fi-exc.error{color:#dc2626}
.fi-msg{font-family:ui-monospace,SFMono-Regular,Menlo,monospace;font-size:.8rem;color:#334155;word-break:break-word}
.fi-cause{margin:3px 0 0 14px}
.fi-conns{margin-top:4px}
.fi-conn{display:inline-block;font-family:ui-monospace,SFMono-Regular,Menlo,monospace;font-size:.72rem;padding:0 6px;margin:2px 3px 0 0;border-radius:4px;background:#e2e8f0;color:#334155}
.fi-conns details{display:inline}.fi-conns summary{display:inline;cursor:pointer;font-size:.75rem;color:#2563eb;font-weight:500}
.fi-comp{display:inline-block;font-size:.72rem;font-weight:500;padding:1px 8px;margin:0 3px 0 0;border-radius:999px;border:1px solid #c7d2fe;background:#eef2ff;color:#3730a3;white-space:nowrap}
.fi-lvl{display:inline-block;font-size:.68rem;font-weight:700;padding:1px 7px;border-radius:12px;margin-right:4px}
.fi-lvl.fatal{background:#fee2e2;color:#b91c1c}.fi-lvl.error{background:#ffedd5;color:#c2410c}.fi-lvl.warn{background:#fef3c7;color:#b45309}
""" + dark("""
.fi-count{background:#334155;color:#e2e8f0}
.fi-count.critical{background:#450a0a;color:#fca5a5}.fi-count.high{background:#431407;color:#fdba74}.fi-count.medium{background:#422006;color:#fcd34d}
.fi-count.low{background:#052e16;color:#86efac}.fi-count.info{background:#172554;color:#93c5fd}
.fi-meta,.fi-advice{color:#94a3b8}
.fi-read a{color:#93c5fd}
.rec-details li.fi-chain{background:#0f172a}
.rec-line{background:#0b1220;color:#e2e8f0}
.fi-exc{color:#fdba74}.fi-exc.error{color:#fca5a5}
.fi-msg{color:#cbd5e1}
.fi-conn{background:#334155;color:#cbd5e1}
.fi-comp{background:#1e1b4b;color:#c7d2fe;border-color:#3730a3}
.fi-conns summary{color:#93c5fd}
.fi-lvl.fatal{background:#450a0a;color:#fca5a5}.fi-lvl.error{background:#431407;color:#fdba74}.fi-lvl.warn{background:#422006;color:#fcd34d}
""") + "</style>"


def exception_html(text: str) -> str:
    """"SaslAuthenticationException: {..}" -> the class in color (an Error in red), then the message"""
    m = re.match(r"^([A-Za-z_$][\w$.]*(?:Exception|Error|Throwable|Fault|Failure))(?::\s*(.*))?$", text or "", re.S)
    if not m:
        # anything else (the clients: FAIL [rdkafka#producer-1] …, panic:, Error:, [Connection] …): the colors of the log
        return f"<span class='fi-msg'>{log_html(text)}</span>"
    cls = "fi-exc error" if m.group(1).endswith("Error") else "fi-exc"
    return f"<span class='{cls}'>{e(m.group(1))}</span>" + (f"<span class='fi-msg'>: {e(m.group(2))}</span>" if m.group(2) else "")


def first_html(viewers: Dict[str, str], label: str, line, timestamp) -> str:
    """"first 2026-11-02 20:17:50 📄 ✏️": the time, then the page of the file at the line and the editor (the path on hover)"""
    when = e(timestamp.replace("T", " ")) if timestamp else f"line {line}"
    link = log_viewer.link(viewers, label, "📄", line) if line else ""
    if not link or link == "📄":
        link = f"<span title='{e(label)} line {line}'>📄</span>"
    return f"<span class='fi-meta' title='{e(label)}, line {line}'>first {when} {link}</span>"


def connectors_html(names: List[str]) -> str:
    if not names:
        return ""
    chips = "".join(f"<span class='fi-conn'>{e(n)}</span>" for n in names[:5])
    more = ""
    if len(names) > 5:
        more = (f" <details><summary>+{len(names) - 5} more</summary>"
                + "".join(f"<span class='fi-conn'>{e(n)}</span>" for n in names[5:200]) + "</details>")
    return f"<div class='fi-conns'><span class='fi-meta'>🔌 {len(names)} connector(s): </span>{chips}{more}</div>"


# exception chains shown under a known cause (the killed tasks: all of them) or a root cause, most frequent first
CHAINS_SHOWN = 5


def chains_note(chains: List[dict], limit: int) -> str:
    if not chains:
        return ""
    more = f", the {limit} most frequent below" if len(chains) > limit else ", most frequent first"
    return f"<span class='fi-meta'> · {len(chains)} distinct exception chain(s){more}</span>"


def chain_rows(chains: List[dict], limit: int, sev: str, viewers: Dict[str, str]) -> List[str]:
    """one card per exception chain: count, exception (class in color, then the message), Caused by, connectors, first
    occurrence linked"""
    rows = []
    ordered = sorted(chains, key=lambda c: -c["occurrences"])
    for c in ordered[:limit]:
        rows.append(f"<span class='fi-count {sev}'>{c['occurrences']:,}×</span>" + exception_html(c["exception"][:400])
                    + (f"<div class='fi-cause'><span class='fi-meta'>⬅️ Caused by </span>{exception_html(c['caused_by'][:400])}</div>" if c["caused_by"] else "")
                    + connectors_html(c["connectors"])
                    + f"<div>{first_html(viewers, c['first_file'], c['first_line'], c['first_timestamp'])}</div>")
    if len(ordered) > limit:
        rest = sum(c["occurrences"] for c in ordered[limit:])
        rows.append(f"<span class='fi-meta'>+{len(ordered) - limit} more chain(s), {rest:,} occurrence(s): see the 📄 cards of the files below</span>")
    return rows


def finding_id(title: str) -> str:
    """anchor of the card of a known cause: the 🌳 Root causes table links to it"""
    return "finding-" + (re.sub(r"[^a-z0-9]+", "-", title.lower()).strip("-") or "x")


def finding_view(f: dict, viewers: Dict[str, str], unit: str) -> dict:
    """the finding with html / html_details for findings_html: the same facts as its text, easier to read"""
    v = f.get("_view")
    if not v:
        return f
    f = dict(f, id=finding_id(v["title"]) if v["kind"] == "known" else f"finding-root-{v['cause_index']}")
    sev = f["severity"].lower()
    files = v.get("files") or []
    where = f"in {len(files)} {unit}s" if len(files) > 1 else (f"in {e(os.path.basename(files[0]))}" if files else "")
    if v["kind"] == "known":
        first = v.get("first") or {}
        head = (f"<span class='fi-title'>{e(v['title'])}</span><span class='fi-count {sev}'>{v['occurrences']:,}×</span>"
                + component_chips(files)
                + f"<span class='fi-meta'>{where} · </span>" + first_html(viewers, first.get("file", ""), first.get("line"), first.get("timestamp")))
        # the killed tasks list all their chains (what to fix), the other known causes the most frequent ones
        chains = v.get("chains") or v.get("_chains") or []
        limit = len(chains) if v.get("chains") else CHAINS_SHOWN
        reads = " · ".join(f"<a href='{e(url)}' target='_blank' rel='noopener'>📚 {e(label)}</a>" for label, url in reading_links(v))
        head += (chains_note(chains, limit) + f"<div class='fi-advice'>👉 {e(v['advice'])}</div>"
                 + (f"<div class='fi-advice fi-read'>{reads}</div>" if reads else ""))
        return dict(f, html=head, html_details=chain_rows(chains, limit, sev, viewers) or None)
    # a root cause no known cause explains: its exception as the title, the same rows as a known cause
    chains = v.get("_chains") or []
    first = v.get("first") or {}
    if v["root_cause"]:
        title = short_exception(v["root_cause"]).split(":")[0]
    else:
        # no exception: the start of the message
        words = (v["example"] or "").split()
        title = " ".join(words[:8]) + ("…" if len(words) > 8 else "") or "Unrecognized error"
    head = (f"<span class='fi-lvl {v['level'].lower()}'>{e(v['level'])}</span><span class='fi-title'>🌳 {e(title)}</span>"
            f"<span class='fi-count {sev}'>{v['occurrences']:,}×</span>{component_chips(files)}<span class='fi-meta'>{where}</span>"
            + (f"<span class='fi-meta'> · </span>{first_html(viewers, first['file'], first['line'], first['timestamp'])}" if first else "")
            + chains_note(chains, CHAINS_SHOWN)
            + "<div class='fi-advice'>👉 no known cause matches it: read its exception chain and its context (📄)"
            + f" · <a href='#root-cause-{v['cause_index']}' title='its row in the 🌳 All root causes table'>🌳 in the table</a></div>")
    rows = chain_rows(chains, CHAINS_SHOWN, sev, viewers)
    if not rows:
        rows = [f"<span class='fi-count {sev}'>{v['occurrences']:,}×</span>{exception_html(v['example'][:400])}"]
    return dict(f, html=head, html_details=rows)


COVERAGE_CSS = """<style>
.cov-folder{font-size:.84rem;font-weight:600;color:#334155;margin:14px 0 4px}
.cov-row{display:grid;grid-template-columns:minmax(160px,26%) 1fr 270px;gap:10px;align-items:center;font-size:.8rem;padding:3px 0}
.cov-name{font-family:ui-monospace,SFMono-Regular,Menlo,monospace;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.cov-track{position:relative;height:12px;border-radius:6px;background:#e2e8f0}
.cov-bar{position:absolute;top:0;height:100%;border-radius:6px;background:linear-gradient(90deg,#1e3a5f,#2563eb);min-width:3px}
.cov-bar.hit{background:linear-gradient(90deg,#9a3412,#ea580c)}
.cov-gap{position:absolute;top:0;height:100%;background:repeating-linear-gradient(45deg,#dc2626 0 4px,transparent 4px 8px);opacity:.7}
.cov-when{color:#64748b;font-variant-numeric:tabular-nums;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.cov-axis{display:grid;grid-template-columns:minmax(160px,26%) 1fr 270px;gap:10px;font-size:.72rem;color:#94a3b8}
.cov-axis div:nth-child(2){display:flex;justify-content:space-between}
.cov-gaps{margin:4px 0 8px;font-size:.8rem;color:#b91c1c}
html[data-theme=dark] .cov-folder{color:#cbd5e1}html[data-theme=dark] .cov-track{background:#334155}
html[data-theme=dark] .cov-gaps{color:#fca5a5}
</style>"""


def coverage_html(cov: dict, viewers: Optional[Dict[str, str]], unit: str = "file") -> str:
    """🕰️ Log coverage: a bar per file on the same time axis, grouped by folder, the files with records in orange, the
    periods a folder has no log hatched in red and listed"""
    files = cov.get("files") or []
    timed = [x for x in files if x["seconds"] is not None]
    if len(timed) < 1 or unit != "file":
        return ""
    t0, t1 = ts_seconds(cov["first"]), ts_seconds(cov["last"])
    span = max(t1 - t0, 1)

    def pos(ts: str) -> float:
        return 100.0 * (ts_seconds(ts) - t0) / span
    gaps_by: Dict[str, List[dict]] = {}
    for g in cov.get("gaps") or []:
        gaps_by.setdefault(g["folder"], []).append(g)
    folders: "OrderedDict[str, List[dict]]" = OrderedDict()
    for x in sorted(files, key=lambda x: (x["folder"], x["first"] or "~", x["label"])):
        folders.setdefault(x["folder"], []).append(x)
    axis = (f"<div class='cov-axis'><div></div><div><span>{e(period_text(cov['first'], None))}</span>"
            f"<span>{e(cov['last'].replace('T', ' '))}</span></div><div></div></div>")
    parts = [axis]
    for folder, xs in folders.items():
        gaps = gaps_by.get(folder, [])
        parts.append(f"<div class='cov-folder'>📁 {e(folder or '.')} <span class='fi-meta'>· {len(xs)} {unit}(s)</span></div>")
        if gaps:
            what = {"start": "starts {d} after the other logs", "end": "ends {d} before the other logs",
                    "between": "no file between them"}
            parts.append("<div class='cov-gaps'>⚠️ not covered by any file of this folder: "
                         + ", ".join(f"{e(period_text(g['from'], g['to']))} ({e(what.get(g.get('where'), '{d}').format(d=human_duration(g['seconds'])))})"
                                     for g in gaps[:8])
                         + (f" (+{len(gaps) - 8} more)" if len(gaps) > 8 else "") + "</div>")
        for x in xs:
            name = x["label"].rsplit("/", 1)[-1]
            link = log_viewer.link(viewers or {}, x["label"], e(name)) if viewers else e(name)
            if x["seconds"] is None:
                parts.append(f"<div class='cov-row'><div class='cov-name' title='{e(x['label'])}'>{link}</div>"
                             f"<div class='fi-meta'>no timestamped line</div><div class='cov-when'>{x['lines']:,} lines</div></div>")
                continue
            left, right = pos(x["first"]), pos(x["last"])
            gap_marks = "".join(f"<span class='cov-gap' style='left:{pos(g['from']):.2f}%;width:{max(pos(g['to']) - pos(g['from']), .3):.2f}%' "
                                f"title='no log: {e(period_text(g['from'], g['to']))}'></span>" for g in gaps)
            hit = " hit" if x["occurrences"] else ""
            parts.append(f"<div class='cov-row'><div class='cov-name' title='{e(x['label'])}'>{link}</div>"
                         f"<div class='cov-track'>{gap_marks}<span class='cov-bar{hit}' style='left:{left:.2f}%;width:{max(right - left, .3):.2f}%' "
                         f"title='{e(period_text(x['first'], x['last']))} · {x['lines']:,} lines · {x['occurrences']:,} record occurrence(s)'></span></div>"
                         f"<div class='cov-when'>{e(period_text(x['first'], x['last']))} · {e(human_duration(x['seconds']))}"
                         f" · {x['lines']:,} lines" + (f" · <b>{x['occurrences']:,}</b> rec." if x["occurrences"] else "") + "</div></div>")
    ngaps = len(cov.get("gaps") or [])
    head = (f"{len(files)} {unit}(s), {period_text(cov['first'], cov['last'])}"
            + (f", ⚠️ {ngaps} period(s) without logs" if ngaps else ""))
    return (COVERAGE_CSS + f"<div class='table-card' id='log-coverage'><h2>🕰️ Log coverage <span class='fi-meta'>· {e(head)}</span></h2>"
            "<p class='legend'>The time range of each file (first and last timestamped line) on the same axis, grouped by folder "
            "(a folder of rotated logs, a worker, a pod): 🟧 a file with records, 🟦 without. What happened outside these "
            "ranges, or in a period hatched in red (no file of the folder covers it), is not in the input.</p>"
            + "".join(parts) + "</div>")


def html_report(res: dict, title: str, levels: str, skipped: int, heading: str = "🔥 Log Analysis",
                command: str = "playground analyze logs", unit: str = "file", links: List[Tuple[str, str]] = (),
                sections: List[Tuple[str, str]] = (), viewers: Optional[Dict[str, str]] = None,
                html_sections: List[Tuple[str, str]] = (), share_zip: str = "") -> str:
    """unit: what a label is (file, container, script); links: (label, url) in the header; sections: (title, text)
    shown as is after the findings (the last lines of a failed CI script...); viewers: label -> page of the file
    (log_viewer), the labels and line numbers link to it"""
    viewers = viewers or {}
    s = res["summary"]
    Unit = unit[0].upper() + unit[1:]
    errors = s["by_level"]["FATAL"] + s["by_level"]["ERROR"]
    # the period the logs cover (first and last timestamped line of the files, not only the records), the duration
    # it makes, and a warning when that window is too short to hold the context of an incident
    covered, covered_seconds = period_text(s["log_first_timestamp"], s["log_last_timestamp"]), s["log_duration_seconds"]
    short_window = unit == "file" and covered_seconds is not None and covered_seconds < SHORT_PERIOD_SECONDS
    span = covered if covered_seconds is None else f"{covered} ({human_duration(covered_seconds)})"
    detail = [covered]
    hover = (f"first and last timestamped line of the {unit}s scanned: {covered}" if covered_seconds is not None
             else f"no line of the {unit}s scanned starts with a date: how long they cover is unknown")
    if short_window:
        detail.append("⚠️ short window")
        hover += (f" — shorter than {human_duration(SHORT_PERIOD_SECONDS)}, the logs may not cover the incident itself: "
                  f"ask for an export that starts well before it")
    elif s["findings_duration_seconds"] is not None and covered_seconds and s["findings_duration_seconds"] < covered_seconds:
        detail.append(f"{levels} over {human_duration(s['findings_duration_seconds'])} of it")
        hover += f" — the {levels} records span {period_text(s['first_timestamp'], s['last_timestamp'])}"
    if time_zone_note(s):
        detail.append("🌐 UTC")
        hover += " — " + time_zone_note(s)
    kpis = "".join([
        kpi("🕐 Period covered", human_duration(covered_seconds), " · ".join(detail) if covered_seconds is not None
            else "no timestamped line in the logs", "warn" if short_window else "", hover),
        kpi(f"🗂️ {Unit}s scanned", s["files_scanned"], f"{s['lines']} lines" + (f", {skipped} binary skipped" if unit == "file" else "")),
        (kpi("🏷️ Kafka version", s["kafka_versions"][-1], " → ".join(s["kafka_versions"]) if len(s["kafka_versions"]) > 1 else "logged at startup",
             "", "the version the components log at startup (AppInfoParser): -ce is Confluent Platform") if s.get("kafka_versions") else ""),
        kpi(f"🔥 {Unit}s with findings", s["files_with_findings"], f"{levels} records", "danger" if errors else "warn" if s["files_with_findings"] else "ok"),
        kpi("🧬 Distinct records", s["distinct"], "after de-duplication"),
        kpi("🔁 Occurrences", s["occurrences"], "all levels reported"),
        kpi("💀 FATAL", s["by_level"]["FATAL"], "occurrences", "danger" if s["by_level"]["FATAL"] else "ok"),
        kpi("🔴 ERROR", s["by_level"]["ERROR"], "occurrences", "danger" if s["by_level"]["ERROR"] else "ok"),
        kpi("🟠 WARN", s["by_level"]["WARN"], "occurrences" if "WARN" in levels else "not included (--errors-only)",
            "warn" if s["by_level"]["WARN"] else ""),
    ])
    # the most frequent first within a severity (the text summary and --json keep the order of the known causes)
    findings_view = sorted((finding_view(f, viewers, unit) for f in res["findings"]),
                           key=lambda f: (SEVERITY_ORDER.index(f["severity"]), -(f.get("_view") or {}).get("occurrences", 0)))
    # an exception chain of a killed task is a card of its own inside the finding
    # the filter bar above the findings: a component picked (🔌 Connect) keeps its findings right below
    without_connector = sum(r["count"] for f in res["files"] for r in f["records"] if not r.get("connector"))
    body = [verdict_html(*verdict(res, levels, unit)), incomplete_html(s.get("incomplete_inputs") or []), kpis_html([kpis]),
            compare_html(res.get("comparison")), trend_html(res.get("trend")),
            filter_html(s["by_level"], s["by_connector"], without_connector, res["files"]), FINDINGS_CSS,
            findings_html(findings_view, intro="What to look at first: the known causes, with what to do, then the most "
                          "frequent errors no known cause explains (🌳). Every distinct error is in 🌳 All root causes below.")
            .replace("<li><span class='fi-count", "<li class='fi-chain'><span class='fi-count"),
            timeline_html(res.get("timeline") or [], viewers), connectors_health_html(res.get("connectors") or []),
            lifecycle_html(res.get("lifecycle"))]
    body += [card(e(t), f"<pre>{e(text)}</pre>") for t, text in sections]
    # trusted HTML written by the playground itself (never text from the logs: the tools escape it)
    body += [f"<div class='table-card'><h2>{e(t)}</h2>{fragment}</div>" for t, fragment in html_sections]
    # the filter bar first: everything under it (the charts, the root causes, the records) follows the filters

    body.append(charts_html(res["files"], res["root_causes"]))
    with_conn = bool(s["by_connector"])
    if res["root_causes"]:
        def finding_cell(c: dict, i: int) -> str:
            if c.get("explained_by"):
                return "<br>".join(f"<a href='#{finding_id(t)}' title='the card of this known cause in 🔎 Findings'>{e(t)}</a>"
                                   for t in c["explained_by"])
            if c.get("in_findings"):
                return f"<a href='#finding-root-{i}' title='its card in 🔎 Findings'>🌳 card in Findings</a>"
            return "<span class='fi-meta' title='not a known cause, not among the most frequent: read its records below'>—</span>"
        rows = "".join(f"<tr class='rc-row' data-level='{e(c['level'])}' data-cause='{i}' id='root-cause-{i}'><td>{level_badge(c['level'])}</td>"
                       f"<td>{component_chips(c['files'])}</td>"
                       f"<td class='mono' title='{e(c['root_cause'] or '')}'>{e((c['root_cause'] or '—').split('.')[-1])}</td>"
                       f"<td class='mono'>{e(c['example'][:300])}</td><td class='num rc-occ'>{c['occurrences']}</td>"
                       f"<td class='num rc-rec'>{c['records']}</td><td class='mono'>{', '.join(log_viewer.link(viewers, x, e(x), edit=False) for x in c['files'][:5])}"
                       f"{e(' …' if len(c['files']) > 5 else '')}</td>"
                       + (f"<td class='mono' title='{e(', '.join(c['connectors']))}'>{e(first_names(c['connectors']))}</td>" if with_conn else "")
                       + f"<td>{finding_cell(c, i)}</td></tr>" for i, c in enumerate(res["root_causes"]))
        untimed = sum(count - len(times) * stride for c in res["root_causes"] for _, _, count, times, _, _, stride in c["records_meta"]
                      if count > len(times) * stride)
        follows = ("<p class='legend'>Every distinct error of the logs, grouped by its deepest exception (or its message when "
                   "it has none), most frequent first. 🔎 Findings above is the short list to start with; the Finding column "
                   "says which card explains a row (a known cause, or a 🌳 card of the most frequent unexplained errors), "
                   "— for the long tail.</p><p class='legend'>⏱ Drag over 📈 Occurrences over time to select a period: this table, the charts and "
                   "the records below then only show that period, with the occurrences counted in it (double-click the "
                   "chart, or ⤺ whole period, to go back). The Levels chips and the Connector picker filter the charts "
                   "too."
                   + (f" {untimed} occurrence(s) have no timestamp of their own (undated line, or beyond the first 1000 "
                      "occurrences kept per record): they are not counted in a period, and a root cause that has only "
                      "those stays shown." if untimed else "")
                   + "</p>")
        body.append("<div class='table-card'><h2>🌳 All root causes (every distinct error, by deepest exception)"
                    "<span class='rc-range'></span><button type='button' class='rc-reset' hidden>⤺ whole period</button>"
                    f"</h2>{follows}<table><tr><th>Level</th><th>Component</th>"
                    "<th>Root cause</th><th>Message</th><th class='num'>Occurrences</th><th class='num'>Records</th>"
                    f"<th>{Unit}s</th>{'<th>Connectors</th>' if with_conn else ''}<th>Finding</th></tr>"
                    f"{rows}</table></div>")
    body.append(coverage_html(res.get("coverage") or {}, viewers, unit))
    if res["files"]:
        # grouped by folder (a folder of rotated logs, a worker, a pod), as 🕰️ Log coverage: a 📁 row, then the file names
        by_folder: "OrderedDict[str, List[Tuple[int, dict]]]" = OrderedDict()
        for i, f in sorted(enumerate(res["files"]), key=lambda x: (x[1]["label"].rsplit("/", 1)[0] if "/" in x[1]["label"] else "", x[1]["label"])):
            by_folder.setdefault(f["label"].rsplit("/", 1)[0] if "/" in f["label"] else "", []).append((i, f))
        grouped = len(by_folder) > 1 or next(iter(by_folder)) != ""
        rows = ""
        for folder, items in by_folder.items():
            if grouped:
                rows += (f"<tr class='file-folder'><td colspan='7'>📁 {e(folder or '.')} <span class='fi-meta'>· "
                         f"{len(items)} {unit}(s), {sum(f['occurrences'] for _, f in items):,} occurrence(s)</span></td></tr>")
            rows += "".join(f"<tr class='file-row' data-file='{i}'><td class='mono' title='{e(f['label'])}'>"
                            f"{log_viewer.link(viewers, f['label'], e(f['label'].rsplit('/', 1)[-1] if grouped else f['label']))}</td>"
                            f"<td class='num'>{f['lines']}</td><td class='num fr-distinct'>{f['distinct']}</td>"
                            f"<td class='num fr-occ'>{f['occurrences']}</td>"
                            + "".join(f"<td class='num fr-{lvl.lower()}'>{sum(r['count'] for r in f['records'] if r['level'] == lvl) or ''}</td>"
                                      for lvl in ("FATAL", "ERROR", "WARN"))
                            + "</tr>" for i, f in items)
        body.append(f"<div class='table-card'><h2>🗂️ {Unit}s with findings</h2><table><tr><th>{Unit}</th><th class='num'>Lines</th>"
                    "<th class='num'>Distinct</th><th class='num'>Occurrences</th><th class='num'>FATAL</th><th class='num'>ERROR</th>"
                    f"<th class='num'>WARN</th></tr>{rows}</table>"
                    + (f"<details><summary>✅ {len(res['files_without_findings'])} {unit}(s) without findings</summary><p class='mono'>"
                       + e(", ".join(res["files_without_findings"][:500])) + "</p></details>" if res["files_without_findings"] else "")
                    + "</div>")
        for f in res["files"]:
            # not "title": the title of the report, in its header
            folder, _, name = f["label"].rpartition("/")
            file_title = ((f"<span class='ff-dir'>📁 {e(folder)}/</span>" if folder else "")
                          + log_viewer.link(viewers, f["label"], e(name)))
            body.append(f"<div class='table-card file-records'><h2>📄 {file_title}</h2>"
                        f"{records_html(f['records'], viewers=viewers, label=f['label'])}</div>")
    body.append(config_html(res.get("configuration") or [], viewers, list(s["by_connector"])))
    # last: the index of the records the filters count again from, then the filters themselves
    body.append("<script type='application/json' id='pg-occurrences'>"
                + occurrences_json(res["root_causes"], res["files"]).replace("<", "\\u003c") + "</script>")
    body.append(FILTER_SCRIPT)
    body.append(SECTION_TOGGLE)
    sanitized = any(t.startswith("🔒") for t, _ in sections)
    body.append(share_html(text_summary(res, []), share_zip, sanitized, title, ticket_markdown(res, title, levels, unit)))
    meta = [f"&#128196; {e(title)}", f"🕐 {e(span)}", f"Levels: {e(levels)}"]
    if res.get("filter"):
        meta.append(f"🔌 --connector {e(' '.join(res['filter']['connectors']))}" + (" --with-worker" if res["filter"]["with_worker"] else ""))
    meta += [f"<a href='{e(url)}' style='color:#fff'>{e(label)}</a>" for label, url in links]
    return page(f"{heading[2:].strip()} report — {title}", e(heading), meta, "".join(body),
                f"🛠️ Generated by {e(command)} (self-contained, no external resource). Records are cut to 300 "
                "characters per line and to 3 frames of the deepest cause, like the terminal digest; "
                + ("📄 opens the whole file at the line." if viewers else "📋 Show context has the raw lines around their first occurrence.")
                + (f" The file names, line numbers and 📄 open the file in {e(next(iter(viewers.values())).split('/')[0])}/, "
                   f"✏️ in {e(log_viewer.editor()[0])} (playground config editor): keep that folder with the report." if viewers else ""))


def write_viewers(report: str, files: List[dict], res: dict, sources_file: str) -> Dict[str, str]:
    """the pages of the files with findings or a configuration (log_viewer), with the lines of their records and
    configs highlighted: label -> href"""
    sources: Dict[str, Tuple[str, bool]] = {}
    try:
        with open(sources_file, encoding="utf-8", errors="replace") as fh:
            for line in fh:
                label, path, stays = (line.rstrip("\n").split("\t") + ["", ""])[:3]
                sources.setdefault(label, (path, stays == "1"))
    except OSError:
        return {}
    hits: Dict[str, List[int]] = OrderedDict()
    for f in res["files"]:
        hits[f["label"]] = [n for r in f["records"] for n in (r["first_line"], r["last_line"])]
    for c in res.get("configuration") or []:
        hits.setdefault(c["file"], []).extend([c["line"]] if c.get("line") else [])
    source_of = {f["label"]: sources.get(f.get("path", f["label"]), ("", False)) for f in files}
    pages = []
    for label, lines in hits.items():
        path, stays = source_of.get(label, ("", False))
        pages.append((label, path, lines, os.path.abspath(path) if path and stays else None))
    return log_viewer.write_pages(report, pages)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--records", required=True, help="records file written by summarize_log_errors")
    ap.add_argument("--title", default="logs", help="what was analyzed, for the report header")
    ap.add_argument("--levels", default="ERROR/FATAL", help="levels reported, for the report")
    ap.add_argument("--skipped", type=int, default=0, help="number of binary files skipped")
    ap.add_argument("--incomplete", metavar="FILE", help="label<tab>reason of each input not fully read")
    ap.add_argument("--compare", metavar="JSON", action="append", default=[],
                    help="the JSON of analyze logs of another input, to compare with (repeatable, oldest first: a trend)")
    ap.add_argument("--ticket-out", metavar="PATH", help="also write the summary for a ticket (Markdown, sanitized) there")
    ap.add_argument("--compare-label", metavar="LABEL", action="append", default=[],
                    help="what that other input is, for the report (one per --compare)")
    ap.add_argument("--json", action="store_true", help="print the analysis as JSON")
    ap.add_argument("--html-out", metavar="PATH", help="write a self-contained HTML report")
    ap.add_argument("--heading", default="🔥 Log Analysis", help="title of the report")
    ap.add_argument("--command", default="playground analyze logs", help="command named in the footer")
    ap.add_argument("--unit", default="file", help="what a label is: file, container, script")
    ap.add_argument("--link", nargs=2, action="append", default=[], metavar=("LABEL", "URL"), help="link in the header")
    ap.add_argument("--section", nargs=2, action="append", default=[], metavar=("TITLE", "FILE"),
                    help="text file shown as is after the findings")
    ap.add_argument("--html-section", nargs=2, action="append", default=[], metavar=("TITLE", "FILE"),
                    help="HTML fragment written by another playground tool (the 🌊 Kafka Streams view of "
                         "tools/streams-analyzer), shown after the findings and the text sections")
    ap.add_argument("--share-zip", metavar="NAME", default="",
                    help="name of the .zip of the report and its file pages, next to it: the 📤 Share panel links to it")
    ap.add_argument("--sources", metavar="FILE",
                    help="label<tab>path<tab>1 when the file stays on disk, of each file analyzed: with --html-out, a page "
                         "per file with findings next to the report (<report>-files/), linked from its locations")
    ap.add_argument("--connector", action="append", default=[], help="keep only the records and configs of this connector")
    ap.add_argument("--with-worker", action="store_true", help="with --connector, also keep what has no connector context")
    ap.add_argument("--text-summary", action="store_true", help="print the bounded text summary of the terminal digest")
    ap.add_argument("--show-config", metavar="NAME", help="print the configs of a connector, config class or client id")
    ap.add_argument("--json-sections", metavar="LIST",
                    help="comma separated sections of the JSON: summary,findings,known_causes,root_causes,files,"
                         "files_without_findings,coverage,configuration,timeline,connectors,comparison,trend,lifecycle,config_lint (default: all)")
    args = ap.parse_args()

    files = parse_records(args.records)
    if args.connector:
        filter_connectors(files, args.connector, args.with_worker)
    res = analyze(files, args.unit)
    if args.connector:
        res["filter"] = {"connectors": args.connector, "with_worker": args.with_worker}
    res["summary"]["binary_files_skipped"] = args.skipped
    res["summary"]["incomplete_inputs"] = read_incomplete(args.incomplete)
    if args.compare:
        prevs, labels = [], []
        for i, path in enumerate(args.compare):
            try:
                with open(path, encoding="utf-8") as fh:
                    prevs.append(json.load(fh))
                labels.append(args.compare_label[i] if i < len(args.compare_label) else path)
            except (OSError, ValueError) as ex:
                print(f"⚠️ --compare: cannot read {path}: {ex}", file=sys.stderr)
        if prevs:
            # the comparison with the last input given (the one just before), the trend over all of them
            res["comparison"] = compare_reports(res, prevs[-1], labels[-1])
            if len(prevs) > 1:
                res["trend"] = trend(res, prevs, labels, args.title)
    res["summary"]["time_zone"] = getattr(files, "time_zone", None) or {"offsets": [], "converted_to_utc": False, "without_offset": False}
    res["summary"]["levels"] = args.levels
    if args.json:
        # the timestamps of every occurrence are only for the timeline and the time filter of the HTML report
        compact = dict(res, files=[dict(f, records=[{k: v for k, v in r.items() if k not in ("timestamps", "index", "file_index")} for r in f["records"]])
                                   for f in res["files"]],
                       root_causes=[{k: v for k, v in c.items() if k != "records_meta"} for c in res["root_causes"]],
                       known_causes=[{k: v for k, v in h.items() if k not in ("records", "_chains")} for h in res["known_causes"]],
                       findings=[{k: v for k, v in f.items() if k not in ("records", "_view")} for f in res["findings"]])
        if args.json_sections:
            sections = [x.strip() for x in args.json_sections.split(",") if x.strip()]
            compact = {k: v for k, v in compact.items() if k in sections}
        if args.connector:
            compact["filter"] = {"connectors": args.connector, "with_worker": args.with_worker}
        # type: playground analyze logs also emits the JSON of cfk-analysis ("cfk-bundle") for a CFK support bundle
        print(json.dumps(dict({"type": "logs"}, **compact), indent=2, ensure_ascii=False))
    if args.text_summary:
        print(text_summary(res, args.connector))
    if args.show_config:
        print(show_config(res, args.show_config))
    if args.ticket_out:
        with open(args.ticket_out, "w", encoding="utf-8") as fh:
            fh.write(ticket_markdown(res, args.title, args.levels, args.unit))
    if args.html_out:
        # written next to it then renamed: the 🔄 progress page of analyze logs, open in the browser at the same path,
        # reloads every 2 s and must never load a half written report (it has no refresh, the tab would stay on it)
        tmp_out = args.html_out + ".partial"
        with open(tmp_out, "w", encoding="utf-8") as fh:
            sections = []
            for title, path in args.section:
                with open(path, encoding="utf-8", errors="replace") as sf:
                    sections.append((title, sf.read()))
            html_sections = []
            for title, path in args.html_section:
                with open(path, encoding="utf-8", errors="replace") as sf:
                    html_sections.append((title, sf.read()))
            viewers = write_viewers(args.html_out, files, res, args.sources) if args.sources else {}
            fh.write(html_report(res, args.title, args.levels, args.skipped, args.heading, args.command, args.unit,
                                 [tuple(l) for l in args.link], sections, viewers, html_sections, args.share_zip))
        os.replace(tmp_out, args.html_out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
