#!/usr/bin/env python3
"""
Analysis of a jscissors trace (playground debug jscissors / playground analyze jscissors): what the traced methods did
while the agent was attached. Text digest, --json, and a self-contained HTML report.

Input: the folder copied from the container by playground debug jscissors --action stop, holding one pid-<pid>/ folder
per traced JVM (or one pid-<pid>/ folder, or its events.jsonl). Each holds, written by the agent (tools/jscissors/agent):
  summary.json    rules, settings, classes instrumented, exact statistics per method, limits, errors, dumps
  events.jsonl    one event per line: enter (args, stack), exit (duration, return value, exception), dump
  agent.log       what the agent did
  dumps/          thread dumps (jstack format) and heap dumps taken by the THREADS / HEAP operations

Standard library only, runs with the host python3.
"""

import argparse
import json
import os
import re
import sys
from collections import Counter, defaultdict
from datetime import datetime
from typing import Dict, List, Optional, Tuple

# no __pycache__ left in the repository
sys.dont_write_bytecode = True
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "report-common"))
import report_html as rh  # noqa: E402

# call trees of the HTML report: root calls shown per thread, and calls shown in total
MAX_ROOTS_PER_THREAD = 40
MAX_TREE_NODES = 4000


# ── Loading ──────────────────────────────────────────────────────────────────

def find_pid_dirs(path: str) -> List[str]:
    if os.path.isfile(path):
        path = os.path.dirname(os.path.abspath(path))
    if os.path.isfile(os.path.join(path, "summary.json")) or os.path.isfile(os.path.join(path, "events.jsonl")):
        return [path]
    dirs = []
    for root, _, files in os.walk(path):
        if "summary.json" in files or "events.jsonl" in files:
            dirs.append(root)
    return sorted(dirs)


def read_json(path: str) -> dict:
    try:
        with open(path, encoding="utf-8", errors="replace") as fh:
            return json.load(fh)
    except (OSError, ValueError):
        return {}


def read_events(path: str) -> Tuple[List[dict], int]:
    events, bad = [], 0
    try:
        with open(path, encoding="utf-8", errors="replace") as fh:
            for line in fh:
                line = line.strip()
                if not line:
                    continue
                try:
                    events.append(json.loads(line))
                except ValueError:
                    # the last line of a JVM killed while writing
                    bad += 1
    except OSError:
        pass
    return events, bad


def load(path: str) -> Optional[dict]:
    """The traced JVM with the most calls; the other ones (tools started in the container with the agent) are listed."""
    jvms = []
    for d in find_pid_dirs(path):
        summary = read_json(os.path.join(d, "summary.json"))
        events, bad = read_events(os.path.join(d, "events.jsonl"))
        jvms.append({"dir": d, "summary": summary, "events": events, "bad_lines": bad})
    if not jvms:
        return None
    jvms.sort(key=lambda j: (j["summary"].get("calls", 0), len(j["events"])), reverse=True)
    main = jvms[0]
    main["others"] = [{"dir": j["dir"], "pid": j["summary"].get("pid"), "main": j["summary"].get("main"),
                       "calls": j["summary"].get("calls", 0)} for j in jvms[1:]]
    return main


# ── Analysis ─────────────────────────────────────────────────────────────────

def shown(path: str) -> str:
    """A path as printed in the reports: relative to the current folder when it is under it (a published report must not
    hold the path of a user folder), absolute otherwise"""
    rel = os.path.relpath(path)
    return path if rel.startswith("..") else rel


def short_class(name: str) -> str:
    return (name or "").split(".")[-1]


def method_label(c: dict, full: bool = False) -> str:
    cls = c.get("class") or ""
    return f"{cls if full else short_class(cls)}.{c.get('method', '?')}"


def fmt_us(us: float) -> str:
    if us is None:
        return "-"
    if us < 1000:
        return f"{us:.0f} µs"
    if us < 1000000:
        return f"{us / 1000:.1f} ms"
    return f"{us / 1000000:.2f} s"


def normalize_message(msg: str) -> str:
    return re.sub(r"\d+", "N", msg or "")[:200]


