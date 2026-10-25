#!/usr/bin/env python3
"""
HTML report of playground connector diagnose: one section per connector with its status and tasks (with the trace of
a failed task), the errors of the connect worker (self-managed) or the Confluent Cloud error recommendations (fully
managed), the consumer lag or the offsets, the configuration and the next steps.

Each --connector-dir is a folder written by playground connector diagnose:

  meta.json            connector, connector_type, is_cloud, type, since, environment
  status.json          GET /connectors/<connector>/status
  config.json          GET /connectors/<connector>/config
  errors.records       records of the connect logs (see tools/log-analyzer/log_report.py), self-managed
  recommendations.txt  output of playground connector error-recommendations, fully managed
  lag.txt              output of playground connector show-lag, sink with all tasks RUNNING
  offsets.txt          output of playground connector offsets get, otherwise
  next_steps.txt       one command or advice per line
"""

import argparse
import json
import os
import re
import sys
from typing import List, Optional, Tuple

# no __pycache__ left in the repository
sys.dont_write_bytecode = True
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "log-analyzer"))
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "report-common"))
import log_report as lr  # noqa: E402
import report_html as rh  # noqa: E402

ANSI_RE = re.compile(r"\x1b\[[0-9;]*m")
LAG_RE = re.compile(r"topic:\s*(\S+)\s+partition:\s*(\d+)\s+current-offset:\s*(\S+)\s+end-offset:\s*(\S+)\s+lag:\s*(\S+)")


def read(path: str) -> str:
    try:
        with open(path, encoding="utf-8", errors="replace") as fh:
            return ANSI_RE.sub("", fh.read())
    except OSError:
        return ""


def read_json(path: str):
    try:
        return json.loads(read(path))
    except ValueError:
        return None


def first_json_block(text: str):
    """The pretty-printed JSON that offsets get prints (with jq) after its log lines."""
    start = text.find("{")
    while start != -1:
        depth = 0
        for i in range(start, len(text)):
            if text[i] == "{":
                depth += 1
            elif text[i] == "}":
                depth -= 1
                if depth == 0:
                    try:
                        return json.loads(text[start:i + 1])
                    except ValueError:
                        break
        start = text.find("{", start + 1)
    return None


def trace_summary(trace: str) -> str:
    """Deepest exception of a task trace: its last "Caused by:" line, else its first line."""
    lines = [l.strip() for l in trace.splitlines() if l.strip()]
    causes = [l for l in lines if l.startswith("Caused by:")]
    return (causes[-1][len("Caused by:"):].strip() if causes else lines[0]) if lines else ""


def load(d: str) -> dict:
    meta = read_json(os.path.join(d, "meta.json")) or {}
    status = read_json(os.path.join(d, "status.json")) or {}
    config = read_json(os.path.join(d, "config.json"))
    if not isinstance(config, dict) or "error_code" in config or "error" in config:
        config = None
    c = {"meta": meta, "name": meta.get("connector") or status.get("name", "?"), "is_cloud": meta.get("is_cloud") == "1",
         "type": status.get("type") or meta.get("type") or "?", "config": config}
    conn = status.get("connector") or {}
    c["state"] = conn.get("state", "UNKNOWN")
    c["worker"] = conn.get("worker_id", "")
    c["connector_trace"] = conn.get("trace", "")
    c["tasks"] = sorted(status.get("tasks") or [], key=lambda t: t.get("id", 0))
    c["records"] = []
    rec_path = os.path.join(d, "errors.records")
    if os.path.exists(rec_path):
        c["log_files"] = lr.parse_records(rec_path)
        c["records"] = [r for f in c["log_files"] for r in f["records"]]
    else:
        c["log_files"] = None
    c["recommendations"] = read(os.path.join(d, "recommendations.txt")).strip()
    lag: dict = {}
    for line in read(os.path.join(d, "lag.txt")).splitlines():
        m = LAG_RE.search(line)
        if m:
            # show-lag may poll more than once: the last line of a partition wins
            lag[(m.group(1), int(m.group(2)))] = {"topic": m.group(1), "partition": int(m.group(2)), "current": m.group(3),
                                                   "end": m.group(4), "lag": m.group(5)}
    c["lag"] = sorted(lag.values(), key=lambda x: (x["topic"], x["partition"]))
    offsets_text = read(os.path.join(d, "offsets.txt"))
    c["offsets"] = first_json_block(offsets_text)
    c["offsets_text"] = offsets_text.strip() if offsets_text.strip() and c["offsets"] is None else ""
    c["next_steps"] = [l.rstrip() for l in read(os.path.join(d, "next_steps.txt")).splitlines() if l.strip()]
    return c


