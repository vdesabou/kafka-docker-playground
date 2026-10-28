#!/usr/bin/env python3
"""
HTML report and JSON of the ERROR/FATAL (and WARN) digest of log files, written by playground analyze logs.

The records come from summarize_log_errors (scripts/cli/src/lib/cli_function.sh), the same parser as
playground container logs --errors, run with PG_LOG_DIGEST_RECORDS_FILE set:

  @@PGFILE@@<tab>label<tab>lines<tab>distinct records<tab>occurrences
  @@PGREC@@<tab>level<tab>count<tab>first line<tab>last line<tab>first timestamp<tab>last timestamp
  <the record as printed in the digest, on one or more lines>
  @@PGTS@@<tab>timestamps of the occurrences, space separated

Also used by playground get-ci-result --logs, container logs --errors --html and container display-error-all --html,
and imported by tools/connector-diagnose/diagnose_report.py for the errors section of the connector report.
"""

import argparse
import json
import os
import re
import sys
from collections import OrderedDict
from datetime import datetime
from typing import Dict, List, Optional, Tuple

# no __pycache__ left in the repository
sys.dont_write_bytecode = True
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "report-common"))
from report_html import (SERIES_1, SERIES_2, SEVERITY_ORDER, badge, card, charts_grid, e, findings_html,  # noqa: E402
                         kpi, kpis_html, page, svg_hbars, svg_time_columns, time_bins, verdict_html)

LEVEL_ORDER = {"FATAL": 0, "ERROR": 1, "WARN": 2}
KILLED_TASK_PATTERN = r"Task threw an uncaught and unrecoverable exception|Task is being killed and will not recover"

# well-known causes: (regex on the record, severity, title, what to do)
HINTS = [
    (r"OutOfMemoryError", "CRITICAL", "💥 OutOfMemoryError",
     "the JVM ran out of heap (or metaspace / direct memory): raise -Xmx (KAFKA_HEAP_OPTS) or lower the batch sizes, "
     "and look at what fills the heap with playground debug heap-dump + playground analyze heap-dump"),
    (KILLED_TASK_PATTERN,
     "HIGH", "🧨 A connector task was killed",
     "it stays FAILED until it is restarted: fix the cause (the exception chain of the record), then "
     "playground connector restart --connector <connector>"),
    (r"Failed to find any class that implements Connector|Failed to find any class that implements Converter",
     "HIGH", "🧩 Plugin not found",
     "the connector or converter class is not installed in the plugin.path of the worker (or has a typo)"),
    (r"ClassNotFoundException|NoClassDefFoundError|NoSuchMethodError|NoSuchFieldError",
     "HIGH", "📦 Class loading error",
     "a jar is missing from the plugin, or two versions of a library clash in the plugin path"),
    (r"SaslAuthenticationException|Authentication failed|[Ii]nvalid credentials|ORA-01017|password authentication failed"
     r"|Access denied for user|Login failed for user|401 Unauthorized|Status code\s*:?\s*401",
     "HIGH", "🔑 Authentication failure",
     "check the credentials (user, password, API key, keytab) of the client or of the external system"),
    (r"(Topic|Group|Cluster|TransactionalId)AuthorizationException|[Nn]ot authorized to access|403 Forbidden|Status code\s*:?\s*403",
     "HIGH", "🚫 Authorization failure",
     "an ACL or an RBAC role binding is missing for the principal of the client"),
    (r"SSLHandshakeException|PKIX path building failed|unable to find valid certification path|No subject alternative names",
     "HIGH", "🔐 TLS handshake failure",
     "the truststore does not trust the server certificate, or the hostname does not match it"),
    (r"Unknown magic byte", "HIGH", "🧲 Unknown magic byte",
     "the records were not written with the Schema Registry serializer the converter expects: check key.converter / "
     "value.converter against the producer (playground topic consume shows the real format)"),
    (r"Converting byte\[\] to Kafka Connect data failed|SerializationException|DataException",
     "MEDIUM", "🔀 Serialization or conversion error",
     "the converter does not match the format of the records, or a record does not match the schema; "
     "errors.tolerance=all + a dead letter queue keeps the task running (playground topic dlq inspect)"),
    (r"Connection refused|UnknownHostException|No route to host|connect timed out"
     r"|Connection to node -?\d+ .* could not be established|Communications link failure",
     "HIGH", "🔌 Connection failure",
     "the host is down, unreachable or the name does not resolve: check the host, port and network "
     "(playground debug tcp-dump shows what goes over the wire)"),
    (r"TimeoutException|timed out|Timed out", "MEDIUM", "⏱️ Timeouts",
     "the other side is slow or unreachable: look at the first occurrence, and at what happened just before"),
    (r"RecordTooLargeException|MESSAGE_TOO_LARGE|message.max.bytes", "MEDIUM", "📏 Record too large",
     "raise max.request.size of the producer (producer.override.max.request.size for a source connector) and "
     "message.max.bytes / max.message.bytes on the broker or topic"),
    (r"UnknownTopicOrPartitionException|UNKNOWN_TOPIC_OR_PARTITION", "MEDIUM", "❓ Unknown topic or partition",
     "the topic does not exist and is not auto-created: create it, or check its name"),
    (r"OffsetOutOfRangeException|OFFSET_OUT_OF_RANGE", "MEDIUM", "⏮️ Offset out of range",
     "the committed offset was deleted by retention: the consumer restarts from auto.offset.reset"),
]

