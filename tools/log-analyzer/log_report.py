#!/usr/bin/env python3
"""
HTML report and JSON of the ERROR/FATAL (and WARN) digest of log files, written by playground analyze logs.

The records come from summarize_log_errors (scripts/cli/src/lib/cli_function.sh), the same parser as
playground container logs --errors, run with PG_LOG_DIGEST_RECORDS_FILE set:

  @@PGFILE@@<tab>label<tab>lines<tab>distinct records<tab>occurrences
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
from collections import OrderedDict
from datetime import datetime
from typing import Dict, List, Optional, Tuple

# no __pycache__ left in the repository
sys.dont_write_bytecode = True
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "report-common"))
from report_html import (SERIES_1, SERIES_2, SEVERITY_ORDER, badge, card, charts_grid, e, findings_html, log_html,  # noqa: E402
                         kpi, kpis_html, page, svg_hbars, svg_time_columns, time_bins, verdict_html)
import known_causes  # noqa: E402
import log_viewer  # noqa: E402
from known_causes import KILLED_TASK_TITLE  # noqa: E402

LEVEL_ORDER = {"FATAL": 0, "ERROR": 1, "WARN": 2}

# well-known causes: (regex on the record, severity, title, what to do), shared with the CFK analyzer
# (tools/report-common/known_causes.py)
HINTS = known_causes.hints()

EXCEPTION_RE = re.compile(r"^(?:Caused by:\s*)?((?:[a-zA-Z_$][\w$]*\.)+[A-Z][\w$]*(?:Exception|Error|Throwable))(?::\s*(.*))?$")
# connector of a record: the [connector|task-0] / [connector|worker] MDC context of Connect, with an optional scope
# ([connector|task-0|offsets], Oracle CDC [connector|task-0|redoLog]), or the id of the task
CONNECTOR_RE = re.compile(r"\[([^\s|\]]+)\|(?:task-\d+|worker)(?:\|[^\s|\]]+)?\]|Worker(?:Source|Sink)Task\{id=(\S+)-\d+\}")


def parse_records(path: str) -> List[dict]:
    """Files of a records file, each with its records, in the order they were written."""
    files: List[dict] = []
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
                current = {"label": parts[1], "lines": int(parts[2]), "distinct": int(parts[3]),
                           "occurrences": int(parts[4]), "records": [], "configs": []}
                files.append(current)
                rec = done = None
            elif line.startswith("@@PGREC@@\t") and current is not None:
                parts = line.split("\t")
                rec = {"level": parts[1], "count": int(parts[2]), "first_line": int(parts[3]), "last_line": int(parts[4]),
                       "first_ts": parts[5] or None, "last_ts": parts[6] or None, "lines": [], "timestamps": []}
                current["records"].append(rec)
                done = None
            elif line.startswith("@@PGTS@@\t") and rec is not None:
                rec["timestamps"] = line.split("\t", 1)[1].split()
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
        m = re.search(r"((?:[a-z_$][\w$]*\.)+[A-Z][\w$]*(?:Exception|Error|Throwable))", rec["message"])
        if m:
            rec["root_cause"] = m.group(1)


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
                "advice": advice, "text": f"{title}: {occurrences} occurrence(s) {where}: {advice}"}
        if title == KILLED_TASK_TITLE:
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
    # journalctl prefix: "Oct 06 07:35:50 host connect-distributed[1080]: "
    m = re.sub(r"^[A-Z][a-z]{2} [ \d]\d \d\d:\d\d:\d\d \S+ [^\s:]+: ", "", message)
    m = re.sub(r"^\[?\d{4}-\d{2}-\d{2}[ T][\d:,.]*\]?\s*", "", m)
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
                                    "connectors": OrderedDict(), "example": r["root_cause_message"] or short_message(r["message"]), "level": r["level"]})
        c["occurrences"] += r["count"]
        c["records"] += 1
        c["files"][f["label"]] = True
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
    return {"files_scanned": len(files), "files_with_findings": sum(1 for f in files if f["records"]),
            "lines": sum(f["lines"] for f in files), "distinct": sum(f["distinct"] for f in files),
            "occurrences": sum(f["occurrences"] for f in files), "by_level": by_level,
            "by_connector": dict(sorted(by_connector.items(), key=lambda kv: (-kv[1], kv[0]))),
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


def drop_alternating_changes(config: dict, window: int = 60) -> None:
    """Two configs logged with the same identity (two consumers with one client.id) look like a value going back and
    forth: a change undone within `window` seconds (or 500 lines without timestamps) is not a restart with another
    config, both are dropped"""
    changes = config.get("changes") or []

    def seconds(ch):
        try:
            return datetime.strptime(ch["time"], "%Y-%m-%dT%H:%M:%S").timestamp() if ch.get("time") else None
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


def analyze(files: List[dict], unit: str = "file") -> dict:
    """unit: what a label is (file, container, script), for the texts of the findings"""
    shorten_labels(files)
    hints = match_hints(files, unit)
    causes = root_causes(files)
    # the "<Class>Config values:" dumps of the logs and the config files of the input (.properties, connector JSON)
    configuration = [dict({k: v for k, v in c.items() if k != "lines"}, file=f["label"], text="\n".join(c["lines"]))
                     for f in files for c in f.get("configs", []) if c["lines"]]
    for c in configuration:
        drop_alternating_changes(c)
    for f in files:
        f.pop("configs", None)
    return {"summary": summary(files), "findings": findings(files, hints, causes, unit=unit), "known_causes": hints,
            "root_causes": causes, "files": [f for f in files if f["records"]],
            "files_without_findings": [f["label"] for f in files if not f["records"]],
            "configuration": configuration}


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
            for d in h.get("details", [])[:5]:
                out.append(f"      {d}")
    explained = [re.compile(p) for p, _, _, _ in HINTS]
    others = [c for c in res["root_causes"] if not any(rx.search(c["label"] + " " + c["example"]) for rx in explained)]
    if others:
        out.append("🌳 Root causes not explained by a known cause" + (f" (top {top} of {len(others)})" if len(others) > top else ""))
        for c in others[:top]:
            what = f"{c['root_cause'].split('.')[-1]}: {c['example']}" if c["root_cause"] else c["example"]
            who = f" · {len(c['connectors'])} connector(s): {first_names(c['connectors'])}" if c["connectors"] else ""
            out.append(f"   {c['level']} ×{c['occurrences']} {what[:220]}{who}")
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


NO_CONNECTOR = "-"


def connectors_attr(names: List[str], none: bool = False) -> str:
    """data-connectors of a record or a root cause, for the connector filter: names (no space in them), "-" for none"""
    return " data-connectors='" + e(" ".join(list(names) + ([NO_CONNECTOR] if none or not names else []))) + "'"


def records_html(records: List[dict], open_first: int = 3, highlight: Optional[str] = None,
                 viewers: Optional[Dict[str, str]] = None, label: str = "") -> str:
    """One collapsible block per distinct record; highlight: name that marks the records mentioning it; viewers: label ->
    page of the file (log_viewer), its line numbers link to it."""
    viewers = viewers or {}
    out = []
    for i, r in enumerate(records):
        when = (log_viewer.link(viewers, label, f"line {r['first_line']}", r["first_line"])
                + e(f" ({r['first_ts'].replace('T', ' ')})" if r["first_ts"] else ""))
        if r["count"] > 1:
            when += (" → " + log_viewer.link(viewers, label, f"line {r['last_line']}", r["last_line"])
                     + e(f" ({r['last_ts'].replace('T', ' ')})" if r["last_ts"] else ""))
        mine = " <span class='st mine'>this connector</span>" if highlight and highlight in r["text"] else ""
        msg = short_message(r["message"])
        conn = f"<span class='legend mono'>[{e(r['connector'])}]</span> " if r.get("connector") else ""
        out.append(f"<details data-level='{e(r['level'])}'{connectors_attr([r['connector']] if r.get('connector') else [])}"
                   f"{' open' if i < open_first else ''}><summary>{level_badge(r['level'])} ×{r['count']}{mine} "
                   f"{conn}<span class='mono'>{e(msg[:180])}</span> <span class='legend'>· {when}</span></summary>"
                   f"<pre>{log_html(r['text'])}</pre>"
                   + (f"<details><summary>📋 Show context</summary><pre>{log_html(r['context'])}</pre></details>" if r.get("context") else "")
                   + "</details>")
    return "".join(out)


# filter bar of the log report: hides the root causes and the records of the levels switched off, and of the
# connectors not selected (the [connector|task-0] MDC context of the records)
FILTER_CSS = ("<style>.lvl-filter{position:sticky;top:0;z-index:5;display:flex;flex-wrap:wrap;align-items:center;gap:6px;"
              "padding:8px 12px;margin-bottom:14px;border-radius:8px;background:#fff;box-shadow:0 1px 3px rgba(0,0,0,.08);"
              "font-size:.78rem;color:#475569}.lvl-chip{border:0;cursor:pointer;font-family:inherit;font-size:.75rem}"
              ".lvl-chip[aria-pressed=false]{opacity:.35;text-decoration:line-through}[data-level][hidden]{display:none}"
              ".conn-filter{font-family:inherit;font-size:.75rem;max-width:420px;padding:2px 4px;border-radius:6px}"
              ".lvl-filter .sep{margin-left:10px}"
              ".file-records[hidden]{display:none}html[data-theme=dark] .lvl-filter{background:#1e293b;color:#94a3b8}</style>")
FILTER_SCRIPT = """<script>
function pgApplyFilters() {
  const off = new Set([...document.querySelectorAll(".lvl-chip[aria-pressed=false]")].map(c => c.dataset.level));
  const sel = document.querySelector(".conn-filter");
  const conn = sel ? sel.value : "";
  document.querySelectorAll("[data-level]:not(.lvl-chip)").forEach(el => {
    const names = (el.dataset.connectors || "-").split(" ");
    el.hidden = off.has(el.dataset.level) || (conn !== "" && !names.includes(conn));
  });
  // a file whose records are all hidden
  document.querySelectorAll(".file-records").forEach(card => { card.hidden = !card.querySelector("details[data-level]:not([hidden])"); });
}
document.addEventListener("click", function (ev) {
  const chip = ev.target.closest(".lvl-chip");
  if (!chip) return;
  chip.setAttribute("aria-pressed", chip.getAttribute("aria-pressed") === "false" ? "true" : "false");
  pgApplyFilters();
});
document.addEventListener("change", function (ev) { if (ev.target.closest(".conn-filter")) pgApplyFilters(); });
</script>"""


CONFIG_CSS = ("<style>.cfg-search{font-family:inherit;font-size:.8rem;padding:4px 8px;border-radius:6px;border:1px solid #cbd5e1;"
              "width:100%;max-width:420px;margin:4px 0 10px}table.cfg td:first-child{width:36%}table.cfg td{word-break:break-all}"
              "html[data-theme=dark] .cfg-search{background:#0f172a;color:#cbd5e1;border-color:#334155}</style>")
CONFIG_SCRIPT = """<script>
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