def to_int(v) -> Optional[int]:
    try:
        return int(v)
    except (TypeError, ValueError):
        return None


def mentions(c: dict, r: dict) -> bool:
    return f"{c['name']}|" in r["text"] or f"id={c['name']}-" in r["text"] or f"'{c['name']}'" in r["text"] or f" {c['name']} " in r["text"]


def assess(c: dict) -> dict:
    states = [t.get("state", "UNKNOWN") for t in c["tasks"]]
    failed = [t for t in c["tasks"] if t.get("state") == "FAILED"]
    total_lag = sum(to_int(x["lag"]) or 0 for x in c["lag"])
    mine = [r for r in c["records"] if mentions(c, r)]
    errors = [r for r in c["records"] if r["level"] in ("FATAL", "ERROR")]
    c.update({"failed_tasks": failed, "total_lag": total_lag, "my_records": mine, "error_records": errors,
              "running_tasks": states.count("RUNNING")})

    f: List[dict] = []
    if c["state"] == "FAILED":
        f.append({"severity": "CRITICAL", "text": f"🔥 The connector FAILED: {trace_summary(c['connector_trace']) or 'no trace'}"})
    for t in failed:
        f.append({"severity": "CRITICAL", "text": f"🔥 Task {t.get('id')} FAILED on {t.get('worker_id', '?')}: "
                                                  f"{trace_summary(t.get('trace', '')) or 'no trace'}"})
    if c["state"] == "PAUSED" or "PAUSED" in states:
        f.append({"severity": "MEDIUM", "text": f"⏸️ The connector is PAUSED: playground connector resume --connector {c['name']}"})
    if c["state"] == "UNASSIGNED" or "UNASSIGNED" in states:
        f.append({"severity": "HIGH", "text": "⌛ The connector or a task is UNASSIGNED: the worker that owned it left the group "
                                              "and the rebalance did not complete (scheduled.rebalance.max.delay.ms), or it is still starting"})
    if not c["tasks"] and c["state"] == "RUNNING":
        f.append({"severity": "HIGH", "text": "🫥 The connector is RUNNING but has no task: tasks.max, or a source with nothing to "
                                              "split (no table, no file) — look at the connector logs"})
    if c["lag"] and total_lag > 0:
        f.append({"severity": "MEDIUM", "text": f"🐢 Consumer lag of {total_lag} record(s) on {sum(1 for x in c['lag'] if (to_int(x['lag']) or 0) > 0)} "
                                                f"partition(s): run diagnose again to see whether it goes down"})
    if c["log_files"] is not None:
        hints = lr.match_hints([{"label": f["label"], "records": [r for r in f["records"] if mentions(c, r)]} for f in c["log_files"]])
        f.extend({"severity": h["severity"], "text": h["text"].replace("<connector>", c["name"])} for h in hints)
        others = len([r for r in errors if r not in mine])
        if others:
            f.append({"severity": "INFO", "text": f"ℹ️ {others} other distinct ERROR/FATAL record(s) in the worker logs do not name "
                                                  "this connector: they can still explain it (worker, other connectors, Kafka clients)"})
    f.sort(key=lambda x: rh.SEVERITY_ORDER.index(x["severity"]))
    c["findings"] = f

    if c["state"] == "FAILED" or failed:
        c["verdict"] = ("danger", f"🔥 {c['name']}: {'the connector' if c['state'] == 'FAILED' else str(len(failed)) + ' task(s)'} FAILED. "
                                  "Read the trace, fix the cause, then restart it.")
    elif c["state"] in ("PAUSED", "UNASSIGNED") or "PAUSED" in states or "UNASSIGNED" in states:
        c["verdict"] = ("warn", f"⚠️ {c['name']} is not processing: {c['state']}, tasks {', '.join(sorted(set(states))) or 'none'}.")
    elif c["state"] != "RUNNING":
        c["verdict"] = ("warn", f"⚠️ {c['name']} is {c['state']}.")
    elif c["lag"] and total_lag > 0:
        c["verdict"] = ("warn", f"🐢 {c['name']} is RUNNING with a lag of {total_lag} record(s).")
    elif mine:
        c["verdict"] = ("warn", f"⚠️ {c['name']} is RUNNING, but the worker logged {len(mine)} distinct record(s) naming it.")
    else:
        c["verdict"] = ("ok", f"✅ {c['name']} is RUNNING ({c['running_tasks']}/{len(c['tasks'])} task(s))"
                              + (", no lag." if c["lag"] else "."))
    return c