def build_calls(events: List[dict]) -> Tuple[Dict[int, dict], List[dict], int]:
    """calls by id (enter + exit merged), dump events, last timestamp (µs since the start of the session)"""
    calls: Dict[int, dict] = {}
    dumps = []
    last_us = 0
    for ev in events:
        last_us = max(last_us, ev.get("us", 0))
        kind = ev.get("ev")
        if kind == "enter":
            c = calls.setdefault(ev["id"], {})
            c.update(ev)
            c["start_us"] = ev.get("us", 0)
            c["children"] = c.get("children", [])
        elif kind == "exit":
            c = calls.setdefault(ev["id"], {"id": ev["id"], "thread": ev.get("thread"), "children": [], "exit_only": True})
            for k in ("dur_us", "ret", "void", "exc", "exc_msg", "exc_stack", "exc_cause"):
                if k in ev:
                    c[k] = ev[k]
            for k in ("class", "method", "sig"):
                if k in ev and k not in c:
                    c[k] = ev[k]
            if "start_us" not in c:
                c["start_us"] = ev.get("us", 0) - ev.get("dur_us", 0)
                c["ts"] = ev.get("ts", 0) - ev.get("dur_us", 0) // 1000
        elif kind == "dump":
            dumps.append(ev)
    for c in calls.values():
        if "dur_us" not in c:
            # still running when the session stopped (or when the JVM exited)
            c["open"] = True
            c["dur_us"] = max(0, last_us - c.get("start_us", 0))
    for c in calls.values():
        parent = calls.get(c.get("parent") or 0)
        if parent is not None and parent is not c:
            parent["children"].append(c)
    for c in calls.values():
        c["children"].sort(key=lambda x: x.get("start_us", 0))
        c["self_us"] = max(0, c["dur_us"] - sum(ch["dur_us"] for ch in c["children"]))
    return calls, dumps, last_us


def percentile(values: List[float], p: float) -> Optional[float]:
    if not values:
        return None
    values = sorted(values)
    return values[min(len(values) - 1, int(round(p * (len(values) - 1))))]


