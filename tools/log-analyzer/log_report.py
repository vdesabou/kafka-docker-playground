#!/usr/bin/env python3
"""
HTML report and JSON of the ERROR/FATAL (and WARN) digest of log files, written by playground analyze logs.

The records come from summarize_log_errors (scripts/cli/src/lib/cli_function.sh), the same parser as
playground container logs --errors, run with PG_LOG_DIGEST_RECORDS_FILE set:

  @@PGFILE@@<tab>label<tab>lines<tab>distinct records<tab>occurrences
  @@PGREC@@<tab>level<tab>count<tab>first line<tab>last line<tab>first timestamp<tab>last timestamp
  <the record as printed in the digest, on one or more lines>
  @@PGTS@@<tab>timestamps of the occurrences, space separated

Also imported by tools/connector-diagnose/diagnose_report.py for the errors section of the connector report.
"""

import argparse
import json
import re
import sys
from collections import OrderedDict
from datetime import datetime, timedelta
from typing import Dict, List, Optional, Tuple

SEVERITY_ORDER = ["CRITICAL", "HIGH", "MEDIUM", "LOW", "INFO", "OK"]
SEVERITY_ICONS = {"CRITICAL": "🔴", "HIGH": "🟠", "MEDIUM": "🟡", "LOW": "🟢", "INFO": "ℹ️", "OK": "✅"}
LEVEL_ORDER = {"FATAL": 0, "ERROR": 1, "WARN": 2}

# same palette as the other playground reports
SERIES_1 = "#2a78d6"
SERIES_2 = "#eb6834"