def config_html(configs: List[dict], viewers: Optional[Dict[str, str]] = None) -> str:
    """⚙️ Configuration: one collapsible key / value table per config dump of the logs or config file of the input,
    grouped by config files, components, connector and clients"""
    if not configs:
        return ""
    groups: Dict[Tuple[int, str], List[dict]] = {}
    for c in configs:
        groups.setdefault(config_group(c), []).append(c)
    blocks = []
    for group in sorted(groups):
        blocks.append(f"<h3 style='font-size:.9rem;margin:14px 0 4px'>{e(group[1])} ({len(groups[group])})</h3>")
        # the connector configs first, then by line
        for c in sorted(groups[group], key=lambda c: (not c["title"].endswith("ConnectorConfig"), c["file"], c.get("line") or 0)):
            blocks.append(config_block_html(c, viewers))
    return (f"{CONFIG_CSS}<div class='table-card'><h2>⚙️ Configuration ({len(configs)})</h2>"
            "<p class='legend'>🪵 the configs the components log when they start (<span class='mono'>KafkaConfig values:</span>, "
            "<span class='mono'>DistributedConfig</span>, the config of a connector with its <span class='mono'>[connector|task-0]</span> "
            "context, <span class='mono'>ProducerConfig</span> of a client…, defaults included, the last one of each), "
            "📄 the config files of the input (.properties, connector JSON)</p>"
            "<input class='cfg-search' type='search' placeholder='Filter keys and values…'>"
            f"{''.join(blocks)}</div>{CONFIG_SCRIPT}")