def analyze(jvm: dict, top: int) -> dict:
    s = jvm["summary"]
    calls, dumps, last_us = build_calls(jvm["events"])
    recorded = [c for c in calls.values() if not c.get("exit_only")]

    # per method: exact counts from summary.json, distribution and self time from the recorded calls
    by_method = defaultdict(list)
    for c in recorded:
        by_method[(c.get("class"), c.get("method"), c.get("sig"))].append(c)
    methods = []
    for m in s.get("methods", []):
        key = (m.get("class"), m.get("method"), m.get("sig"))
        rec = by_method.get(key, [])
        durations = [c["dur_us"] for c in rec if not c.get("open")]
        methods.append({
            "class": m.get("class"), "method": m.get("method"), "sig": m.get("sig"),
            "calls": m.get("calls", 0), "errors": m.get("errors", 0), "total_us": m.get("total_us", 0),
            "avg_us": m.get("total_us", 0) / m["calls"] if m.get("calls") else 0, "max_us": m.get("max_us", 0),
            "p95_us": percentile(durations, 0.95), "self_us": sum(c["self_us"] for c in rec if not c.get("open")),
            "recorded": len(rec), "exceptions": m.get("exceptions", {}),
        })
    if not methods and recorded:
        # summary.json missing (JVM killed before its first refresh): from the events only
        for key, rec in by_method.items():
            durations = [c["dur_us"] for c in rec]
            methods.append({"class": key[0], "method": key[1], "sig": key[2], "calls": len(rec),
                            "errors": sum(1 for c in rec if c.get("exc")), "total_us": sum(durations),
                            "avg_us": sum(durations) / len(rec), "max_us": max(durations), "p95_us": percentile(durations, 0.95),
                            "self_us": sum(c["self_us"] for c in rec), "recorded": len(rec), "exceptions": {}})
    methods.sort(key=lambda m: m["total_us"], reverse=True)

    # exceptions: grouped by method, exception and message (digits ignored)
    groups: Dict[tuple, dict] = {}
    for c in calls.values():
        if not c.get("exc"):
            continue
        key = (method_label(c, True), c["exc"], normalize_message(c.get("exc_msg")))
        g = groups.setdefault(key, {"method": key[0], "exception": c["exc"], "message": c.get("exc_msg", ""), "count": 0,
                                    "first_ts": c.get("ts"), "last_ts": c.get("ts"), "stack": None, "cause": None, "call": c})
        g["count"] += 1
        g["last_ts"] = c.get("ts") or g["last_ts"]
        if c.get("exc_stack") and not g["stack"]:
            g["stack"] = c["exc_stack"]
            g["cause"] = c.get("exc_cause")
    # exact number of exceptions of that class thrown by that method (the recorded calls are only a part of them)
    exact = {(f"{m['class']}.{m['method']}", exc): n for m in methods for exc, n in (m.get("exceptions") or {}).items()}
    per_class = Counter((g["method"], g["exception"]) for g in groups.values())
    for g in groups.values():
        n = exact.get((g["method"], g["exception"]))
        # split between the messages of the same class in proportion is not possible: exact only with one message
        g["total"] = n if n and per_class[(g["method"], g["exception"])] == 1 else g["count"]
    exceptions = sorted(groups.values(), key=lambda g: g["total"], reverse=True)

    open_calls = sorted([c for c in calls.values() if c.get("open")], key=lambda c: c["dur_us"], reverse=True)
    slowest = sorted([c for c in recorded if not c.get("open")], key=lambda c: c["dur_us"], reverse=True)[:top]
    threads = Counter(c.get("thread") for c in recorded)
    roots = defaultdict(list)
    for c in recorded:
        if not calls.get(c.get("parent") or 0):
            roots[c.get("thread")].append(c)
    for t in roots:
        roots[t].sort(key=lambda c: c.get("start_us", 0))

    started = s.get("started") or (min((c.get("ts", 0) for c in recorded), default=0))
    ended = s.get("stopped") or s.get("updated") or (started + last_us // 1000)
    duration_s = max(0.0, (ended - started) / 1000) if started and ended else last_us / 1e6
    total_calls = s.get("calls", len(recorded))
    a = {
        "dir": jvm["dir"], "summary": s, "others": jvm.get("others", []), "bad_lines": jvm.get("bad_lines", 0),
        "duration_s": duration_s, "calls_total": total_calls, "calls_recorded": len(recorded),
        "errors_total": sum(m["errors"] for m in methods), "methods": methods, "exceptions": exceptions,
        "open_calls": open_calls, "slowest": slowest, "threads": threads, "roots": roots, "calls": calls, "dumps": dumps,
        "rate": total_calls / duration_s if duration_s > 0 else 0,
    }
    a["findings"] = findings(a)
    a["verdict"] = verdict(a)
    return a


def findings(a: dict) -> List[dict]:
    s = a["summary"]
    res = []
    rules = s.get("rules", [])
    instrumented = s.get("instrumented", [])
    if not rules:
        res.append({"severity": "HIGH", "text": "📜 No rule was loaded: check --class / --method (agent.log lists the lines ignored)"})
    elif not instrumented:
        res.append({"severity": "HIGH", "text": "🔍 No class matched the rules: the class name is wrong (it is an exact name unless it has "
                                                "regex characters, like io.confluent.connect.jdbc.*), the class is not loaded yet (it "
                                                "is instrumented when it loads, start the connector after the agent), or it is a JDK "
                                                "class (java.*, javax.*: not supported)"})
    elif not a["calls_total"]:
        res.append({"severity": "MEDIUM", "text": f"💤 {len(instrumented)} class(es) instrumented but no traced method was called: the "
                                                  "--method pattern matches nothing that ran (interfaces and abstract methods are never "
                                                  "traced: trace the implementation class), or the code path was not exercised"})
    for name in s.get("not_visible", [])[:3]:
        res.append({"severity": "MEDIUM", "text": f"🙈 {name} matches a rule, but its class loader cannot see the agent: not traced"})
    for err in s.get("errors", [])[:3]:
        res.append({"severity": "MEDIUM", "text": f"🧨 Agent error: {err[:300]}"})
    for w in s.get("warnings", []):
        res.append({"severity": "LOW", "text": f"📜 {w}"})
    long_open = [c for c in a["open_calls"] if c["dur_us"] >= 5000000]
    if long_open:
        c = long_open[0]
        res.append({"severity": "HIGH", "text": f"⏳ {len(a['open_calls'])} call(s) still running when the trace stopped, the longest "
                                                f"{method_label(c)} on thread {c.get('thread')} for {fmt_us(c['dur_us'])}: a hang or a "
                                                "long blocking call; take a thread dump (playground debug thread-dump) to see where it waits"})
    elif a["open_calls"]:
        res.append({"severity": "INFO", "text": f"⏳ {len(a['open_calls'])} call(s) were still running when the trace stopped"})
    for g in a["exceptions"][:3]:
        res.append({"severity": "MEDIUM", "text": f"💥 {g['total']} call(s) of {short_class(g['method'].rsplit('.', 1)[0])}."
                                                  f"{g['method'].rsplit('.', 1)[-1]} threw {g['exception']}: {g['message'][:200]}"
                                                  + (f" (cause {g['cause'][:150]})" if g.get("cause") else "")})
    if a["slowest"] and a["slowest"][0]["dur_us"] >= 1000000:
        c = a["slowest"][0]
        res.append({"severity": "INFO", "text": f"🐢 Slowest call: {method_label(c)} took {fmt_us(c['dur_us'])} on thread {c.get('thread')}"})
    settings = s.get("settings", {})
    if settings.get("onlyFailed") or settings.get("slowerThanMs"):
        what = " or ".join(x for x in ["threw an exception" if settings.get("onlyFailed") else "",
                                        f"took {settings['slowerThanMs']} ms or more" if settings.get("slowerThanMs") else ""] if x)
        res.append({"severity": "INFO", "text": f"🎯 Only the calls that {what} were recorded with their details (--only-failed / "
                                                f"--slower-than): {a['calls_recorded']:,} of {a['calls_total']:,}. The statistics "
                                                "count every call; a recorded call whose caller was not recorded shows as a root of "
                                                "the call trees"})
    if s.get("events_dropped"):
        res.append({"severity": "MEDIUM", "text": f"🚰 {s['events_dropped']} event(s) dropped (the traced threads produced them faster than "
                                                  "they could be written): narrow --class / --method"})
    if s.get("limit_reached_at"):
        res.append({"severity": "INFO", "text": f"✂️ maxCalls ({s.get('settings', {}).get('maxCalls')}) reached: the next calls are only "
                                                "counted in the statistics (--max-calls to record more)"})
    if s.get("calls_capped_per_method"):
        res.append({"severity": "INFO", "text": f"✂️ {s['calls_capped_per_method']} call(s) past maxCallsPerMethod "
                                                f"({s.get('settings', {}).get('maxCallsPerMethod')}) are only counted in the statistics "
                                                "(--max-calls-per-method to record more)"})
    if a["rate"] > 5000:
        res.append({"severity": "LOW", "text": f"🔥 {a['rate']:,.0f} traced calls per second: tracing that many calls slows the JVM down, "
                                               "narrow --class / --method"})
    written = [d for d in a["dumps"] if d.get("file")]
    if len(written) > 3:
        res.append({"severity": "INFO", "text": f"📸 {len(written)} dumps in {shown(os.path.join(a['dir'], 'dumps'))}, the first ones below"})
    for d in written[:3]:
        if d.get("file", "").endswith(".txt"):
            res.append({"severity": "INFO", "text": f"🧵 Thread dump at the {d.get('when')} of {d.get('origin')}: playground analyze "
                                                    f"thread-dump -f {shown(os.path.join(a['dir'], d['file']))}"})
        elif d.get("file"):
            res.append({"severity": "INFO", "text": f"💾 Heap dump at the {d.get('when')} of {d.get('origin')}: playground analyze "
                                                    f"heap-dump -f {shown(os.path.join(a['dir'], d['file']))}"})
    if s.get("dumps_skipped"):
        res.append({"severity": "INFO", "text": f"📸 {s['dumps_skipped']} dump(s) skipped by the limits (maxThreadDumps, maxHeapDumps, "
                                                "dumpIntervalMs)"})
    if a["others"]:
        res.append({"severity": "INFO", "text": f"🧮 {len(a['others'])} other JVM(s) loaded the agent ("
                                                + ", ".join(f"pid {o['pid']} {o['main'] or ''} {o['calls']} calls" for o in a["others"][:3])
                                                + "): only the one with the most calls is analyzed"})
    return rh.sort_findings(res)


def verdict(a: dict) -> Tuple[str, str]:
    if not a["summary"].get("instrumented") and not a["calls_total"]:
        return "danger", "🔍 Nothing was traced: no class matched the rules."
    if not a["calls_total"]:
        return "warn", "💤 Classes instrumented, but no traced method was called during the trace."
    parts = [f"✂️ {a['calls_total']:,} call(s) of {len(a['methods'])} method(s) in {a['duration_s']:.0f}s"]
    if a["errors_total"]:
        parts.append(f"{a['errors_total']:,} threw an exception")
    if a["methods"]:
        m = a["methods"][0]
        parts.append(f"most time in {short_class(m['class'])}.{m['method']} ({fmt_us(m['total_us'])})")
    cls = "danger" if any(c["dur_us"] >= 5000000 for c in a["open_calls"]) else "warn" if a["errors_total"] else "ok"
    return cls, ", ".join(parts) + "."


# ── Text digest ──────────────────────────────────────────────────────────────

def text_report(a: dict, top: int) -> str:
    s = a["summary"]
    out = [f"✂️  jscissors trace of pid {s.get('pid', '?')} {s.get('main') or ''} ({s.get('jvm', '?')}), {s.get('mode', '')}",
           f"   {shown(a['dir'])}",
           f"   {a['duration_s']:.0f}s, {len(s.get('rules', []))} rule(s), {len(s.get('instrumented', []))} class(es) instrumented, "
           f"{a['calls_total']:,} call(s) ({a['calls_recorded']:,} with details), {a['errors_total']:,} exception(s)",
           "", a["verdict"][1], ""]
    if a["methods"]:
        out.append("⏱️  Methods, by total time")
        out.append(f"   {'calls':>9} {'total':>10} {'avg':>10} {'p95':>10} {'max':>10} {'errors':>7}  method")
        for m in a["methods"][:top]:
            out.append(f"   {m['calls']:>9,} {fmt_us(m['total_us']):>10} {fmt_us(m['avg_us']):>10} {fmt_us(m['p95_us']):>10} "
                       f"{fmt_us(m['max_us']):>10} {m['errors']:>7}  {short_class(m['class'])}.{m['method']}{m['sig']}")
        out.append("")
    if a["exceptions"]:
        out.append("💥 Exceptions")
        for g in a["exceptions"][:top]:
            out.append(f"   {g['total']:>6}  {g['method']} → {g['exception']}: {g['message'][:150]}")
        out.append("")
    if a["open_calls"]:
        out.append("⏳ Still running when the trace stopped")
        for c in a["open_calls"][:top]:
            out.append(f"   {fmt_us(c['dur_us']):>10}  {method_label(c)} on {c.get('thread')}")
        out.append("")
    if a["slowest"]:
        out.append("🐢 Slowest calls")
        for c in a["slowest"][:min(top, 5)]:
            args = ", ".join(c.get("args", [])) if "args" in c else ""
            ret = f" → {c['ret']}" if "ret" in c else f" ✖ {c['exc']}" if c.get("exc") else ""
            out.append(f"   {fmt_us(c['dur_us']):>10}  {method_label(c)}({args[:120]}){ret[:120]} on {c.get('thread')}")
        out.append("")
    if a["findings"]:
        out.append("🔎 Findings")
        for f in a["findings"]:
            out.append(f"   {rh.SEVERITY_ICONS.get(f['severity'], '')} {f['severity']}: {f['text']}")
    return "\n".join(out)


def json_report(a: dict, top: int) -> dict:
    def call_json(c: dict) -> dict:
        return {k: c[k] for k in ("id", "thread", "class", "method", "sig", "args", "ret", "exc", "exc_msg", "dur_us", "ts", "open")
                if k in c}
    s = a["summary"]
    return {
        "dir": a["dir"], "pid": s.get("pid"), "main": s.get("main"), "jvm": s.get("jvm"), "mode": s.get("mode"),
        "duration_s": round(a["duration_s"], 1), "rules": s.get("rules", []), "instrumented": s.get("instrumented", []),
        "calls": a["calls_total"], "calls_recorded": a["calls_recorded"], "exceptions_total": a["errors_total"],
        "verdict": a["verdict"][1], "methods": a["methods"][:top],
        "exceptions": [{k: g[k] for k in ("method", "exception", "message", "total", "cause", "stack")} for g in a["exceptions"][:top]],
        "still_running": [call_json(c) for c in a["open_calls"][:top]], "slowest": [call_json(c) for c in a["slowest"]],
        "dumps": [d.get("file") for d in a["dumps"] if d.get("file")], "findings": a["findings"],
    }


# ── HTML ─────────────────────────────────────────────────────────────────────

TREE_CSS = """<style>
.tree details{border:0;padding:0;margin-left:18px}
.tree>details{margin-left:0;border-top:1px solid #f1f5f9;padding:2px 0}
.tree summary{font-family:'SFMono-Regular',Consolas,Menlo,monospace;font-size:.76rem;font-weight:normal;padding:2px 0;list-style-position:outside}
.tree .leaf{margin-left:18px;font-family:'SFMono-Regular',Consolas,Menlo,monospace;font-size:.76rem;padding:2px 0 2px 14px}
.tree .dur{display:inline-block;min-width:74px;text-align:right;color:#475569;margin-right:8px}
.tree .slow{color:#c2410c;font-weight:700}.tree .exc{color:#dc2626}.tree .ret{color:#15803d}.tree .args{color:#1d4ed8}
.tree .thr{color:#94a3b8}
.callinfo{margin:4px 0 6px 18px}
.tree.flat .leaf{margin-left:0;border-top:1px solid #f1f5f9}.tree.flat>details{margin-left:0}
""" + rh.dark("""
.tree>details,.tree.flat .leaf{border-top-color:#334155}
.tree .dur{color:#94a3b8}
.tree .slow{color:#fdba74}.tree .exc{color:#f87171}.tree .ret{color:#4ade80}.tree .args{color:#93c5fd}
""") + "</style>"


def call_line(c: dict, slow_us: float) -> str:
    dur = f"<span class='dur{' slow' if c['dur_us'] >= slow_us else ''}'>{rh.e(fmt_us(c['dur_us']))}</span>"
    args = f"<span class='args'>({rh.e(', '.join(c['args'])[:300])})</span>" if "args" in c else rh.e(c.get("sig", ""))
    tail = ""
    if c.get("exc"):
        tail = f" <span class='exc'>✖ {rh.e(c['exc'])}: {rh.e((c.get('exc_msg') or '')[:200])}</span>"
    elif "ret" in c:
        tail = f" <span class='ret'>→ {rh.e(c['ret'][:200])}</span>"
    if c.get("open"):
        tail += " " + rh.badge("still running", "warn")
    return f"{dur}<b>{rh.e(method_label(c))}</b>{args}{tail}"


def call_details(c: dict) -> str:
    rows = []
    if c.get("stack"):
        rows.append("<pre>" + rh.e("\n".join(c["stack"])) + "</pre>")
    if c.get("exc_stack"):
        rows.append(f"<pre>{rh.e(c['exc'])}: {rh.e(c.get('exc_msg') or '')}\n" + rh.e("\n".join("\tat " + f for f in c["exc_stack"]))
                    + (f"\nCaused by: {rh.e(c['exc_cause'])}" if c.get("exc_cause") else "") + "</pre>")
    return f"<div class='callinfo'>{''.join(rows)}</div>" if rows else ""


def flat_call_html(c: dict, slow_us: float) -> str:
    info = call_details(c)
    if not info:
        return f"<div class='leaf'>{call_line(c, slow_us)} <span class='thr'>{rh.e(c.get('thread', ''))}</span></div>"
    return f"<details><summary>{call_line(c, slow_us)} <span class='thr'>{rh.e(c.get('thread', ''))}</span></summary>{info}</details>"


def tree_html(c: dict, budget: List[int], slow_us: float) -> str:
    budget[0] -= 1
    info = call_details(c)
    if not c["children"] and not info:
        return f"<div class='leaf'>{call_line(c, slow_us)}</div>"
    inner = info
    for ch in c["children"]:
        if budget[0] <= 0:
            inner += "<div class='leaf muted'>… (more calls in events.jsonl)</div>"
            break
        inner += tree_html(ch, budget, slow_us)
    return f"<details><summary>{call_line(c, slow_us)}</summary>{inner}</details>"


def file_item(path: str, label: str, html_dir: str) -> str:
    """linked relative to the report when the file is next to it or below (the trace folder of debug jscissors), so that
    the folder can be moved or zipped; only named otherwise"""
    rel = os.path.relpath(path, html_dir)
    if rel.startswith(".."):
        return f"<li><code>{rh.e(label)}</code></li>"
    return f"<li><a href='{rh.e(rel)}'>{rh.e(label)}</a></li>"


def html_report(a: dict, top: int, html_dir: str) -> str:
    s = a["summary"]
    instrumented = s.get("instrumented", [])
    kpis = rh.kpis_html([
        rh.kpi("⏱️ Trace", f"{a['duration_s']:.0f}s", s.get("mode", "")),
        rh.kpi("📞 Calls", f"{a['calls_total']:,}", f"{a['calls_recorded']:,} with details, {a['rate']:,.0f}/s"),
        rh.kpi("🧩 Methods", len(a["methods"]), f"{len(instrumented)} class(es) instrumented", "danger" if not instrumented else ""),
        rh.kpi("💥 Exceptions", f"{a['errors_total']:,}", f"{len(a['exceptions'])} kind(s)", "warn" if a["errors_total"] else "ok"),
        rh.kpi("⏳ Still running", len(a["open_calls"]), "when the trace stopped",
               "danger" if any(c["dur_us"] >= 5000000 for c in a["open_calls"]) else "ok" if not a["open_calls"] else "warn"),
        rh.kpi("🧵 Threads", len(a["threads"]), ", ".join(t for t, _ in a["threads"].most_common(2))[:60] or "-"),
    ])
    points = []
    for c in a["calls"].values():
        if c.get("ts") and not c.get("exit_only"):
            points.append((datetime.fromtimestamp(c["ts"] / 1000), "calls"))
        if c.get("exc") and c.get("ts"):
            points.append((datetime.fromtimestamp(c["ts"] / 1000), "exceptions"))
    tl = rh.time_bins(points, ("calls", "exceptions"))
    bars = [(f"{short_class(m['class'])}.{m['method']}", m["total_us"] / 1000, f"{m['calls']:,} calls, {fmt_us(m['total_us'])} in total")
            for m in a["methods"][:12] if m["total_us"]]
    charts = rh.charts_grid([
        ("📈 Calls recorded with details, and exceptions", rh.svg_time_columns(tl, [("calls", "calls", rh.SERIES_1), ("exceptions", "exceptions", rh.SERIES_2)]) if tl else ""),
        ("⏱️ Total time by method (ms)", rh.svg_hbars(bars, lambda v: f"{v:,.1f} ms")),
    ])
    body = [TREE_CSS, rh.verdict_html(*a["verdict"]), kpis, rh.findings_html(a["findings"]), charts]

    if a["methods"]:
        rows = [[f"<span class='mono'>{rh.e(short_class(m['class']))}.<b>{rh.e(m['method'])}</b>{rh.e(m['sig'])}</span>"
                 f"<div class='legend'>{rh.e(m['class'])}</div>",
                 f"{m['calls']:,}", rh.e(fmt_us(m["total_us"])), rh.e(fmt_us(m["avg_us"])), rh.e(fmt_us(m["p95_us"])),
                 rh.e(fmt_us(m["max_us"])), rh.e(fmt_us(m["self_us"])) if m["recorded"] else "-",
                 (rh.badge(f"{m['errors']:,}", "error") if m["errors"] else "0")]
                for m in a["methods"]]
        body.append(rh.card("⏱️ Methods, by total time", rh.table(
            ["Method", "Calls", "Total", "Avg", "p95", "Max", "Self", "Exceptions"], rows, num=(1, 2, 3, 4, 5, 6, 7))
            + "<p class='legend'>Calls, total, average, max and exceptions are exact (counted by the agent for every call). p95 and "
              "self time (time not spent in a traced callee) come from the calls recorded with details.</p>"))

    if a["exceptions"]:
        items = []
        for i, g in enumerate(a["exceptions"][:top]):
            stack = ""
            if g.get("stack"):
                stack = "<pre>" + rh.e(f"{g['exception']}: {g['message']}\n" + "\n".join("\tat " + f for f in g["stack"])) \
                        + (f"\nCaused by: {rh.e(g['cause'])}" if g.get("cause") else "") + "</pre>"
            c = g["call"]
            args = f"<div class='legend'>arguments of one call: <span class='mono'>{rh.e(', '.join(c['args'])[:400])}</span></div>" if "args" in c else ""
            items.append(f"<details{' open' if i == 0 else ''}><summary>{rh.badge('×' + str(g['total']), 'error')} "
                         f"<span class='mono'>{rh.e(g['method'])} → {rh.e(g['exception'])}: {rh.e(g['message'][:200])}</span></summary>"
                         f"{args}{stack}</details>")
        body.append(rh.card("💥 Exceptions thrown by the traced methods", "".join(items)))

    if a["open_calls"]:
        rows = [[rh.e(fmt_us(c["dur_us"])), f"<span class='mono'>{rh.e(method_label(c, True))}</span>", rh.e(c.get("thread", "")),
                 f"<span class='mono'>{rh.e(', '.join(c.get('args', []))[:300])}</span>"] for c in a["open_calls"][:top]]
        body.append(rh.card("⏳ Calls still running when the trace stopped", rh.table(["Running for", "Method", "Thread", "Arguments"], rows, num=(0,))))

    if a["slowest"]:
        slow_us = a["slowest"][min(len(a["slowest"]) - 1, 4)]["dur_us"]
        body.append(rh.card(f"🐢 Slowest calls ({len(a['slowest'])})", "<div class='tree flat'>" + "".join(
            flat_call_html(c, slow_us) for c in a["slowest"]) + "</div>"
            + "<p class='legend'>Their callees are in the call trees below.</p>"))

    if a["roots"]:
        all_durs = sorted(c["dur_us"] for c in a["calls"].values())
        slow_us = percentile(all_durs, 0.95) or 0
        budget = [MAX_TREE_NODES]
        sections = []
        for thread, _ in a["threads"].most_common():
            roots = a["roots"].get(thread, [])
            if not roots or budget[0] <= 0:
                continue
            inner = "".join(tree_html(c, budget, slow_us) for c in roots[:MAX_ROOTS_PER_THREAD] if budget[0] > 0)
            more = len(roots) - MAX_ROOTS_PER_THREAD
            if more > 0:
                inner += f"<div class='leaf muted'>… {more} more root call(s) on this thread in events.jsonl</div>"
            sections.append(f"<details{' open' if not sections else ''}><summary>{rh.badge(str(len(roots)) + ' root call(s)', 'mine')} "
                            f"<span class='mono'>{rh.e(thread)}</span></summary><div class='tree'>{inner}</div></details>")
        body.append(rh.card("🌳 Call trees, by thread", "".join(sections)
                            + "<p class='legend'>Only the traced methods appear: a child is a traced call made (directly or not) "
                              "by its parent. Durations in orange are above the 95th percentile.</p>"))

    rules = "".join(f"<li><code>{rh.e(r)}</code></li>" for r in s.get("rules", []))
    settings = ", ".join(f"{k}={v}" for k, v in s.get("settings", {}).items())
    classes = "<br>".join(f"<span class='mono'>{rh.e(c)}</span>" for c in sorted(instrumented)[:500])
    files = ["events.jsonl", "summary.json", "agent.log", "instrumented.txt"] + [d["file"] for d in a["dumps"] if d.get("file")]
    body.append(rh.card("📜 Rules and files", f"<ul style='margin-left:18px'>{rules}</ul><p class='legend'>{rh.e(settings)}</p>"
                        f"<details><summary>{len(instrumented)} class(es) instrumented</summary>{classes}</details>"
                        "<h3>Files</h3><ul style='margin-left:18px'>"
                        + "".join(file_item(os.path.join(a["dir"], f), f, html_dir) for f in files
                                  if os.path.exists(os.path.join(a["dir"], f))) + "</ul>"))

    meta = [f"✂️ pid {rh.e(s.get('pid', '?'))} {rh.e(s.get('main') or '')}", rh.e(s.get("jvm", "")),
            f"agent {rh.e(s.get('version', '?'))}, {rh.e(s.get('mode', ''))}"]
    if s.get("started"):
        meta.append("from " + datetime.fromtimestamp(s["started"] / 1000).strftime("%Y-%m-%d %H:%M:%S"))
    return rh.page("jscissors trace", "✂️ jscissors trace", meta, "".join(body),
                   "🛠️ Generated by playground analyze jscissors (self-contained, no external resource). Values are cut to "
                   "maxValueLength and the secrets found in them are masked, but check the report before sharing it.")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--dir", required=True, help="folder copied by playground debug jscissors, a pid-<pid> folder or its events.jsonl")
    ap.add_argument("--top", type=int, default=15)
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--html-out")
    args = ap.parse_args()
    jvm = load(args.dir)
    if jvm is None or (not jvm["summary"] and not jvm["events"]):
        print(f"❌ no jscissors trace (summary.json, events.jsonl) in {args.dir}", file=sys.stderr)
        return 2
    a = analyze(jvm, args.top)
    if args.json:
        print(json.dumps(json_report(a, args.top), indent=2, default=str))
        return 0
    print(text_report(a, args.top))
    if args.html_out:
        with open(args.html_out, "w", encoding="utf-8") as fh:
            fh.write(html_report(a, args.top, os.path.dirname(os.path.abspath(args.html_out))))
    return 0


if __name__ == "__main__":
    sys.exit(main())