EXCEPTION_RE = re.compile(r"^(?:Caused by:\s*)?((?:[a-zA-Z_$][\w$]*\.)+[A-Z][\w$]*(?:Exception|Error|Throwable))(?::\s*(.*))?$")


def parse_records(path: str) -> List[dict]:
    """Files of a records file, each with its records, in the order they were written."""
    files: List[dict] = []
    current: Optional[dict] = None
    rec: Optional[dict] = None
    try:
        fh = open(path, encoding="utf-8", errors="replace")
    except OSError:
        return files
    with fh:
        for raw in fh:
            line = raw.rstrip("\n")
            if line.startswith("@@PGFILE@@\t"):
                parts = line.split("\t")
                current = {"label": parts[1], "lines": int(parts[2]), "distinct": int(parts[3]),
                           "occurrences": int(parts[4]), "records": []}
                files.append(current)
                rec = None
            elif line.startswith("@@PGREC@@\t") and current is not None:
                parts = line.split("\t")
                rec = {"level": parts[1], "count": int(parts[2]), "first_line": int(parts[3]), "last_line": int(parts[4]),
                       "first_ts": parts[5] or None, "last_ts": parts[6] or None, "lines": [], "timestamps": []}
                current["records"].append(rec)
            elif line.startswith("@@PGTS@@\t") and rec is not None:
                rec["timestamps"] = line.split("\t", 1)[1].split()
                finish_record(rec)
                rec = None
            elif rec is not None:
                rec["lines"].append(line)
    for f in files:
        f["records"].sort(key=lambda r: (LEVEL_ORDER.get(r["level"], 9), -r["count"]))
    return files


def finish_record(rec: dict) -> None:
    lines = rec.pop("lines")
    rec["text"] = "\n".join(lines)
    rec["message"] = lines[0] if lines else ""
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
        m = re.search(r"((?:[a-z_$][\w$]*\.)+[A-Z][\w$]*(?:Exception|Error|Throwable))", rec["message"])
        if m:
            rec["root_cause"] = m.group(1)


def all_records(files: List[dict]):
    for f in files:
        for r in f["records"]:
            yield f, r


KILLED_TASK_RE = re.compile(KILLED_TASK_PATTERN)
CONNECTOR_RE = re.compile(r"\[([^\s|\]]+)\|task-\d+\]|Worker(?:Source|Sink)Task\{id=(\S+)-\d+\}")


def earliest(matches: List[Tuple[int, dict, dict]]) -> Tuple[int, dict, dict]:
    """The (file index, file, record) that happened first: by timestamp, else by file and line"""
    return min(matches, key=lambda m: (m[2]["first_ts"] or "~", m[0], m[2]["first_line"]))