def st(state: str) -> str:
    return f"<span class='st {rh.e(state.lower())}'>{rh.e(state)}</span>"


def tasks_html(c: dict) -> str:
    rows = [f"<tr><td>connector</td><td>{st(c['state'])}</td><td class='mono' style='white-space:nowrap'>{rh.e(c['worker'])}</td>"
            f"<td>{trace_html(c['connector_trace'])}</td></tr>"]
    rows += [f"<tr><td style='white-space:nowrap'>task {t.get('id')}</td><td>{st(t.get('state', '?'))}</td><td class='mono' style='white-space:nowrap'>{rh.e(t.get('worker_id', ''))}</td>"
             f"<td>{trace_html(t.get('trace', ''))}</td></tr>" for t in c["tasks"]]
    return ("<div class='table-card'><h2>🗺️ Status</h2><table><tr><th>What</th><th>State</th><th>Worker</th><th>Trace</th></tr>"
            + "".join(rows) + "</table></div>")


def trace_html(trace: str) -> str:
    if not trace:
        return "<span class='legend'>-</span>"
    # the summary is the deepest cause, the full trace is one click away
    return f"<details><summary class='mono'>{rh.e(trace_summary(trace)[:240])}</summary><pre>{rh.e(trace)}</pre></details>"


def errors_html(c: dict) -> str:
    if c["is_cloud"]:
        body = f"<pre>{rh.e(c['recommendations'])}</pre>" if c["recommendations"] else "<p>✅ No error recommendation.</p>"
        return f"<div class='table-card'><h2>🔥 Confluent Cloud error recommendations</h2>{body}</div>"
    if c["log_files"] is None:
        return ""
    since = c["meta"].get("since", "")
    if not c["records"]:
        return (f"<div class='table-card'><h2>🔥 Errors in the connect logs (since {rh.e(since)})</h2>"
                "<p>✅ No ERROR/FATAL record in the connect logs.</p></div>")
    mine, others = c["my_records"], [r for r in c["records"] if r not in c["my_records"]]
    body = ""
    if mine:
        body += f"<h3>Naming {rh.e(c['name'])} ({len(mine)})</h3>{lr.records_html(mine, open_first=3)}"
    if others:
        body += (f"<h3>Elsewhere in the worker ({len(others)})</h3>"
                 f"{lr.records_html(others, open_first=0 if mine else 2)}")
    return (f"<div class='table-card'><h2>🔥 Errors in the connect logs (since {rh.e(since)}, whole worker)</h2>{body}"
            "<p class='legend' style='margin-top:10px'>De-duplicated like playground container logs --errors: one block per "
            "distinct record, with its number of occurrences and its exception chain.</p></div>")


