#!/usr/bin/env python3
"""The flow of the running connectors: source -> topic -> sinks, for 'playground connector flow'.

  flow.py topics < data.json        the topics to count (one per line)
  flow.py render [--json] < data.json

data.json (built by the command): {"type": "...", "connectors": [{"name", "config", "status", "active_topics",
"lag"}], "counts": {"<topic>": <records or null>}}
"""

import json
import re
import sys

SOURCE_TOPIC_KEYS = ("kafka.topic", "topic", "kafka.topic.name", "topic.name")
STORAGE_SINK_RE = re.compile(r"(S3SinkConnector|S3_SINK|GcsSink|AzureBlob|DataLakeGen[12]|HdfsSinkConnector|Hdfs3SinkConnector)")


def kind(c):
    cfg = c.get("config") or {}
    cls = cfg.get("connector.class", "")
    if cfg.get("topics") or cfg.get("topics.regex") or re.search(r"sink", cls, re.I):
        return "sink"
    return "source"


def sink_topics(c, known):
    cfg = c.get("config") or {}
    topics = [t.strip() for t in (cfg.get("topics") or "").split(",") if t.strip()]
    for p in ((c.get("lag") or {}).get("partitions") or []):
        if p.get("topic") and p["topic"] not in topics:
            topics.append(p["topic"])
    regex = cfg.get("topics.regex")
    if regex:
        try:
            r = re.compile(regex)
            topics += [t for t in known if r.fullmatch(t) and t not in topics]
        except re.error:
            pass
    topics += [t for t in (c.get("active_topics") or []) if t not in topics]
    return topics


def source_topics(c):
    topics = list(c.get("active_topics") or [])
    cfg = c.get("config") or {}
    if not topics:
        for k in SOURCE_TOPIC_KEYS:
            if cfg.get(k) and cfg[k] not in topics:
                topics.append(cfg[k])
    return topics


def dlq(c):
    return (c.get("config") or {}).get("errors.deadletterqueue.topic.name") or None


def graph(data):
    conns = data.get("connectors", [])
    sources = [c for c in conns if kind(c) == "source"]
    sinks = [c for c in conns if kind(c) == "sink"]
    written = {}
    for s in sources:
        for t in source_topics(s):
            written.setdefault(t, []).append(s["name"])
    known = list(written)
    read = {}
    for k in sinks:
        for t in sink_topics(k, known):
            read.setdefault(t, []).append(k["name"])
    return sources, sinks, written, read


def topics(data):
    _, sinks, written, read = graph(data)
    out = list(written) + [t for t in read if t not in written]
    out += [dlq(k) for k in sinks if dlq(k)]
    seen = set()
    for t in out:
        if t not in seen:
            seen.add(t)
            print(t)


def state_icon(status):
    st = (status or {}).get("state", "UNKNOWN")
    tasks = (status or {}).get("tasks") or []
    failed = any(t.get("state") == "FAILED" for t in tasks)
    icon = {"RUNNING": "✅", "PAUSED": "⏸️", "STOPPED": "⏹️", "FAILED": "🛑", "UNASSIGNED": "⌛"}.get(st, "🤔")
    if failed and st == "RUNNING":
        icon = "🛑"
    running = sum(1 for t in tasks if t.get("state") == "RUNNING")
    return "%s %s %d/%d tasks" % (icon, st, running, len(tasks)), (st != "RUNNING" or failed)


def render(data, as_json=False):
    sources, sinks, written, read = graph(data)
    by_name = {c["name"]: c for c in data.get("connectors", [])}
    counts = data.get("counts", {})

    def records(t):
        n = counts.get(t)
        return "? records" if n is None else "%s record%s" % (n, "" if n == 1 else "s")

    def short(c):
        return (c.get("config") or {}).get("connector.class", "?").split(".")[-1]

    def sink_line(name):
        c = by_name[name]
        st, bad = state_icon(c.get("status"))
        lag = c.get("lag") or {}
        parts = [st]
        if lag.get("error"):
            parts.append("lag ?")
        elif lag.get("total_lag") is None:
            parts.append("lag ? (no offset committed yet)")
        else:
            l = lag["total_lag"]
            text = "lag %s" % l
            if l and STORAGE_SINK_RE.search(short(c)):
                text += " (offsets committed when a file is written)"
            parts.append(text + (" ✔️" if l == 0 else " ⏳"))
        d = dlq(c)
        if d:
            n = counts.get(d)
            parts.append("☠️ dlq %s: %s" % (d, "?" if n is None else n))
        return "🔌 %s · %s · %s" % (name, short(c), " · ".join(parts)), bad

    if as_json:
        out = {"connectors": [], "topics": []}
        for c in data.get("connectors", []):
            st, bad = state_icon(c.get("status"))
            out["connectors"].append({
                "name": c["name"], "kind": kind(c), "class": (c.get("config") or {}).get("connector.class"),
                "state": (c.get("status") or {}).get("state"), "healthy": not bad,
                "writes": source_topics(c) if kind(c) == "source" else [],
                "reads": sink_topics(c, list(written)) if kind(c) == "sink" else [],
                "lag": (c.get("lag") or {}).get("total_lag"),
                "dlq": dlq(c), "dlq_records": counts.get(dlq(c)) if dlq(c) else None,
            })
        for t in list(written) + [t for t in read if t not in written]:
            out["topics"].append({"topic": t, "records": counts.get(t), "written_by": written.get(t, []), "read_by": read.get(t, [])})
        print(json.dumps(out, indent=2))
        return 0

    lines = []
    problems = 0
    shown_sinks = set()
    for s in sources:
        st, bad = state_icon(s.get("status"))
        problems += bad
        lines.append("🔌 %s · %s · %s" % (s["name"], short(s), st))
        ts = source_topics(s)
        if not ts:
            lines.append("  └─▶ 🗳 ? (no active topic yet: the source has written nothing, or the worker does not track topics)")
        for i, t in enumerate(ts):
            last_t = i == len(ts) - 1
            lines.append("  %s─▶ 🗳 %s · %s" % ("└" if last_t else "├", t, records(t)))
            readers = read.get(t, [])
            for j, k in enumerate(readers):
                text, bad = sink_line(k)
                problems += bad
                shown_sinks.add(k)
                lines.append("  %s     %s─▶ %s" % (" " if last_t else "│", "└" if j == len(readers) - 1 else "├", text))
        lines.append("")
    orphans = [t for t in read if t not in written]
    for t in orphans:
        lines.append("🗳 %s · %s · no source connector (a producer, or another cluster)" % (t, records(t)))
        readers = read[t]
        for j, k in enumerate(readers):
            text, bad = sink_line(k)
            problems += bad
            shown_sinks.add(k)
            lines.append("  %s─▶ %s" % ("└" if j == len(readers) - 1 else "├", text))
        lines.append("")
    for k in sinks:
        if k["name"] not in shown_sinks:
            text, bad = sink_line(k["name"])
            problems += bad
            lines.append("❔ %s (no topic found in its config)" % text)
    print("\n".join(lines).rstrip())
    return 1 if problems else 0


def main():
    if len(sys.argv) < 2 or sys.argv[1] not in ("topics", "render"):
        print(__doc__, file=sys.stderr)
        sys.exit(2)
    data = json.load(sys.stdin)
    if sys.argv[1] == "topics":
        topics(data)
    else:
        sys.exit(render(data, "--json" in sys.argv))


if __name__ == "__main__":
    main()