# well-known causes: (regex on the record, severity, title, what to do)
HINTS = [
    (r"OutOfMemoryError", "CRITICAL", "💥 OutOfMemoryError",
     "the JVM ran out of heap (or metaspace / direct memory): raise -Xmx (KAFKA_HEAP_OPTS) or lower the batch sizes, "
     "and look at what fills the heap with playground debug heap-dump + playground analyze heap-dump"),
    (r"Task threw an uncaught and unrecoverable exception|Task is being killed and will not recover",
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


def match_hints(files: List[dict]) -> List[dict]:
    out = []
    for pattern, severity, title, advice in HINTS:
        rx = re.compile(pattern)
        occurrences, labels, example = 0, OrderedDict(), None
        for f, r in all_records(files):
            if rx.search(r["text"]):
                occurrences += r["count"]
                labels[f["label"]] = True
                if example is None:
                    example = (f["label"], r["first_line"])
        if occurrences:
            where = (f"in {len(labels)} files (first at {example[0]} line {example[1]})" if len(labels) > 1
                     else f"in {example[0]} (first at line {example[1]})")
            out.append({"severity": severity, "title": title, "occurrences": occurrences, "files": list(labels),
                        "text": f"{title}: {occurrences} occurrence(s) {where}: {advice}"})
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


def findings(files: List[dict], hints: List[dict], causes: List[dict], top: int = 5) -> List[dict]:
    """Known causes first, then the most frequent root causes no known cause explains."""
    res = [{"severity": h["severity"], "text": h["text"]} for h in hints]
    explained = [re.compile(p) for p, _, _, _ in HINTS]
    added = 0
    for c in causes:
        if added >= top:
            break
        if any(rx.search(c["label"] + " " + c["example"]) for rx in explained):
            continue
        sev = "CRITICAL" if c["level"] == "FATAL" else "HIGH" if c["level"] == "ERROR" else "MEDIUM"
        where = f"{len(c['files'])} file(s)" if len(c["files"]) > 1 else c["files"][0]
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


def analyze(files: List[dict]) -> dict:
    shorten_labels(files)
    hints = match_hints(files)
    causes = root_causes(files)
    return {"summary": summary(files), "findings": findings(files, hints, causes), "known_causes": hints,
            "root_causes": causes, "files": [f for f in files if f["records"]],
            "files_without_findings": [f["label"] for f in files if not f["records"]]}


# ── HTML (same look as the other playground reports) ─────────────────────────

HTML_CSS = """<style>
*{box-sizing:border-box;margin:0;padding:0}
body{font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif;background:#f1f5f9;color:#1e293b;line-height:1.5}
.page{max-width:1300px;margin:0 auto;padding:24px}
h1{font-size:1.55rem;font-weight:700}
h2{font-size:1.05rem;font-weight:600;margin-bottom:12px;color:#334155}
h3{font-size:.95rem;font-weight:600;margin:14px 0 8px;color:#334155}
.header{background:linear-gradient(135deg,#1e3a5f 0%,#2563eb 100%);color:#fff;border-radius:12px;padding:22px 28px;margin-bottom:22px}
.header-meta{font-size:.83rem;opacity:.85;margin-top:6px}
.header-meta span{margin-right:18px}
.kpi-grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(175px,1fr));gap:14px;margin-bottom:22px}
.kpi-card{background:#fff;border-radius:10px;padding:14px 16px;box-shadow:0 1px 3px rgba(0,0,0,.07);border-left:4px solid #2563eb}
.kpi-card.warn{border-left-color:#d97706}.kpi-card.danger{border-left-color:#dc2626}.kpi-card.ok{border-left-color:#16a34a}
.kpi-label{font-size:.75rem;color:#64748b;text-transform:uppercase;letter-spacing:.05em}
.kpi-value{font-size:1.75rem;font-weight:700;margin:3px 0 2px;word-break:break-word}
.kpi-unit{font-size:.73rem;color:#94a3b8}
.charts-grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(560px,1fr));gap:18px;margin-bottom:22px}
.chart-card{background:#fff;border-radius:10px;padding:18px 20px;box-shadow:0 1px 3px rgba(0,0,0,.07)}
.chart-card svg{width:100%;height:auto}
.chart-card svg rect:hover{opacity:.75}
.legend{font-size:.78rem;color:#475569;margin-bottom:6px}
.legend i{display:inline-block;width:10px;height:10px;border-radius:2px;margin:0 5px 0 12px;vertical-align:-1px}
.section-title{font-size:1.05rem;font-weight:600;color:#334155;margin:0 0 12px;padding-top:4px}
.recs-list{display:flex;flex-direction:column;gap:9px;margin-bottom:22px}
.rec-card{background:#fff;border-radius:8px;padding:12px 14px 12px 18px;box-shadow:0 1px 3px rgba(0,0,0,.06);border-left:5px solid #94a3b8;display:flex;align-items:flex-start;gap:10px}
.rec-card.critical{border-left-color:#dc2626}.rec-card.high{border-left-color:#ea580c}.rec-card.medium{border-left-color:#d97706}
.rec-card.low{border-left-color:#16a34a}.rec-card.info{border-left-color:#3b82f6}.rec-card.ok{border-left-color:#0891b2}
.rec-badge{font-size:.68rem;font-weight:700;text-transform:uppercase;padding:2px 7px;border-radius:20px;white-space:nowrap;margin-top:2px}
.rec-badge.critical{background:#fee2e2;color:#dc2626}.rec-badge.high{background:#ffedd5;color:#ea580c}.rec-badge.medium{background:#fef3c7;color:#d97706}
.rec-badge.low{background:#dcfce7;color:#16a34a}.rec-badge.info{background:#dbeafe;color:#2563eb}.rec-badge.ok{background:#cffafe;color:#0891b2}
.rec-text{font-size:.88rem;flex:1;color:#334155}
.table-card{background:#fff;border-radius:10px;padding:18px 20px;box-shadow:0 1px 3px rgba(0,0,0,.07);overflow-x:auto;margin-bottom:22px}
table{width:100%;border-collapse:collapse;font-size:.84rem}
th{text-align:left;padding:7px 11px;background:#f8fafc;font-weight:600;border-bottom:2px solid #e2e8f0;color:#475569}
td{padding:7px 11px;border-bottom:1px solid #f1f5f9;vertical-align:top}
td.num,th.num{text-align:right;font-variant-numeric:tabular-nums}
tr:hover td{background:#f8fafc}
.mono{font-family:'SFMono-Regular',Consolas,'Liberation Mono',Menlo,monospace;font-size:.78rem;word-break:break-all}
details{border-top:1px solid #f1f5f9;padding:2px 0}
details summary{cursor:pointer;font-size:.84rem;padding:6px 0}
.st{display:inline-block;font-size:.68rem;font-weight:700;padding:1px 7px;border-radius:12px;background:#f1f5f9;color:#475569;white-space:nowrap}
.st.fatal,.st.failed{background:#fee2e2;color:#dc2626}.st.error{background:#ffedd5;color:#c2410c}.st.warn,.st.paused,.st.unassigned{background:#fef3c7;color:#b45309}
.st.running{background:#dcfce7;color:#15803d}.st.mine{background:#dbeafe;color:#1d4ed8}
.verdict{background:#fff;border-radius:10px;padding:14px 18px;box-shadow:0 1px 3px rgba(0,0,0,.07);border-left:4px solid #16a34a;font-size:1rem;font-weight:500;margin-bottom:22px}
.verdict.danger{border-left-color:#dc2626}.verdict.warn{border-left-color:#d97706}.verdict.ok{border-left-color:#16a34a}
pre{font-family:'SFMono-Regular',Consolas,Menlo,monospace;font-size:.76rem;background:#f8fafc;padding:10px;border-radius:6px;overflow-x:auto;white-space:pre-wrap;word-break:break-all;margin:4px 0 8px}
.footer{text-align:center;font-size:.78rem;color:#94a3b8;padding:14px}
</style>"""


def e(s) -> str:
    return (str(s).replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace('"', "&quot;"))


def kpi(label, val, unit, cls="") -> str:
    return (f'<div class="kpi-card {cls}"><div class="kpi-label">{e(label)}</div>'
            f'<div class="kpi-value">{e(val)}</div><div class="kpi-unit">{e(unit)}</div></div>')


def findings_html(items: List[dict]) -> str:
    if not items:
        return ""
    return ("<div class='section-title'>🔎 Findings</div><div class='recs-list'>"
            + "".join(f'<div class="rec-card {f["severity"].lower()}"><span class="rec-badge {f["severity"].lower()}">'
                      f'{SEVERITY_ICONS.get(f["severity"], "")} {e(f["severity"])}</span><span class="rec-text">{e(f["text"])}</span></div>'
                      for f in items)
            + "</div>")


def nice_max(v: float) -> int:
    """Axis maximum: an even integer of the form 1, 2, 2.5, 3, 4, 5, 6 or 8 x 10^n, so that the middle tick is an integer too."""
    if v <= 2:
        return 2
    magnitude = 10 ** (len(str(int(v))) - 1)
    for m in (1, 2, 2.5, 3, 4, 5, 6, 8, 10):
        top = int(m * magnitude)
        if top >= v and top % 2 == 0:
            return top
    return int(10 * magnitude)


BUCKETS = [1, 5, 10, 30, 60, 300, 600, 1800, 3600, 7200, 21600, 43200, 86400]


def fmt_bucket(seconds: int) -> str:
    if seconds < 60:
        return f"{seconds}s"
    if seconds < 3600:
        return f"{seconds // 60}min"
    if seconds < 86400:
        return f"{seconds // 3600}h"
    return f"{seconds // 86400}d"


def timeline(files: List[dict]) -> Optional[dict]:
    """Occurrences per time bucket, errors (ERROR + FATAL) and warnings side by side; None without timestamps."""
    points: List[Tuple[datetime, str]] = []
    capped = False
    for _, r in all_records(files):
        if len(r["timestamps"]) < r["count"]:
            capped = True
        for ts in r["timestamps"]:
            try:
                points.append((datetime.strptime(ts, "%Y-%m-%dT%H:%M:%S"), r["level"]))
            except ValueError:
                pass
    if not points:
        return None
    start = min(p[0] for p in points)
    end = max(p[0] for p in points)
    span = (end - start).total_seconds()
    bucket = next((b for b in BUCKETS if span / b <= 60), BUCKETS[-1])
    start = datetime.fromtimestamp(int(start.timestamp()) // bucket * bucket)
    n = int((end - start).total_seconds() // bucket) + 1
    bins = [{"start": start + timedelta(seconds=i * bucket), "errors": 0, "warnings": 0} for i in range(n)]
    for ts, level in points:
        i = int((ts - start).total_seconds() // bucket)
        bins[i]["warnings" if level == "WARN" else "errors"] += 1
    return {"bucket": bucket, "bins": bins, "capped": capped}


def svg_timeline(tl: dict) -> str:
    bins = tl["bins"]
    series = [("errors", "ERROR/FATAL", SERIES_1)]
    if any(b["warnings"] for b in bins):
        series.append(("warnings", "WARN", SERIES_2))
    W, H, L, B, T = 600, 190, 44, 26, 8
    pw, ph = W - L - 10, H - B - T
    mx = nice_max(max((b[k] for b in bins for k, _, _ in series), default=0))
    n = len(bins)
    slot = pw / n
    bw = max(1.0, (slot - 2) / len(series))
    one_day = bins[0]["start"].date() == bins[-1]["start"].date()
    fmt = "%H:%M:%S" if tl["bucket"] < 60 else "%H:%M" if one_day else "%m-%d %H:%M"
    out = [f'<svg viewBox="0 0 {W} {H}" xmlns="http://www.w3.org/2000/svg" role="img">']
    for frac in (0, 0.5, 1):
        y = T + ph * (1 - frac)
        out.append(f'<line x1="{L}" x2="{W - 10}" y1="{y:.1f}" y2="{y:.1f}" stroke="#e2e8f0" stroke-width="1"/>'
                   f'<text x="{L - 6}" y="{y + 3:.1f}" font-size="10" fill="#64748b" text-anchor="end">{int(mx * frac)}</text>')
    for i, b in enumerate(bins):
        for j, (key, label, color) in enumerate(series):
            v = b[key]
            if not v:
                continue
            h = max(1.5, ph * v / mx)
            x = L + i * slot + 1 + j * bw
            out.append(f'<rect x="{x:.1f}" y="{T + ph - h:.1f}" width="{bw:.1f}" height="{h:.1f}" rx="1" fill="{color}">'
                       f'<title>{b["start"].strftime("%Y-%m-%d %H:%M:%S")}: {v} {label}</title></rect>')
    step = max(1, n // 6)
    for i in range(0, n, step):
        out.append(f'<text x="{L + i * slot + slot / 2:.1f}" y="{H - 8}" font-size="10" fill="#64748b" text-anchor="middle">'
                   f'{bins[i]["start"].strftime(fmt)}</text>')
    out.append("</svg>")
    legend = "".join(f"<i style='background:{c}'></i>{l}" for _, l, c in series)
    note = " · first 1000 occurrences of each record" if tl["capped"] else ""
    return f"<div class='legend'>{legend} · per {fmt_bucket(tl['bucket'])}{note}</div>" + "".join(out)


def svg_hbars(rows: List[Tuple[str, float, str]]) -> str:
    W, rowh, L = 600, 22, 300
    H = 10 + rowh * len(rows)
    mx = max(v for _, v, _ in rows) or 1
    out = [f'<svg viewBox="0 0 {W} {H}" xmlns="http://www.w3.org/2000/svg" role="img">']
    for i, (lab, v, tip) in enumerate(rows):
        y = 5 + i * rowh
        w = (W - L - 60) * v / mx
        out.append(f'<text x="{L - 6}" y="{y + 14}" font-size="10" fill="#334155" text-anchor="end">{e(lab[:52])}</text>'
                   f'<rect x="{L}" y="{y + 3}" width="{max(1, w):.1f}" height="15" rx="2" fill="{SERIES_1}"><title>{e(tip)}</title></rect>'
                   f'<text x="{L + w + 5:.1f}" y="{y + 14}" font-size="10" fill="#475569">{int(v)}</text>')
    out.append("</svg>")
    return "".join(out)


def charts_html(files: List[dict], causes: List[dict]) -> str:
    cards = []
    tl = timeline(files)
    if tl:
        cards.append(f"<div class='chart-card'><h2>📈 Occurrences over time</h2>{svg_timeline(tl)}</div>")
    rows = [(f"{c['root_cause'].split('.')[-1]}: {c['example']}" if c["root_cause"] else c["label"],
             c["occurrences"], f"{c['root_cause'] + ': ' + c['example'] if c['root_cause'] else c['label']}: {c['occurrences']} occurrence(s)")
            for c in causes[:10]]
    if rows:
        cards.append(f"<div class='chart-card'><h2>🔝 Root causes (occurrences)</h2>{svg_hbars(rows)}</div>")
    return f"<div class='charts-grid'>{''.join(cards)}</div>" if cards else ""


def level_badge(level: str) -> str:
    return f"<span class='st {e(level.lower())}'>{e(level)}</span>"


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


def page(title: str, h1: str, meta: List[str], body: str, footer: str) -> str:
    return ("<!DOCTYPE html><html lang='en'><head><meta charset='UTF-8'><meta name='viewport' content='width=device-width,initial-scale=1'>"
            f"<title>{e(title)}</title>{HTML_CSS}</head><body><div class='page'>"
            f"<div class='header'><h1>{h1}</h1><div class='header-meta'>"
            + "".join(f"<span>{m}</span>" for m in meta) + "</div></div>"
            + body + f"<div class='footer'>{footer}</div></div></body></html>")


def verdict(res: dict, levels: str) -> Tuple[str, str]:
    s = res["summary"]
    if not s["files_with_findings"]:
        return "ok", f"✅ No {levels} record in the {s['files_scanned']} file(s) scanned ({s['lines']} lines)."
    top = res["findings"][0] if res["findings"] else None
    errors = s["by_level"]["FATAL"] + s["by_level"]["ERROR"]
    if errors:
        start = f": start with {top['text'].split(': ')[0]}" if top else ""
        return "danger", (f"🚨 {errors} ERROR/FATAL occurrence(s), {s['distinct']} distinct record(s) in "
                          f"{s['files_with_findings']} file(s){start}.")
    return "warn", f"⚠️ {s['by_level']['WARN']} WARN occurrence(s) in {s['files_with_findings']} file(s), no ERROR/FATAL."


def html_report(res: dict, title: str, levels: str, skipped: int) -> str:
    s = res["summary"]
    errors = s["by_level"]["FATAL"] + s["by_level"]["ERROR"]
    span = "-"
    if s["first_timestamp"]:
        span = s["first_timestamp"].replace("T", " ")
        if s["last_timestamp"] and s["last_timestamp"] != s["first_timestamp"]:
            span += " → " + s["last_timestamp"].replace("T", " ")
    kpis = "".join([
        kpi("🗂️ Files scanned", s["files_scanned"], f"{s['lines']} lines, {skipped} binary skipped"),
        kpi("🔥 Files with findings", s["files_with_findings"], f"{levels} records", "danger" if errors else "warn" if s["files_with_findings"] else "ok"),
        kpi("🧬 Distinct records", s["distinct"], "after de-duplication"),
        kpi("🔁 Occurrences", s["occurrences"], "all levels reported"),
        kpi("💀 FATAL", s["by_level"]["FATAL"], "occurrences", "danger" if s["by_level"]["FATAL"] else "ok"),
        kpi("🔴 ERROR", s["by_level"]["ERROR"], "occurrences", "danger" if s["by_level"]["ERROR"] else "ok"),
        kpi("🟠 WARN", s["by_level"]["WARN"], "occurrences" if "WARN" in levels else "not included (--include-warnings)",
            "warn" if s["by_level"]["WARN"] else ""),
    ])
    body = [f"<div class='verdict {verdict(res, levels)[0]}'>{e(verdict(res, levels)[1])}</div>",
            f"<div class='kpi-grid'>{kpis}</div>", findings_html(res["findings"]),
            charts_html(res["files"], res["root_causes"])]
    if res["root_causes"]:
        rows = "".join(f"<tr><td>{level_badge(c['level'])}</td><td class='mono' title='{e(c['root_cause'] or '')}'>{e((c['root_cause'] or '—').split('.')[-1])}</td>"
                       f"<td class='mono'>{e(c['example'][:300])}</td><td class='num'>{c['occurrences']}</td>"
                       f"<td class='num'>{c['records']}</td><td class='mono'>{e(', '.join(c['files'][:5]))}"
                       f"{e(' …' if len(c['files']) > 5 else '')}</td></tr>" for c in res["root_causes"])
        body.append("<div class='table-card'><h2>🌳 Root causes (deepest exception of each record)</h2><table><tr><th>Level</th>"
                    "<th>Root cause</th><th>Message</th><th class='num'>Occurrences</th><th class='num'>Records</th><th>Files</th></tr>"
                    f"{rows}</table></div>")
    if res["files"]:
        rows = "".join(f"<tr><td class='mono'>{e(f['label'])}</td><td class='num'>{f['lines']}</td><td class='num'>{f['distinct']}</td>"
                       f"<td class='num'>{f['occurrences']}</td>"
                       + "".join(f"<td class='num'>{sum(r['count'] for r in f['records'] if r['level'] == lvl) or ''}</td>" for lvl in ("FATAL", "ERROR", "WARN"))
                       + "</tr>" for f in res["files"])
        body.append("<div class='table-card'><h2>🗂️ Files with findings</h2><table><tr><th>File</th><th class='num'>Lines</th>"
                    "<th class='num'>Distinct</th><th class='num'>Occurrences</th><th class='num'>FATAL</th><th class='num'>ERROR</th>"
                    f"<th class='num'>WARN</th></tr>{rows}</table>"
                    + (f"<details><summary>✅ {len(res['files_without_findings'])} file(s) without findings</summary><p class='mono'>"
                       + e(", ".join(res["files_without_findings"][:500])) + "</p></details>" if res["files_without_findings"] else "")
                    + "</div>")
        for f in res["files"]:
            body.append(f"<div class='table-card'><h2>📄 {e(f['label'])}</h2>{records_html(f['records'])}</div>")
    meta = [f"&#128196; {e(title)}", f"🕐 {e(span)}", f"Levels: {e(levels)}", f"Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}"]
    return page(f"Log analysis report — {title}", "🔥 Log Analysis", meta, "".join(body),
                "🛠️ Generated by playground analyze logs (self-contained, no external resource). Records are cut to 300 "
                "characters per line and to 3 frames of the deepest cause, like the terminal digest.")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--records", required=True, help="records file written by summarize_log_errors")
    ap.add_argument("--title", default="logs", help="what was analyzed, for the report header")
    ap.add_argument("--levels", default="ERROR/FATAL", help="levels reported, for the report")
    ap.add_argument("--skipped", type=int, default=0, help="number of binary files skipped")
    ap.add_argument("--json", action="store_true", help="print the analysis as JSON")
    ap.add_argument("--html-out", metavar="PATH", help="write a self-contained HTML report")
    args = ap.parse_args()

    res = analyze(parse_records(args.records))
    res["summary"]["binary_files_skipped"] = args.skipped
    res["summary"]["levels"] = args.levels
    if args.json:
        # the timestamps of every occurrence are only for the timeline of the HTML report
        compact = dict(res, files=[dict(f, records=[{k: v for k, v in r.items() if k != "timestamps"} for r in f["records"]])
                                   for f in res["files"]])
        print(json.dumps(compact, indent=2, ensure_ascii=False))
    if args.html_out:
        with open(args.html_out, "w", encoding="utf-8") as fh:
            fh.write(html_report(res, args.title, args.levels, args.skipped))
    return 0


if __name__ == "__main__":
    sys.exit(main())