def config_block_html(c: dict, viewers: Optional[Dict[str, str]] = None) -> str:
    """one config: its key / value table, collapsed; viewers: label -> page of the file (log_viewer)"""
    rows = []
    for line in c["text"].splitlines():
        key, _, value = line.partition("=")
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


def filter_html(by_level: Dict[str, int], by_connector: Dict[str, int], without_connector: int) -> str:
    """Chips FATAL / ERROR / WARN with their occurrences when the report has 2 levels or more, and a connector picker
    when records have a connector context"""
    present = [lvl for lvl in LEVEL_ORDER if by_level.get(lvl)]
    parts = []
    if len(present) >= 2:
        parts.append("Levels:" + "".join(f"<button type='button' class='st {lvl.lower()} lvl-chip' data-level='{lvl}' aria-pressed='true' "
                                         f"title='show / hide the {lvl} records'>{lvl} ({by_level[lvl]})</button>" for lvl in present))
    if by_connector:
        options = [f"<option value=''>all ({len(by_connector)} connector(s){' + no connector' if without_connector else ''})</option>"]
        options += [f"<option value='{e(name)}'>{e(name)} ({n})</option>" for name, n in by_connector.items()]
        if without_connector:
            options.append(f"<option value='{NO_CONNECTOR}'>— no connector context — ({without_connector})</option>")
        parts.append(f"<span class='{'sep' if parts else ''}'>Connector:</span><select class='conn-filter' "
                     "title='only the root causes and the records of this connector ([connector|task-0] context of the log line)'>"
                     + "".join(options) + "</select>")
    if not parts:
        return ""
    return FILTER_CSS + "<div class='lvl-filter'>" + "".join(parts) + "</div>" + FILTER_SCRIPT


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