def short_exception(line: str) -> str:
    """'Caused by: org.x.FooException: msg' -> 'FooException: msg'"""
    m = EXCEPTION_RE.match(line)
    if not m:
        return line
    return m.group(1).split(".")[-1] + (f": {m.group(2)}" if m.group(2) else "")


def killed_task_chains(matches: List[Tuple[int, dict, dict]]) -> List[dict]:
    """Records of killed tasks grouped by exception chain (exception thrown + deepest cause), in order of first occurrence"""
    groups: Dict[str, dict] = {}
    for idx, f, r in matches:
        thrown = r["chain"][0] if r["chain"] else short_message(r["message"])
        cause = r["chain"][-1] if len(r["chain"]) > 1 else ""
        # same chain on another table, topic or partition: {ORACDC.REDO.DB1-0=OffsetAndMetadata{offset=1}} and digits ignored
        key = re.sub(r"[0-9]+", "#", re.sub(r"\{.*\}", "{…}", f"{thrown}\n{cause}"))
        g = groups.setdefault(key, {"exception": short_exception(thrown), "caused_by": short_exception(cause) if cause else "",
                                    "occurrences": 0, "connectors": OrderedDict(), "matches": []})
        g["occurrences"] += r["count"]
        m = CONNECTOR_RE.search(r["message"])
        if m:
            g["connectors"][m.group(1) or m.group(2)] = True
        g["matches"].append((idx, f, r))
    out = []
    for g in groups.values():
        _, f, r = earliest(g.pop("matches"))
        out.append(dict(g, connectors=list(g["connectors"]), first_file=f["label"], first_line=r["first_line"],
                        first_timestamp=r["first_ts"]))
    out.sort(key=lambda g: (g["first_timestamp"] or "~", g["first_line"]))
    return out


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
        hint = {"severity": severity, "title": title, "occurrences": occurrences, "files": labels,
                "text": f"{title}: {occurrences} occurrence(s) {where}: {advice}"}
        if rx.pattern == KILLED_TASK_RE.pattern:
            # the exception that killed the tasks is what to fix: one line per distinct chain
            chains = killed_task_chains(matches)
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
    m = re.sub(r"^\[?\d{4}-\d{2}-\d{2}[ T][\d:,.]*\]?\s*", "", message)
    m = re.sub(r"^(\[[^]]*\]\s*)?(TRACE|DEBUG|INFO|WARN|WARNING|ERROR|FATAL|SEVERE)\b:?\s*", "", m)
    m = re.sub(r"^\[[^]]*\|[^]]*\]\s*", "", m)
    return re.sub(r"\s*\([\w$.]+:\d+\)\s*$", "", m)


def root_causes(files: List[dict]) -> List[dict]:
    """Records grouped by their deepest exception, or by their message when they have none."""
    causes: Dict[str, dict] = {}
    for f, r in all_records(files):
        # same exception with another message is another cause (ConnectException wraps everything)
        key = (f"{r['root_cause']}: {re.sub(r'[0-9]+', '#', r['root_cause_message'])[:100]}" if r["root_cause"]
               else short_message(r["message"])[:160])
        c = causes.setdefault(key, {"root_cause": r["root_cause"], "label": key, "occurrences": 0, "records": 0, "files": OrderedDict(),
                                    "example": r["root_cause_message"] or short_message(r["message"]), "level": r["level"]})
        c["occurrences"] += r["count"]
        c["records"] += 1
        c["files"][f["label"]] = True
        if LEVEL_ORDER.get(r["level"], 9) < LEVEL_ORDER.get(c["level"], 9):
            c["level"] = r["level"]
    out = []
    for c in causes.values():
        c["files"] = list(c["files"])
        out.append(c)
    out.sort(key=lambda c: (LEVEL_ORDER.get(c["level"], 9), -c["occurrences"]))
    return out