def lag_html(c: dict) -> str:
    if c["lag"]:
        mx = max((to_int(x["lag"]) or 0) for x in c["lag"]) or 1
        rows = []
        for x in c["lag"]:
            lag = to_int(x["lag"]) or 0
            cur, end = to_int(x["current"]), to_int(x["end"])
            pct = 100 if not end else int(100 * (cur or 0) / end)
            bar = (f"<svg viewBox='0 0 200 12' width='200' height='12'><rect width='200' height='12' rx='2' fill='#e2e8f0'/>"
                   f"<rect width='{2 * pct}' height='12' rx='2' fill='{rh.SERIES_1}'><title>{pct}% consumed</title></rect></svg>")
            lag_style = ' style="color:#c2410c;font-weight:600"' if lag else ""
            rows.append(f"<tr><td class='mono'>{rh.e(x['topic'])}</td><td class='num'>{x['partition']}</td><td class='num'>{rh.e(x['current'])}</td>"
                        f"<td class='num'>{rh.e(x['end'])}</td><td class='num'{lag_style}>{rh.e(x['lag'])}</td>"
                        f"<td>{bar}</td></tr>")
        return (f"<div class='table-card'><h2>🐢 Consumer lag ({c['total_lag']} record(s))</h2><table><tr><th>Topic</th>"
                "<th class='num'>Partition</th><th class='num'>Committed</th><th class='num'>End offset</th><th class='num'>Lag</th>"
                f"<th>Consumed</th></tr>{''.join(rows)}</table></div>")
    if c["offsets"] is not None:
        items = c["offsets"].get("offsets") if isinstance(c["offsets"], dict) else None
        if items:
            rows = "".join(f"<tr><td class='mono'>{rh.e(json.dumps(o.get('partition'), sort_keys=True))}</td>"
                           f"<td class='mono'>{rh.e(json.dumps(o.get('offset'), sort_keys=True))}</td></tr>" for o in items)
            what = "committed offsets of the sink" if c["type"] == "sink" else "offsets of the source"
            return (f"<div class='table-card'><h2>🐢 Progress: {what}</h2><table><tr><th>Partition</th><th>Offset</th></tr>{rows}</table>"
                    "<p class='legend' style='margin-top:10px'>Run playground connector diagnose again to see whether they move.</p></div>")
        if isinstance(c["offsets"], dict) and c["offsets"].get("offsets") == []:
            why = ("no offset committed yet: it failed or started less than offset.flush.interval.ms (60 s by default) ago"
                   if c["type"] == "sink" else "no offset committed yet")
            return f"<div class='table-card'><h2>🐢 Progress: offsets</h2><p>ℹ️ {rh.e(why)}.</p></div>"
        return f"<div class='table-card'><h2>🐢 Progress: offsets</h2><pre>{rh.e(json.dumps(c['offsets'], indent=2))}</pre></div>"
    if c["offsets_text"]:
        return f"<div class='table-card'><h2>🐢 Progress</h2><pre>{rh.e(c['offsets_text'])}</pre></div>"
    return ""


def config_html(c: dict) -> str:
    if not c["config"]:
        return ""
    rows = "".join(f"<tr><td class='mono'>{rh.e(k)}</td><td class='mono'>{rh.e(rh.mask_secret(k, v))}</td></tr>" for k, v in sorted(c["config"].items()))
    return (f"<div class='table-card'><details><summary><b>⚙️ Configuration ({len(c['config'])} keys, secrets masked)</b></summary>"
            f"<table><tr><th>Key</th><th>Value</th></tr>{rows}</table></details></div>")


def next_steps_html(c: dict) -> str:
    if not c["next_steps"]:
        return ""
    items = "".join(f"<pre>{rh.e(s.strip())}</pre>" if s.strip().startswith("playground ") else f"<p class='rec-text' style='margin:6px 0'>{rh.e(s.strip())}</p>"
                    for s in c["next_steps"])
    return f"<div class='table-card'><h2>👉 Next steps</h2>{items}</div>"