def first_names(names: List[str], top: int = 3) -> str:
    return ", ".join(names[:top]) + (f" (+{len(names) - top} more)" if len(names) > top else "")


def html_report(res: dict, title: str, levels: str, skipped: int, heading: str = "🔥 Log Analysis",
                command: str = "playground analyze logs", unit: str = "file", links: List[Tuple[str, str]] = (),
                sections: List[Tuple[str, str]] = (), viewers: Optional[Dict[str, str]] = None,
                viewers_sanitized: bool = False) -> str:
    """unit: what a label is (file, container, script); links: (label, url) in the header; sections: (title, text)
    shown as is after the findings (the last lines of a failed CI script...); viewers: label -> page of the file
    (log_viewer), the labels and line numbers link to it"""
    viewers = viewers or {}
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
    without_connector = sum(r["count"] for f in res["files"] for r in f["records"] if not r.get("connector"))
    body.append(filter_html(s["by_level"], s["by_connector"], without_connector))
    with_conn = bool(s["by_connector"])
    if res["root_causes"]:
        rows = "".join(f"<tr data-level='{e(c['level'])}'{connectors_attr(c['connectors'], c.get('no_connector', False))}><td>{level_badge(c['level'])}</td><td class='mono' title='{e(c['root_cause'] or '')}'>{e((c['root_cause'] or '—').split('.')[-1])}</td>"
                       f"<td class='mono'>{e(c['example'][:300])}</td><td class='num'>{c['occurrences']}</td>"
                       f"<td class='num'>{c['records']}</td><td class='mono'>{', '.join(log_viewer.link(viewers, x, e(x)) for x in c['files'][:5])}"
                       f"{e(' …' if len(c['files']) > 5 else '')}</td>"
                       + (f"<td class='mono' title='{e(', '.join(c['connectors']))}'>{e(first_names(c['connectors']))}</td>" if with_conn else "")
                       + "</tr>" for c in res["root_causes"])
        body.append("<div class='table-card'><h2>🌳 Root causes (deepest exception of each record)</h2><table><tr><th>Level</th>"
                    "<th>Root cause</th><th>Message</th><th class='num'>Occurrences</th><th class='num'>Records</th>"
                    f"<th>{Unit}s</th>{'<th>Connectors</th>' if with_conn else ''}</tr>"
                    f"{rows}</table></div>")
    if res["files"]:
        rows = "".join(f"<tr><td class='mono'>{log_viewer.link(viewers, f['label'], e(f['label']))}</td><td class='num'>{f['lines']}</td><td class='num'>{f['distinct']}</td>"
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
            title = log_viewer.link(viewers, f["label"], e(f["label"]))
            body.append(f"<div class='table-card file-records'><h2>📄 {title}</h2>"
                        f"{records_html(f['records'], viewers=viewers, label=f['label'])}</div>")
    body.append(config_html(res.get("configuration") or [], viewers))
    meta = [f"&#128196; {e(title)}", f"🕐 {e(span)}", f"Levels: {e(levels)}"]
    if res.get("filter"):
        meta.append(f"🔌 --connector {e(' '.join(res['filter']['connectors']))}" + (" --with-worker" if res["filter"]["with_worker"] else ""))
    meta += [f"<a href='{e(url)}' style='color:#fff'>{e(label)}</a>" for label, url in links]
    return page(f"{heading[2:].strip()} report — {title}", e(heading), meta, "".join(body),
                f"🛠️ Generated by {e(command)} (self-contained, no external resource). Records are cut to 300 "
                "characters per line and to 3 frames of the deepest cause, like the terminal digest; 📋 Show context has the raw "
                "lines around their first occurrence."
                + (f" The file names and line numbers open a copy of the file{' (sanitized)' if viewers_sanitized else ''} "
                   f"in {e(next(iter(viewers.values())).split('/')[0])}/ (✏️ in {e(log_viewer.editor()[0])}, playground config "
                   "editor): keep that folder with the report." if viewers else ""))


def write_viewers(report: str, files: List[dict], res: dict, sources_file: str, sanitize_state: Optional[str]) -> Dict[str, str]:
    """the pages of the files with findings or a configuration (log_viewer), with the lines of their records and
    configs highlighted: label -> href"""
    sources: Dict[str, str] = {}
    try:
        with open(sources_file, encoding="utf-8", errors="replace") as fh:
            for line in fh:
                label, _, path = line.rstrip("\n").partition("\t")
                sources.setdefault(label, path)
    except OSError:
        return {}
    hits: Dict[str, List[int]] = OrderedDict()
    for f in res["files"]:
        hits[f["label"]] = [n for r in f["records"] for n in (r["first_line"], r["last_line"])]
    for c in res.get("configuration") or []:
        hits.setdefault(c["file"], []).extend([c["line"]] if c.get("line") else [])
    path_of = {f["label"]: sources.get(f.get("path", f["label"])) for f in files}
    sanitize = None
    if sanitize_state:
        import sanitizer
        s = sanitizer.DataSanitizer()
        sanitizer._load_state(s, sanitize_state)
        sanitize = s.sanitize_text
    return log_viewer.write_pages(report, [(label, path_of.get(label), lines) for label, lines in hits.items()], sanitize)


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
    ap.add_argument("--sources", metavar="FILE",
                    help="label<tab>path of each file analyzed: with --html-out, the files with findings are copied next to "
                         "the report (<report>-files/) and its locations link to them")
    ap.add_argument("--sanitize-state", metavar="FILE",
                    help="state of tools/report-common/sanitizer.py: the copies of --sources get the same placeholders")
    ap.add_argument("--connector", action="append", default=[], help="keep only the records and configs of this connector")
    ap.add_argument("--with-worker", action="store_true", help="with --connector, also keep what has no connector context")
    ap.add_argument("--text-summary", action="store_true", help="print the bounded text summary of the terminal digest")
    ap.add_argument("--show-config", metavar="NAME", help="print the configs of a connector, config class or client id")
    ap.add_argument("--json-sections", metavar="LIST",
                    help="comma separated sections of the JSON: summary,findings,known_causes,root_causes,files,"
                         "files_without_findings,configuration (default: all)")
    args = ap.parse_args()

    files = parse_records(args.records)
    if args.connector:
        filter_connectors(files, args.connector, args.with_worker)
    res = analyze(files, args.unit)
    if args.connector:
        res["filter"] = {"connectors": args.connector, "with_worker": args.with_worker}
    res["summary"]["binary_files_skipped"] = args.skipped
    res["summary"]["levels"] = args.levels
    if args.json:
        # the timestamps of every occurrence are only for the timeline of the HTML report
        compact = dict(res, files=[dict(f, records=[{k: v for k, v in r.items() if k != "timestamps"} for r in f["records"]])
                                   for f in res["files"]])
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
    if args.html_out:
        with open(args.html_out, "w", encoding="utf-8") as fh:
            sections = []
            for title, path in args.section:
                with open(path, encoding="utf-8", errors="replace") as sf:
                    sections.append((title, sf.read()))
            viewers = write_viewers(args.html_out, files, res, args.sources, args.sanitize_state) if args.sources else {}
            fh.write(html_report(res, args.title, args.levels, args.skipped, args.heading, args.command, args.unit,
                                 [tuple(l) for l in args.link], sections, viewers, bool(args.sanitize_state)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