def findings(files: List[dict], hints: List[dict], causes: List[dict], top: int = 5, unit: str = "file") -> List[dict]:
    """Known causes first, then the most frequent root causes no known cause explains."""
    res = [{k: h[k] for k in ("severity", "text", "details") if k in h} for h in hints]
    explained = [re.compile(p) for p, _, _, _ in HINTS]
    added = 0
    for c in causes:
        if added >= top:
            break
        if any(rx.search(c["label"] + " " + c["example"]) for rx in explained):
            continue
        sev = "CRITICAL" if c["level"] == "FATAL" else "HIGH" if c["level"] == "ERROR" else "MEDIUM"
        where = f"{len(c['files'])} {unit}s" if len(c["files"]) > 1 else c["files"][0]
        what = f"{c['root_cause']}: {c['example']}" if c["root_cause"] else c["example"]
        res.append({"severity": sev, "text": f"{c['level']} ×{c['occurrences']} in {where}: {what[:300]}"})
        added += 1
    res.sort(key=lambda x: SEVERITY_ORDER.index(x["severity"]))
    return res


def summary(files: List[dict]) -> dict:
    by_level = {"FATAL": 0, "ERROR": 0, "WARN": 0}
    first, last = None, None
    for _, r in all_records(files):
        by_level[r["level"]] = by_level.get(r["level"], 0) + r["count"]
        for ts in (r["first_ts"], r["last_ts"]):
            if ts:
                first = ts if first is None or ts < first else first
                last = ts if last is None or ts > last else last
    return {"files_scanned": len(files), "files_with_findings": sum(1 for f in files if f["records"]),
            "lines": sum(f["lines"] for f in files), "distinct": sum(f["distinct"] for f in files),
            "occurrences": sum(f["occurrences"] for f in files), "by_level": by_level,
            "first_timestamp": first, "last_timestamp": last}


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


def analyze(files: List[dict], unit: str = "file") -> dict:
    """unit: what a label is (file, container, script), for the texts of the findings"""
    shorten_labels(files)
    hints = match_hints(files, unit)
    causes = root_causes(files)
    return {"summary": summary(files), "findings": findings(files, hints, causes, unit=unit), "known_causes": hints,
            "root_causes": causes, "files": [f for f in files if f["records"]],
            "files_without_findings": [f["label"] for f in files if not f["records"]]}


# ── HTML ──────────────────────────────────────────────────────────────────────

def timeline(files: List[dict]) -> Optional[dict]:
    """Occurrences per time bucket, errors (ERROR + FATAL) and warnings side by side; None without timestamps."""
    points: List[Tuple[datetime, str]] = []
    capped = False
    for _, r in all_records(files):
        if len(r["timestamps"]) < r["count"]:
            capped = True
        for ts in r["timestamps"]:
            try:
                points.append((datetime.strptime(ts, "%Y-%m-%dT%H:%M:%S"), "warnings" if r["level"] == "WARN" else "errors"))
            except ValueError:
                pass
    tl = time_bins(points, ("errors", "warnings"))
    if tl:
        tl["capped"] = capped
    return tl


def svg_timeline(tl: dict) -> str:
    return svg_time_columns(tl, [("errors", "ERROR/FATAL", SERIES_1), ("warnings", "WARN", SERIES_2)],
                            " · first 1000 occurrences of each record" if tl["capped"] else "")


def charts_html(files: List[dict], causes: List[dict]) -> str:
    tl = timeline(files)
    rows = [(f"{c['root_cause'].split('.')[-1]}: {c['example']}" if c["root_cause"] else c["label"],
             c["occurrences"], f"{c['root_cause'] + ': ' + c['example'] if c['root_cause'] else c['label']}: {c['occurrences']} occurrence(s)")
            for c in causes[:10]]
    return charts_grid([("📈 Occurrences over time", svg_timeline(tl) if tl else ""),
                        ("🔝 Root causes (occurrences)", svg_hbars(rows))])


def level_badge(level: str) -> str:
    return badge(level, level.lower())