def connector_html(c: dict, several: bool) -> str:
    klass = (c["config"] or {}).get("connector.class", "")
    kind = "☁️ fully managed" if c["is_cloud"] else "🌎 self-managed"
    errors_kpi = (rh.kpi("🔥 Error records", len(c["error_records"]), f"{len(c['my_records'])} naming the connector",
                         "danger" if c["my_records"] else "warn" if c["error_records"] else "ok")
                  if c["log_files"] is not None else "")
    progress_kpi = (rh.kpi("🐢 Lag", c["total_lag"], f"{len(c['lag'])} partition(s)", "warn" if c["total_lag"] else "ok") if c["lag"] else "")
    kpis = "".join([
        rh.kpi("🧩 Connector", c["state"], f"{c['type']} · {kind}", "ok" if c["state"] == "RUNNING" else "danger" if c["state"] == "FAILED" else "warn"),
        rh.kpi("⚙️ Tasks", f"{c['running_tasks']}/{len(c['tasks'])}", "RUNNING",
               "danger" if c["failed_tasks"] else "ok" if c["tasks"] and c["running_tasks"] == len(c["tasks"]) else "warn"),
        errors_kpi, progress_kpi,
    ])
    head = (f"<div class='section-title' style='font-size:1.25rem;margin-top:12px'>🩺 {rh.e(c['name'])}"
            + (f" <span class='legend mono'>{rh.e(klass)}</span>" if klass else "") + "</div>") if several else ""
    return (head + f"<div class='verdict {c['verdict'][0]}'>{rh.e(c['verdict'][1])}</div>"
            + f"<div class='kpi-grid'>{kpis}</div>" + rh.findings_html(c["findings"])
            + tasks_html(c) + errors_html(c) + lag_html(c) + next_steps_html(c) + config_html(c))


def html_report(connectors: List[dict]) -> str:
    several = len(connectors) > 1
    first = connectors[0]
    meta = [f"🔗 {rh.e(', '.join(c['name'] for c in connectors))}",
            f"{'☁️ fully managed' if first['is_cloud'] else '🌎 ' + rh.e(first['meta'].get('environment') or 'self-managed')}"]
    if not several:
        klass = (first["config"] or {}).get("connector.class")
        if klass:
            meta.insert(1, f"<span class='mono'>{rh.e(klass)}</span>")
    body = ""
    if several:
        rank = {"danger": 0, "warn": 1, "ok": 2}
        rows = "".join(f"<tr><td class='mono'>{rh.e(c['name'])}</td><td>{rh.e(c['type'])}</td><td>{st(c['state'])}</td>"
                       f"<td>{c['running_tasks']}/{len(c['tasks'])}</td><td>{rh.e(c['verdict'][1])}</td></tr>"
                       for c in sorted(connectors, key=lambda c: rank[c["verdict"][0]]))
        worst = min(connectors, key=lambda c: rank[c["verdict"][0]])["verdict"][0]
        n_bad = sum(1 for c in connectors if c["verdict"][0] != "ok")
        text = f"✅ All {len(connectors)} connectors look healthy." if not n_bad else f"{'🚨' if worst == 'danger' else '⚠️'} {n_bad} of {len(connectors)} connectors need a look."
        body += (f"<div class='verdict {worst}'>{rh.e(text)}</div><div class='table-card'><h2>🧩 Connectors</h2><table><tr><th>Connector</th>"
                 f"<th>Type</th><th>State</th><th>Tasks RUNNING</th><th>Verdict</th></tr>{rows}</table></div>")
    body += "".join(connector_html(c, several) for c in connectors)
    title = ", ".join(c["name"] for c in connectors)
    return rh.page(f"Connector diagnose — {title}", "🩺 Connector Diagnose", meta, body,
                   "🛠️ Generated by playground connector diagnose (self-contained, no external resource). "
                   "A snapshot: run it again to see whether the state, the lag or the offsets move.")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--connector-dir", action="append", required=True, help="folder written by playground connector diagnose")
    ap.add_argument("--html-out", required=True, metavar="PATH", help="write a self-contained HTML report")
    args = ap.parse_args()
    connectors = [assess(load(d)) for d in args.connector_dir]
    with open(args.html_out, "w", encoding="utf-8") as fh:
        fh.write(html_report(connectors))
    return 0


if __name__ == "__main__":
    sys.exit(main())