def records_html(records: List[dict], open_first: int = 3, highlight: Optional[str] = None) -> str:
    """One collapsible block per distinct record; highlight: name that marks the records mentioning it."""
    out = []
    for i, r in enumerate(records):
        when = f"line {r['first_line']}" + (f" ({r['first_ts'].replace('T', ' ')})" if r["first_ts"] else "")
        if r["count"] > 1:
            when += f" → line {r['last_line']}" + (f" ({r['last_ts'].replace('T', ' ')})" if r["last_ts"] else "")
        mine = " <span class='st mine'>this connector</span>" if highlight and highlight in r["text"] else ""
        msg = short_message(r["message"])
        out.append(f"<details{' open' if i < open_first else ''}><summary>{level_badge(r['level'])} ×{r['count']}{mine} "
                   f"<span class='mono'>{e(msg[:180])}</span> <span class='legend'>· {e(when)}</span></summary>"
                   f"<pre>{e(r['text'])}</pre></details>")
    return "".join(out)


def verdict(res: dict, levels: str, unit: str = "file") -> Tuple[str, str]:
    s = res["summary"]
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


def html_report(res: dict, title: str, levels: str, skipped: int, heading: str = "🔥 Log Analysis",
                command: str = "playground analyze logs", unit: str = "file", links: List[Tuple[str, str]] = (),
                sections: List[Tuple[str, str]] = ()) -> str:
    """unit: what a label is (file, container, script); links: (label, url) in the header; sections: (title, text)
    shown as is after the findings (the last lines of a failed CI script...)"""
    s = res["summary"]
    Unit = unit[0].upper() + unit[1:]
    errors = s["by_level"]["FATAL"] + s["by_level"]["ERROR"]
    span = "-"
    if s["first_timestamp"]:
        span = s["first_timestamp"].replace("T", " ")
        if s["last_timestamp"] and s["last_timestamp"] != s["first_timestamp"]:
            span += " → " + s["last_timestamp"].replace("T", " ")
    kpis = "".join([
        kpi(f"🗂️ {Unit}s scanned", s["files_scanned"], f"{s['lines']} lines" + (f", {skipped} binary skipped" if unit == "file" else "")),
        kpi(f"🔥 {Unit}s with findings", s["files_with_findings"], f"{levels} records", "danger" if errors else "warn" if s["files_with_findings"] else "ok"),
        kpi("🧬 Distinct records", s["distinct"], "after de-duplication"),
        kpi("🔁 Occurrences", s["occurrences"], "all levels reported"),
        kpi("💀 FATAL", s["by_level"]["FATAL"], "occurrences", "danger" if s["by_level"]["FATAL"] else "ok"),
        kpi("🔴 ERROR", s["by_level"]["ERROR"], "occurrences", "danger" if s["by_level"]["ERROR"] else "ok"),
        kpi("🟠 WARN", s["by_level"]["WARN"], "occurrences" if "WARN" in levels else "not included (--include-warnings)",
            "warn" if s["by_level"]["WARN"] else ""),
    ])
    body = [verdict_html(*verdict(res, levels, unit)), kpis_html([kpis]), findings_html(res["findings"])]
    body += [card(e(t), f"<pre>{e(text)}</pre>") for t, text in sections]
    body.append(charts_html(res["files"], res["root_causes"]))
    if res["root_causes"]:
        rows = "".join(f"<tr><td>{level_badge(c['level'])}</td><td class='mono' title='{e(c['root_cause'] or '')}'>{e((c['root_cause'] or '—').split('.')[-1])}</td>"
                       f"<td class='mono'>{e(c['example'][:300])}</td><td class='num'>{c['occurrences']}</td>"
                       f"<td class='num'>{c['records']}</td><td class='mono'>{e(', '.join(c['files'][:5]))}"
                       f"{e(' …' if len(c['files']) > 5 else '')}</td></tr>" for c in res["root_causes"])
        body.append("<div class='table-card'><h2>🌳 Root causes (deepest exception of each record)</h2><table><tr><th>Level</th>"
                    "<th>Root cause</th><th>Message</th><th class='num'>Occurrences</th><th class='num'>Records</th>"
                    f"<th>{Unit}s</th></tr>"
                    f"{rows}</table></div>")
    if res["files"]:
        rows = "".join(f"<tr><td class='mono'>{e(f['label'])}</td><td class='num'>{f['lines']}</td><td class='num'>{f['distinct']}</td>"
                       f"<td class='num'>{f['occurrences']}</td>"
                       + "".join(f"<td class='num'>{sum(r['count'] for r in f['records'] if r['level'] == lvl) or ''}</td>" for lvl in ("FATAL", "ERROR", "WARN"))
                       + "</tr>" for f in res["files"])
        body.append(f"<div class='table-card'><h2>🗂️ {Unit}s with findings</h2><table><tr><th>{Unit}</th><th class='num'>Lines</th>"
                    "<th class='num'>Distinct</th><th class='num'>Occurrences</th><th class='num'>FATAL</th><th class='num'>ERROR</th>"
                    f"<th class='num'>WARN</th></tr>{rows}</table>"
                    + (f"<details><summary>✅ {len(res['files_without_findings'])} {unit}(s) without findings</summary><p class='mono'>"
                       + e(", ".join(res["files_without_findings"][:500])) + "</p></details>" if res["files_without_findings"] else "")
                    + "</div>")
        for f in res["files"]:
            body.append(f"<div class='table-card'><h2>📄 {e(f['label'])}</h2>{records_html(f['records'])}</div>")
    meta = [f"&#128196; {e(title)}", f"🕐 {e(span)}", f"Levels: {e(levels)}"]
    meta += [f"<a href='{e(url)}' style='color:#fff'>{e(label)}</a>" for label, url in links]
    return page(f"{heading[2:].strip()} report — {title}", e(heading), meta, "".join(body),
                f"🛠️ Generated by {e(command)} (self-contained, no external resource). Records are cut to 300 "
                "characters per line and to 3 frames of the deepest cause, like the terminal digest.")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--records", required=True, help="records file written by summarize_log_errors")
    ap.add_argument("--title", default="logs", help="what was analyzed, for the report header")
    ap.add_argument("--levels", default="ERROR/FATAL", help="levels reported, for the report")
    ap.add_argument("--skipped", type=int, default=0, help="number of binary files skipped")
    ap.add_argument("--json", action="store_true", help="print the analysis as JSON")
    ap.add_argument("--html-out", metavar="PATH", help="write a self-contained HTML report")
    ap.add_argument("--heading", default="🔥 Log Analysis", help="title of the report")
    ap.add_argument("--command", default="playground analyze logs", help="command named in the footer")
    ap.add_argument("--unit", default="file", help="what a label is: file, container, script")
    ap.add_argument("--link", nargs=2, action="append", default=[], metavar=("LABEL", "URL"), help="link in the header")
    ap.add_argument("--section", nargs=2, action="append", default=[], metavar=("TITLE", "FILE"),
                    help="text file shown as is after the findings")
    args = ap.parse_args()

    res = analyze(parse_records(args.records), args.unit)
    res["summary"]["binary_files_skipped"] = args.skipped
    res["summary"]["levels"] = args.levels
    if args.json:
        # the timestamps of every occurrence are only for the timeline of the HTML report
        compact = dict(res, files=[dict(f, records=[{k: v for k, v in r.items() if k != "timestamps"} for r in f["records"]])
                                   for f in res["files"]])
        print(json.dumps(compact, indent=2, ensure_ascii=False))
    if args.html_out:
        with open(args.html_out, "w", encoding="utf-8") as fh:
            sections = []
            for title, path in args.section:
                with open(path, encoding="utf-8", errors="replace") as sf:
                    sections.append((title, sf.read()))
            fh.write(html_report(res, args.title, args.levels, args.skipped, args.heading, args.command, args.unit,
                                 [tuple(l) for l in args.link], sections))
    return 0


if __name__ == "__main__":
    sys.exit(main())
